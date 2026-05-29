import SwiftUI

@MainActor
final class EditDraft: ObservableObject {
    @Published var path = ""
    @Published var content = ""
    @Published var originalContent = ""
    @Published var title = ""
    @Published var originalTitle = ""
    @Published var description = ""
    @Published var originalDescription = ""
    @Published var tags = ""
    @Published var originalTags: [String] = []
    @Published var editState: EditState = .idle
    @Published var showPreview = false
}

struct EditView: View {
    @EnvironmentObject private var client:   KnowledgedClient
    @EnvironmentObject private var navState: NavigationState

    @ObservedObject var draft: EditDraft

    @FocusState private var pathFocused: Bool
    @FocusState private var contentFocused: Bool

    private var trimmedPath: String {
        draft.path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPath: Bool { !trimmedPath.isEmpty }

    private var canLoad: Bool {
        hasPath && draft.editState != .loading && draft.editState != .saving && !isPolling
    }

    private var canSave: Bool {
        hasPath
            && draft.editState == .loaded
            && (contentChanged || titleChanged || descriptionChanged || tagsChanged)
    }

    private var parsedTags: [String] {
        draft.tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var contentChanged: Bool {
        draft.content != draft.originalContent
            && !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var titleChanged: Bool {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != draft.originalTitle
    }

    private var descriptionChanged: Bool {
        let trimmed = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != draft.originalDescription
    }

    private var tagsChanged: Bool {
        !parsedTags.isEmpty && parsedTags != draft.originalTags
    }

    private var isPolling: Bool {
        if case .queued = draft.editState { return true }
        if case .polling = draft.editState { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("tech/go/goroutines.md", text: $draft.path)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .focused($pathFocused)
                        .onSubmit { if canLoad { load() } }

                    Button(action: load) {
                        Label("Load", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canLoad)
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Title")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        TextField("Frontmatter title", text: $draft.title)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Description")
                            .foregroundStyle(.secondary)
                        TextField("Frontmatter description", text: $draft.description)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Tags")
                            .foregroundStyle(.secondary)
                        TextField("Comma-separated tags", text: $draft.tags)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))

            Divider()

            editorArea

            Divider()

            HStack(spacing: 12) {
                MarkdownPreviewToggle(isPreviewing: $draft.showPreview)
                    .disabled(draft.editState == .idle || draft.editState == .loading)
                statusBadge
                Spacer()
                Button(action: save) {
                    Label("Save", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16))
        }
        .onAppear {
            pathFocused = true
            applyPendingFilePath()
        }
        .onChange(of: navState.editFilePath) {
            applyPendingFilePath()
        }
        .onChange(of: draft.showPreview) {
            if !draft.showPreview {
                contentFocused = true
            }
        }
    }

    @ViewBuilder
    private var editorArea: some View {
        switch draft.editState {
        case .idle:
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Load a Markdown document to edit")
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        default:
            ZStack(alignment: .topLeading) {
                Color(nsColor: .textBackgroundColor)
                if draft.showPreview {
                    MarkdownWebView(markdown: draft.content)
                        .padding(14)
                } else {
                    TextEditor(text: $draft.content)
                        .font(.body.monospaced())
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .focused($contentFocused)
                        .disabled(draft.editState != .loaded)
                        .onKeyPress(.return, phases: .down) { press in
                            guard press.modifiers.contains(.command), canSave else {
                                return .ignored
                            }
                            save()
                            return .handled
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch draft.editState {
        case .idle, .loaded:
            EmptyView()

        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading…").foregroundStyle(.secondary)
            }

        case .saving:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Saving…").foregroundStyle(.secondary)
            }

        case .queued(let id):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Queued · \(shortID(id))")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

        case .polling(let id):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Committing · \(shortID(id))")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

        case .done(let editedPath):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(editedPath) saved")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func applyPendingFilePath() {
        guard let pending = navState.editFilePath else { return }
        draft.path = pending
        navState.editFilePath = nil
        load()
    }

    private func load() {
        guard canLoad else { return }
        let requestedPath = trimmedPath
        draft.editState = .loading

        Task {
            do {
                let file = try await client.getFile(path: requestedPath)
                let parsed = try MarkdownFrontmatter.parse(file.content)
                draft.path = file.path
                draft.content = parsed.body
                draft.originalContent = parsed.body
                draft.title = parsed.title
                draft.originalTitle = parsed.title
                draft.description = parsed.description
                draft.originalDescription = parsed.description
                draft.tags = parsed.tags.joined(separator: ", ")
                draft.originalTags = parsed.tags
                draft.editState = .loaded
                contentFocused = true
            } catch {
                draft.editState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let savePath = trimmedPath
        let saveContent = contentChanged ? draft.content : ""
        let saveTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let saveDescription = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let saveTags = tagsChanged ? parsedTags : []
        let effectiveTitle = saveTitle.isEmpty ? draft.originalTitle : saveTitle
        let effectiveDescription = saveDescription.isEmpty ? draft.originalDescription : saveDescription
        draft.editState = .saving

        Task {
            do {
                let response = try await client.editContent(
                    path:        savePath,
                    content:     saveContent,
                    title:       saveTitle,
                    description: saveDescription,
                    tags:        saveTags
                )
                draft.editState = .queued(jobId: response.jobId)

                draft.editState = .polling(jobId: response.jobId)
                let job = try await client.pollUntilDone(id: response.jobId)

                if job.status == "done" {
                    let editedPath = job.path ?? savePath
                    draft.path = editedPath
                    draft.originalContent = draft.content
                    draft.originalTitle = effectiveTitle
                    draft.originalDescription = effectiveDescription
                    if !saveTags.isEmpty {
                        draft.originalTags = saveTags
                        draft.tags = saveTags.joined(separator: ", ")
                    } else {
                        draft.tags = draft.originalTags.joined(separator: ", ")
                    }
                    draft.title = draft.originalTitle
                    draft.description = draft.originalDescription
                    draft.editState = .done(path: editedPath)
                    resetLoadedAfterDelay()
                } else {
                    draft.editState = .failed(message: job.error ?? "Job failed")
                }
            } catch {
                draft.editState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func resetLoadedAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            if case .done = draft.editState {
                draft.editState = .loaded
                contentFocused = true
            }
        }
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }
}
