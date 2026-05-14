import SwiftUI
import WebKit

@MainActor
final class MarkdownPDFRenderer: NSObject, WKNavigationDelegate {
    private var loadContinuation: CheckedContinuation<Void, Error>?

    func render(markdown: String, to url: URL) async throws {
        let paperSize = CGSize(width: 595.2, height: 841.8)
        let margins = PDFMargins(top: 54, right: 54, bottom: 54, left: 54)
        let contentSize = CGSize(
            width: paperSize.width - margins.left - margins.right,
            height: paperSize.height - margins.top - margins.bottom
        )
        let webView = WKWebView(frame: CGRect(origin: .zero, size: contentSize))
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        try await loadHTML(MarkdownHTMLRenderer.buildDocument(markdown, isDark: false), in: webView)
        let documentHeight = max(try await fullDocumentHeight(in: webView), contentSize.height)
        let links = try await renderedLinks(in: webView)
        let pageCount = max(1, Int(ceil(documentHeight / contentSize.height)))

        var pages: [PDFPageData] = []
        for pageIndex in 0..<pageCount {
            let offset = CGFloat(pageIndex) * contentSize.height
            let height = min(contentSize.height, documentHeight - offset)
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(x: 0, y: offset, width: contentSize.width, height: height)
            let data = try await createPDF(in: webView, configuration: configuration)
            pages.append(PDFPageData(data: data, contentHeight: height))
        }

        try writeA4PDF(pages: pages, links: links, paperSize: paperSize, margins: margins, to: url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    private func loadHTML(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    private func fullDocumentHeight(in webView: WKWebView) async throws -> CGFloat {
        let script = """
        Math.max(
            document.body.scrollHeight,
            document.body.offsetHeight,
            document.documentElement.clientHeight,
            document.documentElement.scrollHeight,
            document.documentElement.offsetHeight
        )
        """

        guard let height = try await webView.evaluateJavaScript(script) as? CGFloat else {
            throw PDFRenderError.invalidDocumentSize
        }
        return height
    }

    private func renderedLinks(in webView: WKWebView) async throws -> [RenderedLink] {
        let script = """
        JSON.stringify(Array.from(document.querySelectorAll('a[href]')).flatMap((link) => {
            const href = link.href;
            if (!href || !(href.startsWith('http://') || href.startsWith('https://'))) {
                return [];
            }
            return Array.from(link.getClientRects()).map((rect) => ({
                href,
                x: rect.left + window.scrollX,
                y: rect.top + window.scrollY,
                width: rect.width,
                height: rect.height
            }));
        }))
        """

        guard let json = try await webView.evaluateJavaScript(script) as? String,
              let data = json.data(using: .utf8)
        else {
            throw PDFRenderError.invalidLinkData
        }

        return try JSONDecoder().decode([RenderedLink].self, from: data)
    }

    private func createPDF(in webView: WKWebView, configuration: WKPDFConfiguration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: configuration) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func writeA4PDF(
        pages: [PDFPageData],
        links: [RenderedLink],
        paperSize: CGSize,
        margins: PDFMargins,
        to url: URL
    ) throws {
        var mediaBox = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw PDFRenderError.writeFailed
        }

        for (pageIndex, page) in pages.enumerated() {
            let pageOffset = CGFloat(pageIndex) * (paperSize.height - margins.top - margins.bottom)
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(mediaBox)

            guard let provider = CGDataProvider(data: page.data as CFData),
                  let document = CGPDFDocument(provider),
                  let sourcePage = document.page(at: 1)
            else {
                throw PDFRenderError.invalidPageData
            }

            let sourceBox = sourcePage.getBoxRect(.mediaBox)
            context.saveGState()
            context.translateBy(
                x: margins.left - sourceBox.minX,
                y: paperSize.height - margins.top - page.contentHeight - sourceBox.minY
            )
            context.drawPDFPage(sourcePage)
            context.restoreGState()

            addLinkAnnotations(
                links,
                to: context,
                pageOffset: pageOffset,
                pageContentHeight: page.contentHeight,
                paperSize: paperSize,
                margins: margins
            )
            context.endPDFPage()
        }

        context.closePDF()
    }

    private func addLinkAnnotations(
        _ links: [RenderedLink],
        to context: CGContext,
        pageOffset: CGFloat,
        pageContentHeight: CGFloat,
        paperSize: CGSize,
        margins: PDFMargins
    ) {
        let pageBottom = pageOffset + pageContentHeight

        for link in links {
            guard let url = URL(string: link.href) else { continue }

            let linkTop = link.y
            let linkBottom = link.y + link.height
            let clippedTop = max(linkTop, pageOffset)
            let clippedBottom = min(linkBottom, pageBottom)
            guard clippedBottom > clippedTop else { continue }

            let localTop = clippedTop - pageOffset
            let localBottom = clippedBottom - pageOffset
            let rect = CGRect(
                x: margins.left + link.x,
                y: paperSize.height - margins.top - localBottom,
                width: link.width,
                height: localBottom - localTop
            )
            context.setURL(url as CFURL, for: rect)
        }
    }

    private struct PDFMargins {
        let top: CGFloat
        let right: CGFloat
        let bottom: CGFloat
        let left: CGFloat
    }

    private struct PDFPageData {
        let data: Data
        let contentHeight: CGFloat
    }

    private struct RenderedLink: Decodable {
        let href: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private enum PDFRenderError: LocalizedError {
        case invalidDocumentSize
        case invalidLinkData
        case invalidPageData
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .invalidDocumentSize:
                return "Could not determine rendered document size."
            case .invalidLinkData:
                return "Could not read rendered links."
            case .invalidPageData:
                return "Could not read a rendered PDF page."
            case .writeFailed:
                return "Could not render the PDF."
            }
        }
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = MarkdownHTMLRenderer.buildDocument(markdown, isDark: colorScheme == .dark)
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}

enum MarkdownHTMLRenderer {
    // MARK: - HTML generation

    static func buildDocument(_ markdown: String, isDark: Bool) -> String {
        let text      = isDark ? "#e2e2e7" : "#1c1c1e"
        let bg        = isDark ? "transparent" : "transparent"
        let codeBg    = isDark ? "#2c2c2e" : "#f2f2f7"
        let hrColor   = isDark ? "#3a3a3c" : "#d1d1d6"
        let linkColor = isDark ? "#64a4f4" : "#0a7aff"
        let h1Size    = "1.45em"
        let h2Size    = "1.2em"
        let h3Size    = "1.05em"

        let body = markdownToHTML(markdown)

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
        * { box-sizing: border-box; }
        html, body {
            margin: 0; padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            font-size: 13px; line-height: 1.65;
            color: \(text); background: \(bg);
        }
        h1 { font-size: \(h1Size); font-weight: 700; margin: 0.9em 0 0.35em; line-height: 1.3; }
        h2 { font-size: \(h2Size); font-weight: 600; margin: 0.85em 0 0.3em; line-height: 1.35; }
        h3 { font-size: \(h3Size); font-weight: 600; margin: 0.8em 0 0.25em; }
        h4 { font-size: 1em; font-weight: 600; margin: 0.7em 0 0.2em; }
        p { margin: 0.5em 0; }
        p:first-child, h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
        ul, ol { margin: 0.4em 0; padding-left: 1.6em; }
        li { margin: 0.2em 0; }
        code {
            font-family: "SF Mono", Menlo, Monaco, monospace;
            font-size: 0.88em;
            background: \(codeBg);
            padding: 1px 5px;
            border-radius: 4px;
        }
        pre {
            background: \(codeBg);
            border-radius: 6px;
            padding: 10px 14px;
            overflow-x: auto;
            margin: 0.6em 0;
        }
        pre code { background: none; padding: 0; font-size: 0.87em; }
        a { color: \(linkColor); text-decoration: none; }
        a:hover { text-decoration: underline; }
        strong { font-weight: 600; }
        em { font-style: italic; }
        hr { border: none; border-top: 1px solid \(hrColor); margin: 1em 0; }
        blockquote {
            margin: 0.5em 0;
            padding-left: 0.8em;
            border-left: 3px solid \(hrColor);
            color: \(isDark ? "#8e8e93" : "#6c6c70");
        }
        .sources {
            margin-top: 1em;
            padding-top: 0.75em;
            border-top: 1px solid \(hrColor);
        }
        .sources h2 {
            margin: 0 0 0.45em;
        }
        .sources-list {
            margin: 0;
            padding-left: 3.4em;
        }
        .sources-list li {
            margin: 0.35em 0;
            padding-left: 0.2em;
        }
        .source-title {
            font-weight: 500;
        }
        .source-url {
            display: block;
            overflow-wrap: anywhere;
            color: \(isDark ? "#98989f" : "#6c6c70");
            font-size: 0.92em;
        }
        .citation {
            font-size: 0.78em;
            vertical-align: super;
            line-height: 0;
            margin-left: 1px;
        }
        .table-wrap {
            width: 100%;
            overflow-x: auto;
            margin: 0.7em 0;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.96em;
        }
        th, td {
            padding: 8px 10px;
            border: 1px solid \(hrColor);
            vertical-align: top;
        }
        th {
            background: \(codeBg);
            font-weight: 600;
            text-align: left;
        }
        tr:nth-child(even) td {
            background: \(isDark ? "#202022" : "#fbfbfd");
        }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    static func buildClipboardHTML(_ markdown: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            font-size: 13px;
            line-height: 1.65;
        }
        h1 { font-size: 1.45em; font-weight: 700; margin: 0.9em 0 0.35em; line-height: 1.3; }
        h2 { font-size: 1.2em; font-weight: 600; margin: 0.85em 0 0.3em; line-height: 1.35; }
        h3 { font-size: 1.05em; font-weight: 600; margin: 0.8em 0 0.25em; }
        h4 { font-size: 1em; font-weight: 600; margin: 0.7em 0 0.2em; }
        p { margin: 0.5em 0; }
        ul, ol { margin: 0.4em 0; padding-left: 1.6em; }
        li { margin: 0.2em 0; }
        code {
            font-family: "SF Mono", Menlo, Monaco, monospace;
            font-size: 0.88em;
        }
        pre {
            padding: 10px 14px;
            overflow-x: auto;
            margin: 0.6em 0;
        }
        pre code { font-size: 0.87em; }
        strong { font-weight: 600; }
        em { font-style: italic; }
        blockquote {
            margin: 0.5em 0;
            padding-left: 0.8em;
            border-left: 3px solid #d1d1d6;
        }
        .sources {
            margin-top: 1em;
            padding-top: 0.75em;
            border-top: 1px solid #d1d1d6;
        }
        .sources-list {
            margin: 0;
            padding-left: 3.4em;
        }
        .sources-list li {
            margin: 0.35em 0;
            padding-left: 0.2em;
        }
        .source-title {
            font-weight: 500;
        }
        .source-url {
            display: block;
            overflow-wrap: anywhere;
            color: #6c6c70;
            font-size: 0.92em;
        }
        .citation {
            font-size: 0.78em;
            vertical-align: super;
            line-height: 0;
            margin-left: 1px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.96em;
        }
        th, td {
            padding: 8px 10px;
            border: 1px solid #d1d1d6;
            vertical-align: top;
        }
        th {
            font-weight: 600;
            text-align: left;
        }
        </style>
        </head>
        <body>\(markdownToHTML(markdown))</body>
        </html>
        """
    }

    // MARK: - Markdown → HTML

    private static func markdownToHTML(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var html = ""
        var i = 0
        var inCodeBlock = false
        var inUnorderedList = false
        var inOrderedList = false
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            // Join lines with a space so soft-wraps don't run together
            let joined = paragraphLines.joined(separator: " ")
            html += "<p>\(inlineHTML(joined))</p>\n"
            paragraphLines = []
        }

        func closeList() {
            if inUnorderedList { html += "</ul>\n"; inUnorderedList = false }
            if inOrderedList   { html += "</ol>\n";  inOrderedList = false }
        }

        while i < lines.count {
            let raw     = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // ── Code fence ──────────────────────────────────────────────
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    html += "</code></pre>\n"
                    inCodeBlock = false
                } else {
                    flushParagraph(); closeList()
                    html += "<pre><code>"
                    inCodeBlock = true
                }
                i += 1; continue
            }

            if inCodeBlock {
                html += escapeHTML(raw) + "\n"
                i += 1; continue
            }

            // ── Sources block ───────────────────────────────────────────
            if isSourcesHeading(trimmed) {
                var sourceItems: [SourceItem] = []
                var j = i + 1

                while j < lines.count {
                    let candidate = lines[j].trimmingCharacters(in: .whitespaces)
                    if candidate.isEmpty { break }
                    guard let item = parseSourceItem(candidate) else { break }
                    sourceItems.append(item)
                    j += 1
                }

                if !sourceItems.isEmpty {
                    flushParagraph(); closeList()
                    html += renderSources(sourceItems)
                    i = j
                    continue
                }
            }

            // ── Blank line ──────────────────────────────────────────────
            if trimmed.isEmpty {
                flushParagraph(); closeList()
                i += 1; continue
            }

            // ── Headings ────────────────────────────────────────────────
            if trimmed.hasPrefix("#### ") {
                flushParagraph(); closeList()
                html += "<h4>\(inlineHTML(String(trimmed.dropFirst(5))))</h4>\n"
            } else if trimmed.hasPrefix("### ") {
                flushParagraph(); closeList()
                html += "<h3>\(inlineHTML(String(trimmed.dropFirst(4))))</h3>\n"
            } else if trimmed.hasPrefix("## ") {
                flushParagraph(); closeList()
                html += "<h2>\(inlineHTML(String(trimmed.dropFirst(3))))</h2>\n"
            } else if trimmed.hasPrefix("# ") {
                flushParagraph(); closeList()
                html += "<h1>\(inlineHTML(String(trimmed.dropFirst(2))))</h1>\n"

            // ── Horizontal rule ─────────────────────────────────────────
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph(); closeList()
                html += "<hr>\n"

            // ── Blockquote ──────────────────────────────────────────────
            } else if trimmed.hasPrefix("> ") {
                flushParagraph(); closeList()
                html += "<blockquote>\(inlineHTML(String(trimmed.dropFirst(2))))</blockquote>\n"

            // ── Table ───────────────────────────────────────────────────
            } else if i + 1 < lines.count,
                      isTableRow(trimmed),
                      isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                flushParagraph(); closeList()

                let headerCells = splitTableCells(trimmed)
                let alignments = splitTableCells(lines[i + 1]).map(tableAlignment)
                html += "<div class=\"table-wrap\"><table>\n<thead><tr>"
                for (index, cell) in headerCells.enumerated() {
                    html += "<th\(alignmentAttribute(for: alignments, at: index))>\(inlineHTML(cell))</th>"
                }
                html += "</tr></thead>\n<tbody>\n"

                i += 2
                while i < lines.count {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(row), !row.isEmpty else { break }

                    let cells = splitTableCells(row)
                    html += "<tr>"
                    for (index, cell) in cells.enumerated() {
                        html += "<td\(alignmentAttribute(for: alignments, at: index))>\(inlineHTML(cell))</td>"
                    }
                    html += "</tr>\n"
                    i += 1
                }

                html += "</tbody></table></div>\n"
                continue

            // ── Unordered list ──────────────────────────────────────────
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                if !inUnorderedList { closeList(); html += "<ul>\n"; inUnorderedList = true }
                html += "<li>\(inlineHTML(String(trimmed.dropFirst(2))))</li>\n"

            // ── Ordered list ────────────────────────────────────────────
            } else if trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil,
                      let dotRange = trimmed.range(of: ". ") {
                flushParagraph()
                if !inOrderedList { closeList(); html += "<ol>\n"; inOrderedList = true }
                html += "<li>\(inlineHTML(String(trimmed[dotRange.upperBound...])))</li>\n"

            // ── Paragraph line ──────────────────────────────────────────
            } else {
                if inUnorderedList || inOrderedList { closeList() }
                paragraphLines.append(trimmed)
            }

            i += 1
        }

        flushParagraph()
        closeList()
        return html
    }

    // MARK: - Inline formatting

    private static func inlineHTML(_ text: String) -> String {
        var s = escapeHTML(text)
        // Code spans – must come before bold/italic
        s = s.replacingOccurrences(of: #"`([^`]+)`"#,               with: "<code>$1</code>",         options: .regularExpression)
        // Bold
        s = s.replacingOccurrences(of: #"\*\*(.+?)\*\*"#,           with: "<strong>$1</strong>",      options: .regularExpression)
        s = s.replacingOccurrences(of: #"__(.+?)__"#,               with: "<strong>$1</strong>",      options: .regularExpression)
        // Italic
        s = s.replacingOccurrences(of: #"\*([^*\s][^*]*[^*\s])\*"#, with: "<em>$1</em>",             options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*(\S)\*"#,                 with: "<em>$1</em>",             options: .regularExpression)
        s = s.replacingOccurrences(of: #"_([^_\s][^_]*[^_\s])_"#,   with: "<em>$1</em>",             options: .regularExpression)
        // Links
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "<a href=\"$2\">$1</a>",   options: .regularExpression)
        // Citation markers
        s = s.replacingOccurrences(
            of: #"(?<![A-Za-z0-9])\[(\d+)\]"#,
            with: "<a class=\"citation\" href=\"#source-$1\">[$1]</a>",
            options: .regularExpression
        )
        return s
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeHTML(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func isSourcesHeading(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return normalized.caseInsensitiveCompare("Sources") == .orderedSame
    }

    private static func parseSourceItem(_ line: String) -> SourceItem? {
        guard line.hasPrefix("["),
              let closeBracket = line.firstIndex(of: "]"),
              let number = Int(line[line.index(after: line.startIndex)..<closeBracket])
        else {
            return nil
        }

        let restStart = line.index(after: closeBracket)
        let rest = line[restStart...].trimmingCharacters(in: .whitespaces)
        guard let urlRange = rest.range(of: #"https?://\S+"#, options: .regularExpression) else {
            return nil
        }

        let title = rest[..<urlRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—: "))
        let url = String(rest[urlRange])
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))

        return SourceItem(number: number, title: title.isEmpty ? url : title, url: url)
    }

    private static func renderSources(_ sources: [SourceItem]) -> String {
        var html = "<section class=\"sources\"><h2>Sources</h2>\n<ol class=\"sources-list\">\n"

        for source in sources {
            html += """
            <li id="source-\(source.number)" value="\(source.number)">
            <a class="source-title" href="\(escapeAttribute(source.url))">\(inlineHTML(source.title))</a>
            <span class="source-url">\(escapeHTML(source.url))</span>
            </li>
            """
            html += "\n"
        }

        html += "</ol>\n</section>\n"
        return html
    }

    private struct SourceItem {
        let number: Int
        let title: String
        let url: String
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = splitTableCells(line)
        guard !cells.isEmpty else { return false }

        return cells.allSatisfy { cell in
            let token = cell.replacingOccurrences(of: " ", with: "")
            guard !token.isEmpty else { return false }
            let dashesOnly = token.replacingOccurrences(of: ":", with: "")
            return !dashesOnly.isEmpty && dashesOnly.allSatisfy { $0 == "-" }
        }
    }

    private static func splitTableCells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }

        var cells: [String] = []
        var current = ""
        var isEscaping = false

        for character in text {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }

            current.append(character)
        }

        if isEscaping {
            current.append("\\")
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func tableAlignment(for separatorCell: String) -> String? {
        let token = separatorCell.replacingOccurrences(of: " ", with: "")
        guard !token.isEmpty else { return nil }

        let isLeft = token.hasPrefix(":")
        let isRight = token.hasSuffix(":")
        switch (isLeft, isRight) {
        case (true, true): return "center"
        case (true, false): return "left"
        case (false, true): return "right"
        case (false, false): return nil
        }
    }

    private static func alignmentAttribute(for alignments: [String?], at index: Int) -> String {
        guard index < alignments.count, let alignment = alignments[index] else { return "" }
        return " style=\"text-align: \(alignment);\""
    }
}
