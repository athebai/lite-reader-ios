import UIKit

enum DocumentText {

    /// Plain text used by the TXT reader and by full-text search.
    static func plainText(for book: Book) -> String? {
        switch book.type {
        case .txt:
            guard let data = try? Data(contentsOf: book.url) else { return nil }
            return TextDecoder.decode(data)
        case .docx:
            return docxText(book.url)
        case .rtf:
            return rtfText(book.url)
        case .html:
            guard let data = try? Data(contentsOf: book.url) else { return nil }
            return TextDecoder.decode(data)
        case .epub, .pdf:
            return nil
        }
    }

    static func docxText(_ url: URL) -> String? {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("docx-\(UUID().uuidString)",
                                                                isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        do {
            try EPUBParser.extract(url, to: temp)
        } catch {
            return nil
        }
        let documentURL = temp.appendingPathComponent("word/document.xml")
        guard let data = try? Data(contentsOf: documentURL) else { return nil }
        let parser = XMLParser(data: data)
        let delegate = DocxTextParser()
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.text
    }

    static func rtfText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        guard let attributed = try? NSAttributedString(data: data,
                                                       options: options,
                                                       documentAttributes: nil) else {
            return nil
        }
        return attributed.string
    }

    /// Strip HTML tags so that EPUB chapters can be searched.
    static func htmlToText(_ html: String) -> String {
        var text = html
        let patterns = [
            "(?is)<script[^>]*>.*?</script>",
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<head[^>]*>.*?</head>",
            "(?is)<br\\s*/?>",
            "(?is)</p>",
            "(?is)<[^>]+>"
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let replacement = (index == 3 || index == 4) ? "\n" : " "
            text = regex.stringByReplacingMatches(in: text,
                                                  options: [],
                                                  range: NSRange(location: 0, length: (text as NSString).length),
                                                  with: replacement)
        }
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&ldquo;", with: "“")
        text = text.replacingOccurrences(of: "&rdquo;", with: "”")
        text = text.replacingOccurrences(of: "&mdash;", with: "—")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return squashBlankLines(text)
    }

    static func squashBlankLines(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "[ \\t]+\\n", options: []) else {
            return text
        }
        var result = regex.stringByReplacingMatches(in: text,
                                                    options: [],
                                                    range: NSRange(location: 0, length: (text as NSString).length),
                                                    with: "\n")
        if let many = try? NSRegularExpression(pattern: "\\n{3,}", options: []) {
            result = many.stringByReplacingMatches(in: result,
                                                   options: [],
                                                   range: NSRange(location: 0, length: (result as NSString).length),
                                                   with: "\n\n")
        }
        return result
    }
}

final class DocxTextParser: NSObject, XMLParserDelegate {

    private(set) var text = ""
    private var inText = false

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = xmlLocalName(elementName)
        switch name {
        case "t":
            inText = true
        case "tab":
            text += "\t"
        case "br", "cr":
            text += "\n"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { text += string }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = xmlLocalName(elementName)
        if name == "t" { inText = false }
        if name == "p" { text += "\n" }
    }
}
