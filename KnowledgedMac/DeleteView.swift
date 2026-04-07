import SwiftUI

struct DeleteView: View {
    @EnvironmentObject private var client: KnowledgedClient

    @State private var path        = ""
    @State private var deleteState: DeleteState = .idle

    @FocusState private var pathFocused: Bool

    private var canDelete: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && deleteState == .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Path field ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter the repo-relative path of the file to delete.")
                    .foregroundStyle(.secondary)
                    .font(.callout)

                TextField("e.g. tech/go/goroutines.md", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($pathFocused)
                    .onSubmit { if canDelete { delete() } }
            }
            .padding(EdgeInsets(top: 24, leading: 16, bottom: 0, trailing: 16))

            Spacer()

            Divider()

            // ── Action bar ──────────────────────────────────────────────
            HStack(spacing: 12) {
                statusBadge
                Spacer()
                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(!canDelete)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16))
        }
        .onAppear { pathFocused = true }
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        switch deleteState {
        case .idle:
            EmptyView()

        case .deleting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Deleting…").foregroundStyle(.secondary)
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
                Text("Removing · \(shortID(id))")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

        case .done(let deletedPath):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(deletedPath) deleted")
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

    // MARK: - Actions

    private func delete() {
        guard canDelete else { return }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        deleteState = .deleting

        Task {
            do {
                let response = try await client.deleteContent(path: trimmed)
                deleteState = .queued(jobId: response.jobId)

                deleteState = .polling(jobId: response.jobId)
                let job = try await client.pollUntilDone(id: response.jobId)

                if job.status == "done" {
                    deleteState = .done(path: job.path ?? trimmed)
                    resetAfterDelay()
                } else {
                    deleteState = .failed(message: job.error ?? "Job failed")
                }
            } catch {
                deleteState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func resetAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            path        = ""
            deleteState = .idle
            pathFocused = true
        }
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }
}
