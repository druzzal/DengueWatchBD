import Foundation

enum FeedError: LocalizedError {
    case missingResource
    case decoding(String)
    case badResponse(Int)
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            "The dengue dataset bundled with the app is missing."
        case .decoding(let detail):
            "The dengue dataset could not be read: \(detail)"
        case .badResponse(let code):
            "The data feed returned HTTP \(code)."
        case .unsupportedSchema(let version):
            "This feed uses format version \(version), which this version of the app cannot read. Update the app."
        }
    }
}

/// Decoding shared by every path, so the bundled copy and a download can never
/// disagree about how the same bytes are read.
enum FeedDecoder {
    static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func document(from data: Data) throws -> FeedDocument {
        do {
            let document = try make().decode(FeedDocument.self, from: data)
            guard FeedConfig.supportedSchemaVersions.contains(document.schemaVersion) else {
                throw FeedError.unsupportedSchema(document.schemaVersion)
            }
            return document
        } catch let error as FeedError {
            throw error
        } catch {
            throw FeedError.decoding(error.localizedDescription)
        }
    }

    static func summary(from data: Data) throws -> FeedSummaryDocument {
        do {
            return try make().decode(FeedSummaryDocument.self, from: data)
        } catch {
            throw FeedError.decoding(error.localizedDescription)
        }
    }
}

/// Reads the newest dataset available without touching the network: the cached
/// download if there is one, otherwise the copy shipped inside the app.
struct BundledFeedService {
    var resourceName = "dengue-feed"
    var cache = FeedCache()

    func load() throws -> FeedDocument {
        if let cached = cache.cachedData,
           let document = try? FeedDecoder.document(from: cached) {
            return document
        }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            throw FeedError.missingResource
        }
        return try FeedDecoder.document(from: try Data(contentsOf: url))
    }

    /// True when what we are serving came from a download rather than the bundle.
    var isServingDownloadedData: Bool { cache.cachedData != nil }
}

/// Fetches the published feed.
///
/// Two-step on purpose. `summary.json` is ~350 bytes and carries the DGHS report
/// date; `latest.json` is ~40 KB. Asking the small one first means a day when
/// DGHS published nothing new costs a few hundred bytes instead of forty
/// kilobytes — which matters on the metered mobile connections most of this
/// app's readers are on. Conditional GETs make an unchanged file cheaper still.
struct RemoteFeedService {
    enum Outcome {
        /// Neither the report date nor the bytes changed.
        case notModified(reportDate: String?)
        /// A newer report is published; the full document came with it.
        case updated(FeedDocument, Data, FeedCache.Validators)
    }

    let summaryEndpoint: URL
    let latestEndpoint: URL
    var validators = FeedCache.Validators()

    /// - Parameter knownReportDate: the report date already on screen. When the
    ///   feed still reports this date, the large document is not downloaded.
    func fetchIfChanged(knownReportDate: String?) async throws -> Outcome {
        let summary = try await fetchSummary()
        if let knownReportDate,
           let published = summary.lastUpdated,
           published == knownReportDate {
            return .notModified(reportDate: published)
        }
        return try await fetchLatest(reportDate: summary.lastUpdated)
    }

    func fetchSummary() async throws -> FeedSummaryDocument {
        var request = URLRequest(url: summaryEndpoint)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        return try FeedDecoder.summary(from: data)
    }

    private func fetchLatest(reportDate: String?) async throws -> Outcome {
        var request = URLRequest(url: latestEndpoint)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = validators.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedError.badResponse(-1)
        }
        if http.statusCode == 304 { return .notModified(reportDate: reportDate) }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedError.badResponse(http.statusCode)
        }

        let document = try FeedDecoder.document(from: data)
        let fresh = FeedCache.Validators(
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified")
        )
        return .updated(document, data, fresh)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw FeedError.badResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedError.badResponse(http.statusCode)
        }
    }
}

/// On-disk copy of the last successful download, plus the HTTP validators that
/// let the next request be conditional.
struct FeedCache {
    struct Validators: Codable, Sendable {
        var etag: String?
        var lastModified: String?
    }

    private let payloadURL: URL
    private let validatorsURL: URL

    init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        payloadURL = directory.appendingPathComponent("dengue-feed-cache.json")
        validatorsURL = directory.appendingPathComponent("dengue-feed-validators.json")
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
        try JSONEncoder().encode(validators).write(to: validatorsURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: payloadURL)
        try? FileManager.default.removeItem(at: validatorsURL)
    }
}
