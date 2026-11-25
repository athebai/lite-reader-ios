import Foundation
import ZIPFoundation

enum ReaderError: Error {
    case message(String)
}

struct EPUBChapter {
    let title: String
    let url: URL
}

struct EPUBBook {
    let title: String?
    let author: String?
    let chapters: [EPUBChapter]
    let root: URL
    let coverURL: URL?
}

enum EPUBParser {

    private static let prepareQueue = DispatchQueue(label: "lite.reader.epub")

    // MARK: - Public

    static func prepare(epubURL: URL, cacheDirectory: URL) throws -> EPUBBook {
        return try prepareQueue.sync {
            try prepareLocked(epubURL: epubURL, cacheDirectory: cacheDirectory)
        }
    }

    static func extract(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination,
                               withIntermediateDirectories: true,
                               attributes: nil)
        guard let archive = Archive(url: source, accessMode: .read) else {
            throw ReaderError.message("无法打开压缩包（EPUB/DOCX）")
        }
        for entry in archive {
            let path = entry.path
            if path.hasPrefix("__MACOSX") || path.contains("..") { continue }
            let target = destination.appendingPathComponent(path)
            if entry.type == .directory {
                try? fm.createDirectory(at: target,
                                        withIntermediateDirectories: true,
                                        attributes: nil)
            } else if entry.type == .file {
                try fm.createDirectory(at: target.deletingLastPathComponent(),
                                       withIntermediateDirectories: true,
                                       attributes: nil)
                _ = try archive.extract(entry, to: target)
            }
        }
    }

    // MARK: - Implementation

    private static func prepareLocked(epubURL: URL, cacheDirectory: URL) throws -> EPUBBook {
        let fm = FileManager.default
        let attributes = try? fm.attributesOfItem(atPath: epubURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let stamp = Int((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        let identity = "\(epubURL.lastPathComponent)-\(size)-\(stamp)"
        let folder = safeName(identity)
        let destination = cacheDirectory
            .appendingPathComponent("EPUB", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
        let containerURL = destination.appendingPathComponent("META-INF/container.xml")

        if !fm.fileExists(atPath: containerURL.path) {
            if fm.fileExists(atPath: destination.path) {
                try? fm.removeItem(at: destination)
            }
            try extract(epubURL, to: destination)
        }

        guard let opfPath = parseContainer(containerURL) else {
            throw ReaderError.message("不是有效的 EPUB：缺少 META-INF/container.xml")
        }
        let opfURL = destination.appendingPathComponent(opfPath)
        guard let opf = parseOPF(opfURL) else {
            throw ReaderError.message("EPUB 目录解析失败")
        }

        let opfDirectory = opfURL.deletingLastPathComponent()
        var titles: [String: String] = [:]

        if let ncxHref = opf.ncxHref {
            let ncxURL = opfDirectory.appendingPathComponent(decodePath(ncxHref))
            let ncxDirectory = ncxURL.deletingLastPathComponent()
            for entry in parseNCX(ncxURL) {
                let key = relativeKey(entry.src, base: ncxDirectory, root: destination)
                if !key.isEmpty && titles[key] == nil {
                    titles[key] = entry.title
                }
            }
        }

        if let navHref = opf.navHref {
            let navURL = opfDirectory.appendingPathComponent(decodePath(navHref))
            let navDirectory = navURL.deletingLastPathComponent()
            for entry in parseNav(navURL) {
                let key = relativeKey(entry.href, base: navDirectory, root: destination)
                if !key.isEmpty && titles[key] == nil {
                    titles[key] = entry.title
                }
            }
        }

        var chapters: [EPUBChapter] = []
        for (index, href) in opf.spine.enumerated() {
            let decoded = decodePath(href)
            let pathOnly = decoded.components(separatedBy: "#").first ?? decoded
            if pathOnly.isEmpty { continue }
            let url = opfDirectory.appendingPathComponent(pathOnly)
            let key = relativeKey(pathOnly, base: opfDirectory, root: destination)
            let title = titles[key] ?? "第 \(index + 1) 章"
            chapters.append(EPUBChapter(title: title, url: url))
        }
        guard !chapters.isEmpty else {
            throw ReaderError.message("EPUB 没有可显示的章节")
        }

        var coverURL: URL?
        if let coverHref = opf.coverHref {
            let candidate = opfDirectory.appendingPathComponent(decodePath(coverHref))
            if fm.fileExists(atPath: candidate.path) {
                coverURL = candidate
            }
        }

        var bookTitle = opf.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if bookTitle?.isEmpty == true { bookTitle = nil }

        return EPUBBook(title: bookTitle,
                        author: opf.author,
                        chapters: chapters,
                        root: destination,
                        coverURL: coverURL)
    }

    private static func safeName(_ name: String) -> String {
        return FileKey.make(name, maxPrefix: 48)
    }

    private static func decodePath(_ path: String) -> String {
        return path.removingPercentEncoding ?? path
    }

    private static func relativeKey(_ href: String, base: URL, root: URL) -> String {
        let pathOnly = (href.components(separatedBy: "#").first ?? href)
        if pathOnly.isEmpty { return "" }
        let url = base.appendingPathComponent(decodePath(pathOnly)).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        let fullPath = url.path
        if fullPath.hasPrefix(rootPath) {
            var relative = String(fullPath.dropFirst(rootPath.count))
            while relative.hasPrefix("/") { relative.removeFirst() }
            return relative
        }
        return fullPath
    }

    // MARK: - container.xml

    private static func parseContainer(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let parser = XMLParser(data: data)
        let delegate = ContainerParser()
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.rootPath
    }

    // MARK: - OPF

    private struct OPFInfo {
        let title: String?
        let author: String?
        let spine: [String]
        let ncxHref: String?
        let navHref: String?
        let coverHref: String?
    }

    private static func parseOPF(_ url: URL) -> OPFInfo? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let parser = XMLParser(data: data)
        let delegate = OPFParser()
        parser.delegate = delegate
        _ = parser.parse()

        var spine: [String] = []
        for id in delegate.spineIDs {
            if let item = delegate.manifest[id] {
                spine.append(item.href)
            }
        }
        if spine.isEmpty {
            spine = delegate.manifest.values
                .filter { $0.mediaType.contains("html") }
                .map { $0.href }
        }
        guard !spine.isEmpty else { return nil }

        var ncxHref: String?
        if let tocID = delegate.spineTocID, let item = delegate.manifest[tocID] {
            ncxHref = item.href
        }
        if ncxHref == nil {
            ncxHref = delegate.manifest.values
                .first { $0.mediaType.contains("dtbncx") }?.href
        }

        var navHref: String?
        for item in delegate.manifest.values {
            if item.properties.contains("nav") {
                navHref = item.href
                break
            }
        }

        var coverHref: String?
        for item in delegate.manifest.values {
            if item.properties.contains("cover-image") {
                coverHref = item.href
                break
            }
        }
        if coverHref == nil, let coverID = delegate.coverID, let item = delegate.manifest[coverID] {
            coverHref = item.href
        }

        return OPFInfo(title: delegate.bookTitle,
                       author: delegate.bookAuthor,
                       spine: spine,
                       ncxHref: ncxHref,
                       navHref: navHref,
                       coverHref: coverHref)
    }

    // MARK: - NCX

    private static func parseNCX(_ url: URL) -> [(title: String, src: String)] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let parser = XMLParser(data: data)
        let delegate = NCXParser()
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.entries
    }

    // MARK: - nav.xhtml (EPUB 3)

    private static func parseNav(_ url: URL) -> [(title: String, href: String)] {
        guard let data = try? Data(contentsOf: url),
              let html = TextDecoder.decode(data) else { return [] }
        let pattern = "<a\\s+[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html,
                                    options: [],
                                    range: NSRange(location: 0, length: nsHTML.length))
        var result: [(title: String, href: String)] = []
        for match in matches {
            if match.numberOfRanges < 3 { continue }
            let href = nsHTML.substring(with: match.range(at: 1))
            let rawTitle = nsHTML.substring(with: match.range(at: 2))
            let title = stripTags(rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
            if href.isEmpty { continue }
            result.append((title.isEmpty ? "未命名" : title, href))
        }
        return result
    }

    private static func stripTags(_ html: String) -> String {
        var text = html
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            text = regex.stringByReplacingMatches(in: text,
                                                  options: [],
                                                  range: NSRange(location: 0, length: (text as NSString).length),
                                                  with: " ")
        }
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        return text
    }
}

func xmlLocalName(_ name: String) -> String {
    if let colon = name.range(of: ":", options: .backwards) {
        return String(name[colon.upperBound...])
    }
    return name
}

// MARK: - XML delegates

final class ContainerParser: NSObject, XMLParserDelegate {

    var rootPath: String?

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if xmlLocalName(elementName) == "rootfile" && rootPath == nil {
            rootPath = attributeDict["full-path"]
        }
    }
}

final class OPFParser: NSObject, XMLParserDelegate {

    struct Item {
        let href: String
        let mediaType: String
        let properties: String
    }

    var manifest: [String: Item] = [:]
    var spineIDs: [String] = []
    var spineTocID: String?
    var coverID: String?
    var bookTitle: String?
    var bookAuthor: String?

    private var capture: String?
    private var buffer = ""

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = xmlLocalName(elementName)
        switch name {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = Item(href: href,
                                    mediaType: attributeDict["media-type"] ?? "",
                                    properties: attributeDict["properties"] ?? "")
            }
        case "spine":
            spineTocID = attributeDict["toc"]
        case "itemref":
            if let idref = attributeDict["idref"] {
                let linear = (attributeDict["linear"] ?? "yes").lowercased()
                if linear != "no" { spineIDs.append(idref) }
            }
        case "meta":
            if (attributeDict["name"] ?? "").lowercased() == "cover" {
                coverID = attributeDict["content"]
            }
        case "title":
            if bookTitle == nil { capture = "title"; buffer = "" }
        case "creator":
            if bookAuthor == nil { capture = "author"; buffer = "" }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capture != nil { buffer += string }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = xmlLocalName(elementName)
        guard let role = capture else { return }
        if (role == "title" && name == "title") || (role == "author" && name == "creator") {
            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if role == "title" { bookTitle = value } else { bookAuthor = value }
            capture = nil
            buffer = ""
        }
    }
}

final class NCXParser: NSObject, XMLParserDelegate {

    var entries: [(title: String, src: String)] = []

    private var stack: [(title: String, src: String)] = []
    private var inText = false

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = xmlLocalName(elementName)
        switch name {
        case "navPoint":
            stack.append((title: "", src: ""))
        case "text":
            inText = true
        case "content":
            if !stack.isEmpty, stack[stack.count - 1].src.isEmpty, let src = attributeDict["src"] {
                stack[stack.count - 1].src = src
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText && !stack.isEmpty {
            stack[stack.count - 1].title += string
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = xmlLocalName(elementName)
        if name == "text" { inText = false }
        if name == "navPoint" && !stack.isEmpty {
            let entry = stack.removeLast()
            if !entry.src.isEmpty {
                let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append((title: title.isEmpty ? "未命名" : title, src: entry.src))
            }
        }
    }
}
