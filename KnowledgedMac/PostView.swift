import SwiftUI

final class PostDraft: ObservableObject {
    @Published var content = ""
    @Published var hint = ""
    @Published var tags = ""
    @Published var title = ""
    @Published var askQuestion = ""
    // Ask section visibility — persisted across tab switches because the
    // rest of the draft is. Not reset by clear() so the user's preference
    // for whether the Ask box is open survives a successful post.
    @Published var askExpanded = false

    func clear() {
        content = ""
        hint = ""
        tags = ""
        title = ""
        askQuestion = ""
    }
}

struct PostView: View {
    @EnvironmentObject private var client: KnowledgedClient
    @EnvironmentObject private var draft:  PostDraft

    // State machines
    @State private var postState: PostState = .idle
    @State private var askState:  AskState  = .idle

    // Overwrite-confirmation for the Ask action.
    @State private var showOverwriteAlert = false

    // Display
    @State private var showPreview = false

    // Focus
    @FocusState private var contentFocused: Bool
    @FocusState private var askFocused: Bool

    private var canPost: Bool {
        !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && postState == .idle
    }

    private var canAsk: Bool {
        !draft.askQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && askState != .asking
    }

    private var parsedTags: [String] {
        draft.tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Ask (collapsible) ───────────────────────────────────────
            askSection
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

            // ── Content editor ──────────────────────────────────────────
            contentArea
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // ── Metadata fields ─────────────────────────────────────────
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Hint")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    TextField("Topic hint for the organizer", text: $draft.hint)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Tags")
                        .foregroundStyle(.secondary)
                    TextField("Comma-separated tags", text: $draft.tags)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Title")
                        .foregroundStyle(.secondary)
                    TextField("Document title", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))

            Divider()

            // ── Action bar ──────────────────────────────────────────────
            HStack(spacing: 12) {
                MarkdownPreviewToggle(isPreviewing: $showPreview)
                statusBadge
                Spacer()
                Button(action: post) {
                    Label("Post", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canPost)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16))
        }
        .onAppear { contentFocused = true }
        .onChange(of: draft.askExpanded) {
            if draft.askExpanded {
                askFocused = true
            } else {
                contentFocused = true
            }
        }
        .onChange(of: showPreview) {
            if !showPreview {
                contentFocused = true
            }
        }
        .alert("Overwrite content and tags?", isPresented: $showOverwriteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Overwrite", role: .destructive) { performAsk() }
        } message: {
            Text("The content or tags are not empty. Asking will replace them with the drafted answer and suggested tags.")
        }
    }

    // MARK: - Content editor

    @ViewBuilder
    private var contentArea: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))

            if showPreview {
                MarkdownWebView(markdown: draft.content)
                    .padding(12)
            } else {
                if draft.content.isEmpty {
                    Text("Paste or type content to store…")
                        .foregroundStyle(.tertiary)
                        .padding(EdgeInsets(top: 10, leading: 12, bottom: 0, trailing: 12))
                        .allowsHitTesting(false)
                }

                TextEditor(text: $draft.content)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .focused($contentFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command), canPost else {
                            return .ignored
                        }
                        post()
                        return .handled
                    }
            }
        }
    }

    // MARK: - Ask section

    @ViewBuilder
    private var askSection: some View {
        DisclosureGroup(isExpanded: $draft.askExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    TextField(
                        "What concept should the LLM draft an explanation for?",
                        text: $draft.askQuestion,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($askFocused)
                    .onSubmit { requestAsk() }

                    Button(action: requestAsk) {
                        if askState == .asking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Ask")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canAsk)
                }
                if case let .failed(message) = askState {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Ask", systemImage: "sparkles")
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { draft.askExpanded.toggle() }
                }
        }
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        switch postState {
        case .idle:
            EmptyView()

        case .posting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Posting…").foregroundStyle(.secondary)
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
                Text("Storing · \(shortID(id))")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

        case .done(let path):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(path)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy path")
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

    // MARK: - Actions

    private func post() {
        guard canPost else { return }
        let content = draft.content
        let hint = draft.hint
        let tags = parsedTags
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        postState = .posting

        Task {
            do {
                let response = try await client.postContent(
                    content: content,
                    hint:    hint,
                    title:   title,
                    tags:    tags
                )
                postState = .queued(jobId: response.jobId)

                postState = .polling(jobId: response.jobId)
                let job = try await client.pollUntilDone(id: response.jobId)

                if job.status == "done" {
                    postState = .done(path: job.path ?? "stored")
                    clearFormAfterDelay()
                } else {
                    postState = .failed(message: job.error ?? "Job failed")
                }
            } catch {
                postState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func requestAsk() {
        guard canAsk else { return }
        let hasContent = !draft.content
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTags = !draft.tags
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasContent || hasTags {
            showOverwriteAlert = true
        } else {
            performAsk()
        }
    }

    private func performAsk() {
        let question = draft.askQuestion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        askState = .asking

        Task {
            do {
                let resp = try await client.ask(question: question)
                draft.content = resp.answer
                if let title = resp.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    draft.title = title
                }
                draft.tags = resp.tags.joined(separator: ", ")
                askState = .idle
                contentFocused = true
            } catch {
                askState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func clearFormAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            draft.clear()
            showPreview = false
            postState = .idle
            contentFocused = true
        }
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }
}
