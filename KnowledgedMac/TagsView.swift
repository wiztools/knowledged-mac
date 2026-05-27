import SwiftUI

struct TagsView: View {
	@EnvironmentObject private var client:   KnowledgedClient
	@EnvironmentObject private var navState: NavigationState

	@State private var tagsState: TagsState = .idle
	@State private var documentsState: TaggedDocumentsState = .idle
	@State private var selectedTag: String?

	private let dateFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateStyle = .medium
		f.timeStyle = .short
		return f
	}()

	var body: some View {
		VStack(spacing: 0) {
			HSplitView {
				tagList
					.frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

				documentList
					.frame(minWidth: 360)
			}

			Divider()
			toolbar
		}
		.onAppear {
			if case .idle = tagsState {
				loadTags(select: navState.selectedTag)
			} else {
				applyPendingTag()
			}
		}
		.onChange(of: navState.selectedTag) {
			applyPendingTag()
		}
	}

	// MARK: - Tags

	@ViewBuilder
	private var tagList: some View {
		switch tagsState {
		case .idle:
			Color.clear

		case .loading:
			VStack {
				Spacer()
				ProgressView("Loading tags…")
				Spacer()
			}

		case .loaded(let tags) where tags.isEmpty:
			VStack {
				Spacer()
				Text("No tags yet.")
					.foregroundStyle(.secondary)
				Spacer()
			}

		case .loaded(let tags):
			List(selection: $selectedTag) {
				ForEach(tags) { tag in
					TagSummaryRow(summary: tag)
						.tag(tag.tag)
				}
			}
			.listStyle(.sidebar)
			.onChange(of: selectedTag) {
				guard let selectedTag else { return }
				loadDocuments(tag: selectedTag)
			}

		case .failed(let message):
			ErrorPane(message: message) {
				loadTags(select: selectedTag)
			}
		}
	}

	// MARK: - Documents

	@ViewBuilder
	private var documentList: some View {
		switch documentsState {
		case .idle:
			VStack(spacing: 8) {
				Spacer()
				Image(systemName: "tag")
					.font(.system(size: 36))
					.foregroundStyle(.tertiary)
				Text("Select a tag")
					.foregroundStyle(.tertiary)
				Spacer()
			}

		case .loading:
			VStack {
				Spacer()
				ProgressView("Loading documents…")
				Spacer()
			}

		case .loaded(let docs) where docs.isEmpty:
			VStack {
				Spacer()
				Text("No documents for this tag.")
					.foregroundStyle(.secondary)
				Spacer()
			}

		case .loaded(let docs):
			List(docs) { doc in
				TaggedDocumentRow(
					document: doc,
					dateFormatter: dateFormatter
				) {
					navState.retrieveFilePath = doc.path
					navState.selection = .retrieve
				} onEdit: {
					navState.editFilePath = doc.path
					navState.selection = .edit
				} onTag: { tag in
					navState.selectedTag = tag
					selectedTag = tag
					loadDocuments(tag: tag)
				}
				.listRowSeparator(.visible)
			}
			.listStyle(.plain)

		case .failed(let message):
			ErrorPane(message: message) {
				if let selectedTag {
					loadDocuments(tag: selectedTag)
				}
			}
		}
	}

	// MARK: - Toolbar

	private var toolbar: some View {
		HStack {
			switch documentsState {
			case .loaded(let docs):
				Text(statusText(count: docs.count))
					.foregroundStyle(.secondary)
					.font(.callout)
			default:
				if let selectedTag {
					Text(selectedTag)
						.foregroundStyle(.secondary)
						.font(.callout)
				}
			}

			Spacer()

			Button(action: { loadTags(select: selectedTag) }) {
				Label("Refresh", systemImage: "arrow.clockwise")
			}
			.keyboardShortcut("r", modifiers: .command)
			.buttonStyle(.bordered)
			.controlSize(.regular)
			.disabled(isLoading)
		}
		.padding(EdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16))
	}

	private var isLoading: Bool {
		if case .loading = tagsState { return true }
		if case .loading = documentsState { return true }
		return false
	}

	private func statusText(count: Int) -> String {
		guard let selectedTag else { return "" }
		return "\(count) \(count == 1 ? "document" : "documents") tagged \(selectedTag)"
	}

	// MARK: - Loading

	private func applyPendingTag() {
		guard let pending = navState.selectedTag else { return }
		selectedTag = pending
		if case .loaded = tagsState {
			loadDocuments(tag: pending)
		}
	}

	private func loadTags(select tag: String?) {
		tagsState = .loading
		Task {
			do {
				let tags = try await client.tags()
				tagsState = .loaded(tags)
				if let tag, tags.contains(where: { $0.tag == tag }) {
					selectedTag = tag
					loadDocuments(tag: tag)
				} else if selectedTag == nil {
					documentsState = .idle
				}
			} catch {
				tagsState = .failed(message: error.localizedDescription)
			}
		}
	}

	private func loadDocuments(tag: String) {
		documentsState = .loading
		Task {
			do {
				documentsState = .loaded(try await client.documents(tag: tag))
			} catch {
				documentsState = .failed(message: error.localizedDescription)
			}
		}
	}
}

// MARK: - Rows

private struct TagSummaryRow: View {
	let summary: TagSummary

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "tag")
				.foregroundStyle(.secondary)
			Text(summary.tag)
				.lineLimit(1)
			Spacer()
			Text("\(summary.count)")
				.font(.caption)
				.foregroundStyle(.secondary)
				.monospacedDigit()
		}
	}
}

private struct TaggedDocumentRow: View {
	let document:      TaggedDocument
	let dateFormatter: DateFormatter
	let onOpen:        () -> Void
	let onEdit:        () -> Void
	let onTag:         (String) -> Void

	@State private var pathHovered = false

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 6) {
				Text(document.title.isEmpty ? document.path : document.title)
					.font(.headline)
					.lineLimit(1)

				Spacer(minLength: 0)

				Button(action: onEdit) {
					Image(systemName: "pencil.line")
				}
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)
				.help("Edit")

				CopyPathIcon(path: document.path)
			}

			if !document.description.isEmpty {
				Text(document.description)
					.font(.callout)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}

			Text(document.path)
				.font(.caption.monospaced())
				.lineLimit(1)
				.truncationMode(.middle)
				.foregroundStyle(pathHovered ? Color.accentColor : Color.secondary)
				.underline(pathHovered)
				.onHover { pathHovered = $0 }

			HStack(spacing: 12) {
				Text(dateFormatter.string(from: document.modified))
					.font(.caption)
					.foregroundStyle(.secondary)

				ClickableTagList(tags: document.tags, onTag: onTag)
			}
		}
		.padding(.vertical, 6)
		.contentShape(Rectangle())
		.onTapGesture { onOpen() }
	}
}

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

private struct ClickableTagList: View {
	let tags:  [String]
	let onTag: (String) -> Void

	var body: some View {
		HStack(spacing: 4) {
			ForEach(tags, id: \.self) { tag in
				Button {
					onTag(tag)
				} label: {
					Text(tag)
						.font(.caption2)
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(Color.accentColor.opacity(0.12))
						.foregroundStyle(Color.accentColor)
						.clipShape(Capsule())
				}
				.buttonStyle(.plain)
				.help("Browse \(tag)")
			}
		}
	}
}

private struct ErrorPane: View {
	let message: String
	let retry:   () -> Void

	var body: some View {
		VStack(spacing: 8) {
			Spacer()
			Image(systemName: "exclamationmark.circle")
				.font(.largeTitle)
				.foregroundStyle(.red)
			Text(message)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.padding(.horizontal)
			Button("Retry") { retry() }
			Spacer()
		}
	}
}
