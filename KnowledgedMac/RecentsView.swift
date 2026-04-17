import SwiftUI

struct RecentsView: View {
    @EnvironmentObject private var client: KnowledgedClient

    @State private var state: RecentsState = .idle

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            contentArea
            Divider()
            toolbar
        }
        .onAppear { if case .idle = state { load() } }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch state {
        case .idle:
            Color.clear

        case .loading:
            VStack {
                Spacer()
                ProgressView("Loading…")
                Spacer()
            }

        case .loaded(let entries) where entries.isEmpty:
            VStack {
                Spacer()
                Text("No posts yet.")
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .loaded(let entries):
            List(entries) { entry in
                EntryRow(entry: entry, dateFormatter: dateFormatter)
                    .listRowSeparator(.visible)
            }
            .listStyle(.plain)

        case .failed(let message):
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "exclamationmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Retry") { load() }
                Spacer()
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            if case .loaded(let entries) = state {
                Text("\(entries.count) recent \(entries.count == 1 ? "post" : "posts")")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            Button(action: load) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled({ if case .loading = state { return true }; return false }())
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16))
    }

    // MARK: - Load

    private func load() {
        state = .loading
        Task {
            do {
                let entries = try await client.recents()
                state = .loaded(entries)
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Row

private struct EntryRow: View {
    let entry:         RecentEntry
    let dateFormatter: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.path)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                Text(dateFormatter.string(from: entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let tags = entry.tags, !tags.isEmpty {
                    TagList(tags: tags)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tag chips

private struct TagList: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
    }
}
