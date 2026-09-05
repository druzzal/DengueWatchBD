import Foundation

/// Where surveillance data comes from.
protocol SurveillanceService: Sendable {
    func fetch() async throws -> SurveillancePayload
}

enum SurveillanceError: LocalizedError {
    case missingResource
    case decoding(String)
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .missingResource: "The bundled surveillance dataset is missing from the app."
        case .decoding(let detail): "The surveillance dataset could not be read: \(detail)"
        case .badResponse(let code): "The data server returned HTTP \(code)."
        }
    }
}

/// Reads the newest dataset available without touching the network: the cached
/// download if one exists, otherwise the copy shipped inside the app.
struct LocalSurveillanceService: SurveillanceService {
    var resourceName = "surveillance"
    var cache = SurveillanceCache()

    func fetch() async throws -> SurveillancePayload {
        if let cached = cache.cachedData,
           let payload = try? JSONDecoder().decode(SurveillancePayload.self, from: cached) {
            return payload
        }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            throw SurveillanceError.missingResource
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(SurveillancePayload.self, from: data)
        } catch {
            throw SurveillanceError.decoding(error.localizedDescription)
        }
    }

    /// True when the data being served came from a download rather than the bundle.
    var isServingDownloadedData: Bool { cache.cachedData != nil }
}

/// Fetches from a DGHS-shaped endpoint using a conditional GET, so a daily
/// refresh over a metered connection costs almost nothing when the file has not
/// changed.
struct RemoteSurveillanceService: SurveillanceService {
    enum Outcome {
        case notModified
        case updated(SurveillancePayload, Data, SurveillanceCache.Validators)
    }

    let endpoint: URL
    var validators = SurveillanceCache.Validators()

    func fetch() async throws -> SurveillancePayload {
        switch try await fetchIfChanged() {
        case .updated(let payload, _, _): return payload
        case .notModified: throw SurveillanceError.badResponse(304)
        }
    }

    func fetchIfChanged() async throws -> Outcome {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = validators.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SurveillanceError.badResponse(-1)
        }
        if http.statusCode == 304 { return .notModified }
        guard (200..<300).contains(http.statusCode) else {
            throw SurveillanceError.badResponse(http.statusCode)
        }

        do {
            let payload = try JSONDecoder().decode(SurveillancePayload.self, from: data)
            let fresh = SurveillanceCache.Validators(
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified")
            )
            return .updated(payload, data, fresh)
        } catch {
            throw SurveillanceError.decoding(error.localizedDescription)
        }
    }
}
