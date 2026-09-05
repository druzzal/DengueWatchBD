import Foundation
import Network
import Observation

/// Keeps the surveillance dataset fresh.
///
/// Refresh is triggered by three things: app launch, the app returning to the
/// foreground, and the network coming back after being unavailable. That last
/// one is the point — the user reconnects and the data updates without being
/// asked to pull anything.
@MainActor
@Observable
final class SurveillanceSync {
    enum Status: Equatable {
        case idle
        case syncing
        case updated(Date)
        case upToDate(Date)
        case offline
        case failed(String)
        /// No endpoint configured, so the bundled dataset is all there is.
        case bundledOnly
    }

    private(set) var status: Status = .idle
    private(set) var isOnline = true
    private(set) var lastSuccessfulSync: Date? {
        didSet {
            UserDefaults.standard.set(lastSuccessfulSync, forKey: Self.lastSyncKey)
        }
    }

    private static let lastSyncKey = "lastSuccessfulSync"

    private let monitor = NWPathMonitor()
    private let cache: SurveillanceCache
    private weak var store: SurveillanceStore?
    private var hasStartedMonitoring = false

    init(cache: SurveillanceCache = SurveillanceCache()) {
        self.cache = cache
        lastSuccessfulSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    func start(store: SurveillanceStore) {
        self.store = store
        guard !hasStartedMonitoring else { return }
        hasStartedMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let nowOnline = path.status == .satisfied
                let wasOffline = !self.isOnline
                self.isOnline = nowOnline
                // Only the offline → online edge triggers a fetch, so a flapping
                // connection doesn't hammer the server.
                if nowOnline && wasOffline {
                    await self.sync(force: false)
                } else if !nowOnline {
                    self.status = .offline
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "bd.denguewatch.network"))
    }

    func stop() {
        monitor.cancel()
        hasStartedMonitoring = false
    }

    /// `force` skips the minimum-interval check — used by the manual refresh.
    func sync(force: Bool) async {
        guard let endpoint = AppConfig.surveillanceEndpoint else {
            status = .bundledOnly
            return
        }
        guard isOnline else {
            status = .offline
            return
        }
        // The throttle asks two questions, not one. Elapsed time alone was
        // enough to skip a sync even when the cache had gone missing, which
        // left the app quietly serving bundled seed data for up to the
        // interval despite a working connection. A skip is only safe if there
        // is actually a cached payload to fall back on.
        if !force, let last = lastSuccessfulSync,
           Date().timeIntervalSince(last) < AppConfig.minimumSyncInterval,
           cache.cachedData != nil {
            status = .upToDate(last)
            return
        }

        status = .syncing
        do {
            let service = RemoteSurveillanceService(endpoint: endpoint,
                                                    validators: cache.validators)
            switch try await service.fetchIfChanged() {
            case .notModified:
                lastSuccessfulSync = Date()
                status = .upToDate(lastSuccessfulSync ?? Date())
            case .updated(let payload, let data, let validators):
                try cache.write(data: data, validators: validators)
                await store?.apply(payload: payload, source: .network)
                lastSuccessfulSync = Date()
                status = .updated(lastSuccessfulSync ?? Date())
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

/// On-disk copy of the last successful download, plus the HTTP validators that
/// let the next request be conditional.
struct SurveillanceCache {
    struct Validators: Codable, Sendable {
        var etag: String?
        var lastModified: String?
    }

    private let directory: URL
    private let payloadURL: URL
    private let validatorsURL: URL

    init() {
        directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        payloadURL = directory.appendingPathComponent("surveillance-cache.json")
        validatorsURL = directory.appendingPathComponent("surveillance-validators.json")
    }

    var validators: Validators {
        guard let data = try? Data(contentsOf: validatorsURL),
              let decoded = try? JSONDecoder().decode(Validators.self, from: data) else {
            return Validators()
        }
        return decoded
    }

    var cachedData: Data? { try? Data(contentsOf: payloadURL) }

    func write(data: Data, validators: Validators) throws {
        try data.write(to: payloadURL, options: .atomic)
        let encoded = try JSONEncoder().encode(validators)
        try encoded.write(to: validatorsURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: payloadURL)
        try? FileManager.default.removeItem(at: validatorsURL)
    }
}
