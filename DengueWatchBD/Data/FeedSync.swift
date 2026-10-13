import Foundation
import Network
import Observation

/// Keeps the dengue figures current.
///
/// A refresh is triggered by three things: app launch, the app returning to the
/// foreground, and the network coming back after being unavailable. That last
/// one is the point — a reader reconnects and the numbers update without them
/// having to pull anything.
///
/// Each refresh asks `summary.json` (~350 bytes) what DGHS's latest report date
/// is. Only when that date is newer than what is already on screen does it
/// download the full `latest.json`.
@MainActor
@Observable
final class FeedSync {
    enum Status: Equatable {
        case idle
        case syncing
        /// New figures landed.
        case updated(Date)
        /// Checked, and DGHS has published nothing newer.
        case upToDate(Date)
        case offline
        case failed(String)
        /// No endpoint configured, so the bundled copy is all there is.
        case bundledOnly
    }

    private(set) var status: Status = .idle
    private(set) var isOnline = true
    private(set) var lastSuccessfulSync: Date? {
        didSet { UserDefaults.standard.set(lastSuccessfulSync, forKey: Self.lastSyncKey) }
    }

    private static let lastSyncKey = "feed.lastSuccessfulSync"

    private let monitor = NWPathMonitor()
    private let cache: FeedCache
    private weak var store: DengueStore?
    private var hasStartedMonitoring = false

    init(cache: FeedCache = FeedCache()) {
        self.cache = cache
        lastSuccessfulSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    func start(store: DengueStore) {
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

    /// Whether this call should talk to the server at all.
    ///
    /// Pure, and separate from `sync`, so the policy can be tested without
    /// standing up a network: this decision is the difference between a reader
    /// seeing today's figures and yesterday's.
    ///
    /// What it gates is the 350-byte probe. The full document has its own gate
    /// — `fetchIfChanged` downloads only when the probe reports a report date
    /// newer than the one on screen — so saying yes here is nearly free.
    ///
    /// Two questions, not one. Elapsed time alone would skip a check even when
    /// the cache had gone missing, leaving the app quietly serving the bundled
    /// seed despite a working connection. A skip is only safe when there is
    /// actually a cached payload to fall back on.
    static func shouldProbe(force: Bool,
                            lastSuccess: Date?,
                            hasCachedPayload: Bool,
                            now: Date = Date()) -> Bool {
        if force { return true }
        guard let lastSuccess, hasCachedPayload else { return true }
        let elapsed = now.timeIntervalSince(lastSuccess)
        // A stored time in the future means the clock moved backwards — a
        // manual change, a timezone correction on a phone that had drifted.
        // Comparing against it would hold the check off until the clock caught
        // up, which could be a day, and the reader would have no way to tell
        // why the figures had stopped moving.
        guard elapsed >= 0 else { return true }
        return elapsed >= FeedConfig.minimumProbeInterval
    }

    /// `force` skips the probe floor — used by pull-to-refresh.
    func sync(force: Bool) async {
        // Launch and the first scene activation both ask within the same
        // moment; the second would only repeat the first one's requests.
        guard status != .syncing else { return }
        guard let summaryEndpoint = FeedConfig.summaryEndpoint,
              let latestEndpoint = FeedConfig.latestEndpoint else {
            status = .bundledOnly
            return
        }
        guard isOnline else {
            status = .offline
            return
        }
        if !Self.shouldProbe(force: force,
                             lastSuccess: lastSuccessfulSync,
                             hasCachedPayload: cache.cachedData != nil),
           let last = lastSuccessfulSync {
            status = .upToDate(last)
            return
        }

        status = .syncing
        do {
            let service = RemoteFeedService(summaryEndpoint: summaryEndpoint,
                                            latestEndpoint: latestEndpoint,
                                            validators: cache.validators)
            let known = store?.meta?.lastUpdated
            switch try await service.fetchIfChanged(knownReportDate: known) {
            case .notModified(let reportDate):
                // The server can say "nothing new" about a document this screen
                // has never seen: a background refresh in this same process
                // downloads into the cache, with its own store, and saves the
                // new ETag. The next request here sends that ETag, gets a 304,
                // and without this the reader keeps the old figures until the
                // app is killed. The cache is the newer copy, so read it.
                if let reportDate, reportDate != store?.meta?.lastUpdated {
                    await store?.refresh()
                }
                lastSuccessfulSync = Date()
                status = .upToDate(lastSuccessfulSync ?? Date())
            case .updated(let document, let data, let validators):
                try cache.write(data: data, validators: validators)
                await store?.apply(document: document, source: .network)
                lastSuccessfulSync = Date()
                status = .updated(lastSuccessfulSync ?? Date())
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
