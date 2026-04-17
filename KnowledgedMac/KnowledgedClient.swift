import Foundation

// Conforms to ObservableObject so it can be injected via .environmentObject().
// It publishes nothing itself — all state lives in the views.
class KnowledgedClient: ObservableObject {

    private let settings: AppSettings
    private let session  = URLSession.shared
    private let decoder  = JSONDecoder()
    private let encoder  = JSONEncoder()

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(settings: AppSettings) {
        self.settings = settings
        decoder.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            // Try with fractional seconds first, then without.
            let frac = ISO8601DateFormatter()
            frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = frac.date(from: s) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let d = plain.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: try dec.singleValueContainer(),
                debugDescription: "Cannot parse date: \(s)")
        }
    }

    // MARK: - Helpers

    private func baseURL() throws -> URL {
        guard let url = settings.baseURL else {
            throw KCError.invalidURL(settings.serverURL)
        }
        return url
    }

    private func contentURL() throws -> URL {
        try baseURL().appendingPathComponent("content")
    }

    // MARK: - Post

    func postContent(content: String, hint: String, tags: [String]) async throws -> PostResponse {
        var req = URLRequest(url: try contentURL())
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(PostRequest(
            content: content,
            hint:    hint.isEmpty ? nil : hint,
            tags:    tags.isEmpty ? nil : tags
        ))
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decoder.decode(PostResponse.self, from: data)
    }

    // MARK: - Delete

    func deleteContent(path: String) async throws -> PostResponse {
        var req = URLRequest(url: try contentURL())
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(DeleteRequest(path: path))
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decoder.decode(PostResponse.self, from: data)
    }

    // MARK: - Job

    func getJob(id: String) async throws -> JobResponse {
        let url = try baseURL().appendingPathComponent("jobs/\(id)")
        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try decoder.decode(JobResponse.self, from: data)
    }

    /// Polls every 2 s until the job reaches a terminal state.
    func pollUntilDone(id: String) async throws -> JobResponse {
        while true {
            let job = try await getJob(id: id)
            if job.isTerminal { return job }
            try await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: - Retrieve

    func getFile(path: String) async throws -> RawFileResponse {
        var comps = URLComponents(url: try contentURL(), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "path", value: path)]
        let (data, response) = try await session.data(from: comps.url!)
        try validate(response)
        return try decoder.decode(RawFileResponse.self, from: data)
    }

    func query(text: String, mode: RetrieveMode) async throws -> RetrieveResult {
        var comps = URLComponents(url: try contentURL(), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "query", value: text),
            URLQueryItem(name: "mode",  value: mode.rawValue),
        ]
        let (data, response) = try await session.data(from: comps.url!)
        try validate(response)
        switch mode {
        case .synthesize:
            return .synthesis(try decoder.decode(SynthesisResponse.self, from: data))
        case .raw:
            return .rawFiles(try decoder.decode([RawFileResponse].self, from: data))
        }
    }

    // MARK: - Recents

    func recents() async throws -> [RecentEntry] {
        let url = try baseURL().appendingPathComponent("posts/recents")
        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try decoder.decode(RecentsResponse.self, from: data).posts
    }

    // MARK: - Validation

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw KCError.httpError(http.statusCode)
        }
    }
}

// MARK: - Errors

enum KCError: LocalizedError {
    case invalidURL(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid server URL: \(s)"
        case .httpError(let c):  return "Server returned HTTP \(c)"
        }
    }
}
