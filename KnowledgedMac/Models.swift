import Foundation

// MARK: - Post

struct PostRequest: Encodable {
    let content: String
    let hint: String?
    let tags: [String]?
}

struct PostResponse: Decodable {
    let jobId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
    }
}

// MARK: - Job

struct JobResponse: Decodable {
    let jobId:  String
    let status: String
    let path:   String?
    let error:  String?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status, path, error
    }

    var isTerminal: Bool { status == "done" || status == "failed" }
}

// MARK: - Content

struct RawFileResponse: Decodable {
    let path:    String
    let content: String
}

struct SynthesisResponse: Decodable {
    let query:   String
    let sources: [String]
    let answer:  String
}

// MARK: - Retrieve UI abstractions

enum RetrieveMode: String, CaseIterable, Identifiable {
    case synthesize, raw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .synthesize: return "Synthesize"
        case .raw:        return "Raw Docs"
        }
    }
}

enum InputMode: String, CaseIterable, Identifiable {
    case query, path

    var id: String { rawValue }

    var label: String {
        switch self {
        case .query: return "Query"
        case .path:  return "File Path"
        }
    }
}

enum RetrieveResult {
    case synthesis(SynthesisResponse)
    case rawFiles([RawFileResponse])
    case rawFile(RawFileResponse)

    /// Plain text suitable for saving to disk.
    var saveText: String {
        switch self {
        case .synthesis(let r):
            var out = r.answer
            if !r.sources.isEmpty {
                out += "\n\n---\nSources: \(r.sources.joined(separator: ", "))"
            }
            return out
        case .rawFiles(let files):
            return files.map { "=== \($0.path) ===\n\($0.content)" }
                        .joined(separator: "\n\n---\n\n")
        case .rawFile(let f):
            return f.content
        }
    }

    /// Paths of all documents contributing to this result.
    var sources: [String] {
        switch self {
        case .synthesis(let r): return r.sources
        case .rawFiles(let fs): return fs.map(\.path)
        case .rawFile(let f):   return [f.path]
        }
    }

    /// Primary display text shown in the results area.
    var displayText: String {
        switch self {
        case .synthesis(let r): return r.answer
        case .rawFiles(let fs): return fs.map { "=== \($0.path) ===\n\($0.content)" }
                                         .joined(separator: "\n\n---\n\n")
        case .rawFile(let f):   return f.content
        }
    }
}

// MARK: - Post state machine

enum PostState: Equatable {
    case idle
    case posting
    case queued(jobId: String)
    case polling(jobId: String)
    case done(path: String)
    case failed(message: String)
}

// MARK: - Retrieve state machine

enum RetrieveState {
    case idle
    case loading
    case result(RetrieveResult)
    case failed(message: String)
}
