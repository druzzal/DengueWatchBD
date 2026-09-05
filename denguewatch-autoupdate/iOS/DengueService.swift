import Foundation

/// One day of DGHS figures, as stored in Supabase.
///
/// Supabase returns the column names verbatim, so `CodingKeys` maps snake_case
/// to Swift naming. Optionals mean DGHS did not publish that figure — they are
/// never stand-ins for zero, which is why the columns are nullable rather than
/// defaulted.
struct DengueRecord: Codable, Identifiable, Hashable, Sendable {
    let reportDate: String
    let totalCases24h: Int
    let totalDeaths24h: Int
    let dhakaCases24h: Int?
    let outsideDhakaCases24h: Int?
    let createdAt: String?

    /// `report_date` is the primary key, so it identifies the row.
    var id: String { reportDate }

    enum CodingKeys: String, CodingKey {
        case reportDate = "report_date"
        case totalCases24h = "total_cases_24h"
        case totalDeaths24h = "total_deaths_24h"
        case dhakaCases24h = "dhaka_cases_24h"
        case outsideDhakaCases24h = "outside_dhaka_cases_24h"
        case createdAt = "created_at"
    }

    /// Parsed in Dhaka time so a phone abroad still reads the day DGHS meant.
    var day: Date? { DengueService.dayFormatter.date(from: reportDate) }
}

enum DengueAPIError: LocalizedError, Equatable {
    case notConfigured
    case transport(String)
    case http(status: Int, body: String)
    case decoding(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "The Supabase URL and key have not been configured."
        case .transport(let detail):
            "Could not reach the server: \(detail)"
        case .http(let status, _) where status == 401 || status == 403:
            "The server refused the request. The API key may be wrong or expired."
        case .http(let status, _):
            "The server replied with HTTP \(status)."
        case .decoding(let detail):
            "The response could not be read: \(detail)"
        case .empty:
            "No dengue reports have been published yet."
        }
    }
}

/// Reads DGHS figures straight from Supabase's auto-generated REST API.
///
/// An actor because it owns a small cache and may be called from several
/// screens at once.
///
/// The anon key is compiled into the app and should be treated as public. That
/// is safe here only because Row Level Security grants it SELECT and nothing
/// else — it cannot insert or alter a case count. Never ship the service key.
actor DengueService {

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 6 * 3600)   // Dhaka
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    private var cached: (fetched: Date, record: DengueRecord)?
    private let cacheLifetime: TimeInterval = 5 * 60

    /// - Parameters:
    ///   - projectURL: e.g. `https://abcdefgh.supabase.co`
    ///   - anonKey: the project's anon/public key
    init?(projectURL: String, anonKey: String, session: URLSession = .shared) {
        guard let url = URL(string: projectURL), !anonKey.isEmpty else { return nil }
        self.baseURL = url
        self.anonKey = anonKey
        self.session = session
    }

    /// The most recent reporting day.
    ///
    /// - Parameter allowCached: pass `false` for an explicit pull-to-refresh.
    func latest(allowCached: Bool = true) async throws -> DengueRecord {
        if allowCached, let cached, Date().timeIntervalSince(cached.fetched) < cacheLifetime {
            return cached.record
        }
        let records = try await fetch(limit: 1)
        guard let newest = records.first else { throw DengueAPIError.empty }
        cached = (Date(), newest)
        return newest
    }

    /// Recent days, oldest first — the order a chart plots them in.
    func history(days: Int = 30) async throws -> [DengueRecord] {
        try await fetch(limit: max(1, days)).reversed()
    }

    // MARK: - Transport

    private func fetch(limit: Int) async throws -> [DengueRecord] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/dengue_stats"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "report_date.desc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components?.url else { throw DengueAPIError.notConfigured }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DengueAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DengueAPIError.transport("not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            // PostgREST explains refusals in the body; carrying it makes an
            // RLS misconfiguration diagnosable instead of a bare 401.
            throw DengueAPIError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        do {
            return try JSONDecoder().decode([DengueRecord].self, from: data)
        } catch {
            throw DengueAPIError.decoding(String(describing: error))
        }
    }
}
