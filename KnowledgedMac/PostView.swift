import SwiftUI

final class PostDraft: ObservableObject {
    @Published var content = ""
    @Published var hint = ""
    @Published var tags = ""

    func clear() {
        content = ""
        hint = ""
        tags = ""
    }
}

struct PostView: View {
    @EnvironmentObject private var client: KnowledgedClient
    @EnvironmentObject private var draft:  PostDraft

    // State machine
    @State private var postState: PostState = .idle

    // Focus
    @FocusState private var contentFocused: Bool

    private var canPost: Bool {
        !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && postState == .idle
    }

    private var parsedTags: [String] {
        draft.tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Content editor ──────────────────────────────────────────
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))

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
            }
            .padding(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))

            Divider()

            // ── Action bar ──────────────────────────────────────────────
            HStack(spacing: 12) {
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
        postState = .posting

        Task {
            do {
                let response = try await client.postContent(
                    content: content,
                    hint:    hint,
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

    private func clearFormAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            draft.clear()
            postState = .idle
            contentFocused = true
        }
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }
}
