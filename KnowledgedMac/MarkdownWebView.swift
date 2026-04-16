import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = buildHTML(markdown, isDark: colorScheme == .dark)
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - HTML generation

    private func buildHTML(_ markdown: String, isDark: Bool) -> String {
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

    // MARK: - Markdown → HTML

    private func markdownToHTML(_ text: String) -> String {
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

    private func inlineHTML(_ text: String) -> String {
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
        return s
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func isTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let cells = splitTableCells(line)
        guard !cells.isEmpty else { return false }

        return cells.allSatisfy { cell in
            let token = cell.replacingOccurrences(of: " ", with: "")
            guard !token.isEmpty else { return false }
            let dashesOnly = token.replacingOccurrences(of: ":", with: "")
            return !dashesOnly.isEmpty && dashesOnly.allSatisfy { $0 == "-" }
        }
    }

    private func splitTableCells(_ line: String) -> [String] {
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

    private func tableAlignment(for separatorCell: String) -> String? {
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

    private func alignmentAttribute(for alignments: [String?], at index: Int) -> String {
        guard index < alignments.count, let alignment = alignments[index] else { return "" }
        return " style=\"text-align: \(alignment);\""
    }
}
