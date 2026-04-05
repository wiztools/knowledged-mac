import SwiftUI
import UniformTypeIdentifiers

struct RetrieveView: View {
    @EnvironmentObject private var client: KnowledgedClient

    // Input
    @State private var inputMode: InputMode    = .query
    @State private var queryText               = ""
    @State private var filePath                = ""
    @State private var retrieveMode: RetrieveMode = .synthesize

    // State machine
    @State private var state: RetrieveState = .idle

    // Save panel
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    @FocusState private var inputFocused: Bool

    private var canSearch: Bool {
        switch inputMode {
        case .query: return !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .path:  return !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Input bar ────────────────────────────────────────────────
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Picker("", selection: $inputMode) {
                        ForEach(InputMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()

                    if inputMode == .query {
                        TextField("Ask a question…", text: $queryText)
                            .textFieldStyle(.roundedBorder)
                            .focused($inputFocused)
                            .onSubmit(search)
                    } else {
                        TextField("tech/go/goroutines.md", text: $filePath)
                            .textFieldStyle(.roundedBorder)
                            .focused($inputFocused)
                            .onSubmit(search)
                    }

                    Button(action: search) {
                        Image(systemName: "magnifyingglass")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSearch)
                }

                if inputMode == .query {
                    HStack {
                        Text("Mode")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Picker("", selection: $retrieveMode) {
                            ForEach(RetrieveMode.allCases) { m in
                                Text(m.label).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        Spacer()
                    }
                }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))

            Divider()

            // ── Results ──────────────────────────────────────────────────
            Group {
                switch state {
                case .idle:
                    emptyState

                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Retrieving…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .result(let result):
                    resultView(result)

                case .failed(let message):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                        Text(message)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { inputFocused = true }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Enter a query or file path above")
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Result view

    @ViewBuilder
    private func resultView(_ result: RetrieveResult) -> some View {
        VStack(spacing: 0) {
            // Sources bar (shown when there are source paths to display)
            if !result.sources.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(result.sources.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            // Main text content
            ScrollView {
                Text(result.displayText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }

            Divider()

            // Action bar
            HStack {
                Spacer()
                Button(action: { saveToDisk(result) }) {
                    Label("Save to Disk…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(EdgeInsets(top: 8, leading: 14, bottom: 12, trailing: 14))
        }
    }

    // MARK: - Actions

    private func search() {
        guard canSearch else { return }
        state = .loading
        Task {
            do {
                let result: RetrieveResult
                switch inputMode {
                case .query:
                    result = try await client.query(text: queryText, mode: retrieveMode)
                case .path:
                    result = .rawFile(try await client.getFile(path: filePath))
                }
                state = .result(result)
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    private func saveToDisk(_ result: RetrieveResult) {
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.plainText, .text]
        panel.nameFieldStringValue = suggestedFilename(result)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try result.saveText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError    = true
        }
    }

    private func suggestedFilename(_ result: RetrieveResult) -> String {
        switch result {
        case .rawFile(let f):
            return URL(fileURLWithPath: f.path).lastPathComponent
        case .synthesis(let r):
            let slug = r.query
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .prefix(4)
                .joined(separator: "-")
            return "\(slug).md"
        default:
            return "knowledged-export.md"
        }
    }
}
