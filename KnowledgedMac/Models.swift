import Foundation

// MARK: - Delete

struct DeleteRequest: Encodable {
    let path: String
}

// MARK: - Edit

struct EditRequest: Encodable {
    let path: String
    let content: String
    let title: String?
    let description: String?
    let tags: [String]?
}

struct MarkdownFrontmatter {
    var title = ""
    var description = ""
    var tags: [String] = []
    var created = ""
    var modified = ""
    var body: String

    static func parse(_ content: String) throws -> MarkdownFrontmatter {
        guard content.hasPrefix("---\n") || content.hasPrefix("---\r\n") else {
            throw MarkdownFrontmatterError.missingOpeningDelimiter
        }

        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first == "---" else {
            throw MarkdownFrontmatterError.missingOpeningDelimiter
        }

        var closingIndex: Int?
        for index in lines.indices.dropFirst() where lines[index] == "---" {
            closingIndex = index
            break
        }
        guard let closingIndex else {
            throw MarkdownFrontmatterError.missingClosingDelimiter
        }

        let header = lines[1..<closingIndex]
        let rawBody = lines.dropFirst(closingIndex + 1).joined(separator: "\n")
        var fm = MarkdownFrontmatter(body: rawBody.trimmingLeadingNewlines())

        for line in header {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "title":
                fm.title = unquoteYAMLScalar(value)
            case "description":
                fm.description = unquoteYAMLScalar(value)
            case "tags":
                fm.tags = parseYAMLStringList(value)
            case "created":
                fm.created = unquoteYAMLScalar(value)
            case "modified":
                fm.modified = unquoteYAMLScalar(value)
            default:
                continue
            }
        }
        return fm
    }
}

enum MarkdownFrontmatterError: LocalizedError {
    case missingOpeningDelimiter
    case missingClosingDelimiter

    var errorDescription: String? {
        switch self {
        case .missingOpeningDelimiter:
            return "Document is missing YAML frontmatter."
        case .missingClosingDelimiter:
            return "Document has unterminated YAML frontmatter."
        }
    }
}

private func unquoteYAMLScalar(_ raw: String) -> String {
    guard raw.count >= 2 else { return raw }
    if raw.hasPrefix("\""), raw.hasSuffix("\"") {
        let inner = raw.dropFirst().dropLast()
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
    if raw.hasPrefix("'"), raw.hasSuffix("'") {
        return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
    }
    return raw
}

private func parseYAMLStringList(_ raw: String) -> [String] {
    guard raw.hasPrefix("["), raw.hasSuffix("]") else { return [] }
    let inner = raw.dropFirst().dropLast()
    return inner.split(separator: ",")
        .map { unquoteYAMLScalar($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .filter { !$0.isEmpty }
}

private extension String {
    func trimmingLeadingNewlines() -> String {
        var out = self
        while out.hasPrefix("\n") {
            out.removeFirst()
        }
        return out
    }
}

// MARK: - Post

struct PostRequest: Encodable {
    let content: String
    let hint: String?
    let title: String?
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

// MARK: - Ask

struct AskRequest: Encodable {
    let question: String
}

struct AskResponse: Decodable {
    let question: String
    let answer: String
    let tags: [String]
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

    var frontmatter: MarkdownFrontmatter? {
        try? MarkdownFrontmatter.parse(content)
    }

    var bodyContent: String {
        frontmatter?.body ?? content
    }
}

struct SynthesisResponse: Decodable {
	let query:   String
	let sources: [String]
	let answer:  String
}

// MARK: - Tags

struct TagSummary: Decodable, Identifiable {
	let tag:   String
	let count: Int

	var id: String { tag }
}

struct TagsResponse: Decodable {
	let tags: [TagSummary]
}

struct TaggedDocument: Decodable, Identifiable {
	let path:        String
	let title:       String
	let description: String
	let tags:        [String]
	let modified:    Date

	var id: String { path }
}

// MARK: - Tag browser state machine

enum TagsState {
	case idle
	case loading
	case loaded([TagSummary])
	case failed(message: String)
}

enum TaggedDocumentsState {
	case idle
	case loading
	case loaded([TaggedDocument])
	case failed(message: String)
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
        case .rawFiles(let fs): return fs.map { "=== \($0.path) ===\n\($0.bodyContent)" }
                                         .joined(separator: "\n\n---\n\n")
        case .rawFile(let f):   return f.bodyContent
        }
    }

    var frontmatter: MarkdownFrontmatter? {
        switch self {
        case .rawFile(let f): return f.frontmatter
        case .synthesis, .rawFiles: return nil
        }
    }

    var pdfExportDocument: PDFExportDocument {
        switch self {
        case .rawFile(let f):
            let frontmatter = f.frontmatter
            return PDFExportDocument(
                title: frontmatter?.title,
                description: frontmatter?.description,
                tags: frontmatter?.tags ?? [],
                created: frontmatter?.created,
                modified: frontmatter?.modified,
                sourcePath: f.path,
                markdownBody: f.bodyContent
            )
        case .synthesis(let r):
            return PDFExportDocument(
                title: r.query,
                description: nil,
                tags: [],
                created: nil,
                modified: nil,
                sourcePath: nil,
                markdownBody: saveText
            )
        case .rawFiles:
            return PDFExportDocument(
                title: nil,
                description: nil,
                tags: [],
                created: nil,
                modified: nil,
                sourcePath: nil,
                markdownBody: displayText
            )
        }
    }

    var editablePath: String? {
        switch self {
        case .rawFile(let f):   return f.path
        case .synthesis, .rawFiles: return nil
        }
    }
}

struct PDFExportDocument {
    let title: String?
    let description: String?
    let tags: [String]
    let created: String?
    let modified: String?
    let sourcePath: String?
    let markdownBody: String
}

// MARK: - Recents

struct RecentEntry: Decodable, Identifiable {
    let jobId:     String
    let path:      String
    let tags:      [String]?
    let createdAt: Date

    var id: String { jobId }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case path, tags
        case createdAt = "created_at"
    }
}

struct RecentsResponse: Decodable {
    let posts: [RecentEntry]
}

// MARK: - Recents state machine

enum RecentsState {
    case idle
    case loading
    case loaded([RecentEntry])
    case failed(message: String)
}

// MARK: - Delete state machine

enum DeleteState: Equatable {
    case idle
    case deleting
    case queued(jobId: String)
    case polling(jobId: String)
    case done(path: String)
    case failed(message: String)
}

// MARK: - Edit state machine

enum EditState: Equatable {
    case idle
    case loading
    case loaded
    case saving
    case queued(jobId: String)
    case polling(jobId: String)
    case done(path: String)
    case failed(message: String)
}

// MARK: - Ask state machine

enum AskState: Equatable {
    case idle
    case asking
    case failed(message: String)
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
