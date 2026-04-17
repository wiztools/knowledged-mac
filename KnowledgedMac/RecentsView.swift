import SwiftUI

struct RecentsView: View {
    @EnvironmentObject private var client:   KnowledgedClient
    @EnvironmentObject private var navState: NavigationState

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
                EntryRow(entry: entry, dateFormatter: dateFormatter) {
                    navState.retrieveFilePath = entry.path
                    navState.selection = .retrieve
                }
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
    let onTap:         () -> Void

    @State private var pathHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.path)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(pathHovered ? Color.accentColor : Color.primary)
                    .underline(pathHovered)
                    .onHover { pathHovered = $0 }

                Spacer(minLength: 0)

                CopyPathIcon(path: entry.path)
            }

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
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Copy path icon

private struct CopyPathIcon: View {
    let path: String
    @State private var copied = false

    var body: some View {
        Image(systemName: copied ? "checkmark" : "doc.on.doc")
            .font(.caption)
            .foregroundStyle(copied ? .green : .secondary)
            .frame(width: 20, height: 20)
            .onTapGesture(count: 2) {
                copy(URL(fileURLWithPath: path).lastPathComponent)
            }
            .onTapGesture(count: 1) {
                copy(path)
            }
            .help("Click to copy path · Double-click to copy filename")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.15)) { copied = false }
        }
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
