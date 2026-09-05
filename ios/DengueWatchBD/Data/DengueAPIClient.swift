import Foundation

/// Client for the DengueWatch REST API.
///
/// Separate from `SurveillanceService`, which fetches the published
/// `surveillance.json`. Both exist on purpose: the static file is the app's
/// primary source because it is served from a CDN, needs no server to be up,
/// and carries the ingestion pipeline's validation. This client is for the
/// queries a static file cannot answer — one district's history, an arbitrary
/// window — and reaches a database that can be down.
///
/// The JSON uses camelCase keys matching these property names exactly, so no
/// `CodingKeys` are needed. Optionals mean DGHS did not publish the figure;
/// they never stand in for zero.
struct DengueAPIClient: Sendable {

    // MARK: - Wire types

    struct RegionalBreakdown: Codable, Hashable, Sendable {
        var divisionName: String?
        var districtName: String
        var cases24h: Int
        var deaths24h: Int
    }

    struct DailySummary: Codable, Hashable, Sendable {
        var reportDate: String
        var totalCases24h: Int
        var totalDeaths24h: Int
        var totalCasesYtd: Int?
        var totalDeathsYtd: Int?
        var dhakaCityCases24h: Int?
        var outsideDhakaCases24h: Int?
        var regionalBreakdowns: [RegionalBreakdown]

        /// `reportDate` stays a `String` on the wire so decoding cannot fail on
        /// a date format, and is parsed only where a `Date` is actually needed.
        var day: Date? { DengueAPIClient.dayFormatter.date(from: reportDate) }
    }

    struct HistoryPoint: Codable, Hashable, Sendable, Identifiable {
        var reportDate: String
        var totalCases24h: Int
        var totalDeaths24h: Int

        var id: String { reportDate }
        var day: Date? { DengueAPIClient.dayFormatter.date(from: reportDate) }
    }

    struct DistrictPoint: Codable, Hashable, Sendable, Identifiable {
        var reportDate: String
        var districtName: String
        var divisionName: String?
        var cases24h: Int
        var deaths24h: Int

        var id: String { reportDate + districtName }
        var day: Date? { DengueAPIClient.dayFormatter.date(from: reportDate) }
    }

    enum APIError: LocalizedError, Equatable {
        case notConfigured
        case http(Int)
        case decoding(String)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "No API base URL is configured."
            case .http(let code): "The server replied with HTTP \(code)."
            case .decoding(let detail): "The response could not be read: \(detail)"
            case .transport(let detail): "The server could not be reached: \(detail)"
            }
        }
    }

    // MARK: - Configuration

    /// Fixed to Dhaka so a phone travelling abroad still parses DGHS reporting
    /// days as the days DGHS meant.
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 6 * 3600)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var baseURL: URL?
    var session: URLSession = .shared

    // MARK: - Endpoints

    func latest() async throws -> DailySummary {
        try await get("api/v1/dengue/latest", query: [])
    }

    func history(days: Int = 30) async throws -> [HistoryPoint] {
        try await get("api/v1/dengue/history",
                      query: [URLQueryItem(name: "days", value: String(days))])
    }

    func district(_ name: String, days: Int = 90) async throws -> [DistrictPoint] {
        // Percent-encoded because district names contain spaces and brackets,
        // e.g. "Dhaka (Out of CC)".
        let encoded = name.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) ?? name
        return try await get("api/v1/dengue/districts/\(encoded)",
                             query: [URLQueryItem(name: "days", value: String(days))])
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        guard let baseURL,
              var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                             resolvingAgainstBaseURL: false)
        else { throw APIError.notConfigured }

        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.notConfigured }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
