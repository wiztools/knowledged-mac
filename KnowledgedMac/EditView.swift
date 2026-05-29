import SwiftUI

struct EditView: View {
    @EnvironmentObject private var client:   KnowledgedClient
    @EnvironmentObject private var navState: NavigationState

    @State private var path = ""
    @State private var content = ""
    @State private var originalContent = ""
    @State private var title = ""
    @State private var originalTitle = ""
    @State private var description = ""
    @State private var originalDescription = ""
    @State private var tags = ""
    @State private var originalTags: [String] = []
    @State private var editState: EditState = .idle
    @State private var showPreview = false

    @FocusState private var pathFocused: Bool
    @FocusState private var contentFocused: Bool

    private var trimmedPath: String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPath: Bool { !trimmedPath.isEmpty }

    private var canLoad: Bool {
        hasPath && editState != .loading && editState != .saving && !isPolling
    }

    private var canSave: Bool {
        hasPath
            && editState == .loaded
            && (contentChanged || titleChanged || descriptionChanged || tagsChanged)
    }

    private var parsedTags: [String] {
        tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var contentChanged: Bool {
        content != originalContent
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var titleChanged: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != originalTitle
    }

    private var descriptionChanged: Bool {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != originalDescription
    }

    private var tagsChanged: Bool {
        !parsedTags.isEmpty && parsedTags != originalTags
    }

    private var isPolling: Bool {
        if case .queued = editState { return true }
        if case .polling = editState { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("tech/go/goroutines.md", text: $path)
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
                        TextField("Frontmatter title", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Description")
                            .foregroundStyle(.secondary)
                        TextField("Frontmatter description", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Tags")
                            .foregroundStyle(.secondary)
                        TextField("Comma-separated tags", text: $tags)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))

            Divider()

            editorArea

            Divider()

            HStack(spacing: 12) {
                MarkdownPreviewToggle(isPreviewing: $showPreview)
                    .disabled(editState == .idle || editState == .loading)
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
        .onChange(of: showPreview) {
            if !showPreview {
                contentFocused = true
            }
        }
    }

    @ViewBuilder
    private var editorArea: some View {
        switch editState {
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
                if showPreview {
                    MarkdownWebView(markdown: content)
                        .padding(14)
                } else {
                    TextEditor(text: $content)
                        .font(.body.monospaced())
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .focused($contentFocused)
                        .disabled(editState != .loaded)
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
        switch editState {
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
        path = pending
        navState.editFilePath = nil
        load()
    }

    private func load() {
        guard canLoad else { return }
        let requestedPath = trimmedPath
        editState = .loading

        Task {
            do {
                let file = try await client.getFile(path: requestedPath)
                let parsed = try MarkdownFrontmatter.parse(file.content)
                path = file.path
                content = parsed.body
                originalContent = parsed.body
                title = parsed.title
                originalTitle = parsed.title
                description = parsed.description
                originalDescription = parsed.description
                tags = parsed.tags.joined(separator: ", ")
                originalTags = parsed.tags
                editState = .loaded
                contentFocused = true
            } catch {
                editState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let savePath = trimmedPath
        let saveContent = contentChanged ? content : ""
        let saveTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let saveDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let saveTags = tagsChanged ? parsedTags : []
        let effectiveTitle = saveTitle.isEmpty ? originalTitle : saveTitle
        let effectiveDescription = saveDescription.isEmpty ? originalDescription : saveDescription
        editState = .saving

        Task {
            do {
                let response = try await client.editContent(
                    path:        savePath,
                    content:     saveContent,
                    title:       saveTitle,
                    description: saveDescription,
                    tags:        saveTags
                )
                editState = .queued(jobId: response.jobId)

                editState = .polling(jobId: response.jobId)
                let job = try await client.pollUntilDone(id: response.jobId)

                if job.status == "done" {
                    let editedPath = job.path ?? savePath
                    path = editedPath
                    originalContent = content
                    originalTitle = effectiveTitle
                    originalDescription = effectiveDescription
                    if !saveTags.isEmpty {
                        originalTags = saveTags
                        tags = saveTags.joined(separator: ", ")
                    } else {
                        tags = originalTags.joined(separator: ", ")
                    }
                    title = originalTitle
                    description = originalDescription
                    editState = .done(path: editedPath)
                    resetLoadedAfterDelay()
                } else {
                    editState = .failed(message: job.error ?? "Job failed")
                }
            } catch {
                editState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func resetLoadedAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            if case .done = editState {
                editState = .loaded
                contentFocused = true
            }
        }
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }
}
