import AppKit

enum BookmarkTransfer {
    static func importHTML(from url: URL) throws -> [Bookmark] {
        let html = try String(contentsOf: url, encoding: .utf8)
        let pattern = #"<A\s+[^>]*HREF=[\"']([^\"']+)[\"'][^>]*>(.*?)</A>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let rawURL = ns.substring(with: match.range(at: 1))
            let rawTitle = ns.substring(with: match.range(at: 2)).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            guard URL(string: rawURL) != nil else { return nil }
            return Bookmark(url: rawURL, title: decodeHTML(rawTitle).nonEmpty ?? rawURL, createdAt: Date())
        }
    }

    static func exportHTML(_ bookmarks: [Bookmark], to url: URL) throws {
        let items = bookmarks.map { "<DT><A HREF=\"\(escape($0.url))\" ADD_DATE=\"\(Int($0.createdAt.timeIntervalSince1970))\">\(escape($0.title))</A>" }.joined(separator: "\n")
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>AINCRAD Browser Bookmarks</TITLE>
        <H1>AINCRAD Browser Bookmarks</H1>
        <DL><p>
        \(items)
        </DL><p>
        """
        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func decodeHTML(_ value: String) -> String {
        guard let data = value.data(using: .utf8), let decoded = NSAttributedString(html: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)?.string else { return value }
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
