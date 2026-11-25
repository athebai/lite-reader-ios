import Foundation

struct Chapter {
    let title: String
    let range: NSRange
}

enum ChapterParser {

    private static let chapterPattern = "(?m)^[ \\t\u{3000}]*(?:第[0-9０-９零〇一二三四五六七八九十百千万两]{1,8}[章节節回卷部篇集话話]|序章|序言|楔子|引子|前言|后记|後記|尾声|尾聲|番外|尾声|Chapter\\s+\\d+|CHAPTER\\s+\\d+)[^\\n]{0,40}$"

    static func parse(_ text: String) -> [Chapter] {
        let nsText = text as NSString
        if nsText.length == 0 { return [] }

        var chapters = parseHeadings(nsText)
        if chapters.count < 2 {
            chapters = splitIntoChunks(nsText)
        }
        return chapters
    }

    private static func parseHeadings(_ text: NSString) -> [Chapter] {
        guard let regex = try? NSRegularExpression(pattern: chapterPattern, options: []) else {
            return []
        }
        let fullRange = NSRange(location: 0, length: text.length)
        let matches = regex.matches(in: text as String, options: [], range: fullRange)
        guard matches.count >= 2 else { return [] }

        var chapters: [Chapter] = []
        if matches[0].range.location > 200 {
            chapters.append(Chapter(title: "开始",
                                    range: NSRange(location: 0, length: matches[0].range.location)))
        }

        for index in 0..<matches.count {
            let match = matches[index]
            let start = match.range.location
            let end: Int
            if index + 1 < matches.count {
                end = matches[index + 1].range.location
            } else {
                end = text.length
            }
            if end <= start { continue }
            let rawTitle = text.substring(with: match.range)
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            chapters.append(Chapter(title: title.isEmpty ? "第 \(chapters.count + 1) 章" : title,
                                    range: NSRange(location: start, length: end - start)))
        }
        return chapters
    }

    private static func splitIntoChunks(_ text: NSString) -> [Chapter] {
        let chunkSize = 12000
        var chapters: [Chapter] = []
        var location = 0
        var index = 1

        while location < text.length {
            var length = min(chunkSize, text.length - location)
            if location + length < text.length && length > 600 {
                let searchStart = location + length - 400
                let searchRange = NSRange(location: searchStart, length: 400)
                let newline = text.range(of: "\n", options: .backwards, range: searchRange)
                if newline.location != NSNotFound {
                    length = newline.location - location + 1
                }
            }
            if length <= 0 { break }
            chapters.append(Chapter(title: "第 \(index) 节",
                                    range: NSRange(location: location, length: length)))
            location += length
            index += 1
        }
        return chapters
    }

    static func index(of offset: Int, in chapters: [Chapter]) -> Int {
        guard !chapters.isEmpty else { return 0 }
        var low = 0
        var high = chapters.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let chapter = chapters[middle]
            if offset < chapter.range.location {
                high = middle - 1
            } else if offset >= chapter.range.location + chapter.range.length {
                low = middle + 1
            } else {
                return middle
            }
        }
        return max(0, min(chapters.count - 1, low))
    }
}
