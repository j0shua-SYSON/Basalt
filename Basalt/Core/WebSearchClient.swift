import Foundation

enum WebSearchProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case brave
    case searxng

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brave: "Brave Search"
        case .searxng: "SearXNG"
        }
    }
}

struct WebSearchConfiguration: Sendable {
    let provider: WebSearchProvider
    let braveAPIKey: String
    let searxngEndpoint: String
}

enum WebSearchError: LocalizedError {
    case missingBraveKey
    case invalidSearxNGEndpoint
    case httpStatus(Int)
    case noResults

    var errorDescription: String? {
        switch self {
        case .missingBraveKey:
            "Add a Brave Search API key in Settings before using web search."
        case .invalidSearxNGEndpoint:
            "Add a valid HTTPS SearXNG server in Settings. Its JSON format must be enabled."
        case let .httpStatus(code):
            "The search provider returned HTTP \(code)."
        case .noResults:
            "The search provider did not return any web results."
        }
    }
}

struct WebSearchClient: Sendable {
    func search(
        query: String,
        configuration: WebSearchConfiguration,
        limit: Int = 5
    ) async throws -> [WebSource] {
        switch configuration.provider {
        case .brave:
            return try await searchBrave(
                query: query,
                apiKey: configuration.braveAPIKey,
                limit: limit
            )
        case .searxng:
            return try await searchSearxNG(
                query: query,
                endpoint: configuration.searxngEndpoint,
                limit: limit
            )
        }
    }

    private func searchBrave(query: String, apiKey: String, limit: Int) async throws -> [WebSource] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw WebSearchError.missingBraveKey }

        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: String(query.prefix(400))),
            URLQueryItem(name: "count", value: String(min(10, max(1, limit)))),
            URLQueryItem(name: "safesearch", value: "moderate")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(trimmedKey, forHTTPHeaderField: "X-Subscription-Token")

        let (data, response) = try await ephemeralSession.data(for: request)
        try Self.validate(response)
        let payload = try JSONDecoder().decode(BraveResponse.self, from: data)
        let sources = (payload.web?.results ?? []).prefix(limit).compactMap { result -> WebSource? in
            guard let url = URL(string: result.url) else { return nil }
            return WebSource(
                title: Self.clean(result.title),
                url: url,
                snippet: Self.clean(result.description)
            )
        }
        guard !sources.isEmpty else { throw WebSearchError.noResults }
        return sources
    }

    private func searchSearxNG(query: String, endpoint: String, limit: Int) async throws -> [WebSource] {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host != nil
        else {
            throw WebSearchError.invalidSearxNGEndpoint
        }

        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/search") { path += "/search" }
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "safesearch", value: "1")
        ]
        guard let url = components.url else { throw WebSearchError.invalidSearxNGEndpoint }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await ephemeralSession.data(for: request)
        try Self.validate(response)
        let payload = try JSONDecoder().decode(SearxNGResponse.self, from: data)
        let sources = payload.results.prefix(limit).compactMap { result -> WebSource? in
            guard let url = URL(string: result.url) else { return nil }
            return WebSource(
                title: Self.clean(result.title),
                url: url,
                snippet: Self.clean(result.content ?? "")
            )
        }
        guard !sources.isEmpty else { throw WebSearchError.noResults }
        return sources
    }

    private var ephemeralSession: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard 200..<300 ~= http.statusCode else {
            throw WebSearchError.httpStatus(http.statusCode)
        }
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct BraveResponse: Decodable {
    let web: WebResults?

    struct WebResults: Decodable {
        let results: [Result]
    }

    struct Result: Decodable {
        let title: String
        let url: String
        let description: String
    }
}

private struct SearxNGResponse: Decodable {
    let results: [Result]

    struct Result: Decodable {
        let url: String
        let title: String
        let content: String?
    }
}

