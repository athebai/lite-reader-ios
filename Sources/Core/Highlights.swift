import UIKit

/// One highlighted passage. `ratio` is book-wide so highlights survive
/// re-chaptering; the text itself is kept because different formats cannot
/// all be re-located from an offset.
struct Highlight: Codable, Equatable {
    var id: String
    var text: String
    var color: Int
    var note: String
    var ratio: Double
    var date: Date

    init(text: String,
         color: Int = 0,
         note: String = "",
         ratio: Double = 0,
         date: Date = Date()) {
        self.id = UUID().uuidString
        self.text = text
        self.color = color
        self.note = note
        self.ratio = ratio
        self.date = date
    }
}

/// Highlight colours offered by the original app's 标注弹窗.
enum HighlightColor {

    static let names = ["黄色", "绿色", "蓝色", "粉色"]

    static func color(_ index: Int) -> UIColor {
        let clamped = max(0, min(names.count - 1, index))
        switch clamped {
        case 0:  return UIColor(red: 0.99, green: 0.87, blue: 0.36, alpha: 1.0)
        case 1:  return UIColor(red: 0.62, green: 0.86, blue: 0.55, alpha: 1.0)
        case 2:  return UIColor(red: 0.55, green: 0.79, blue: 0.98, alpha: 1.0)
        default: return UIColor(red: 0.99, green: 0.71, blue: 0.83, alpha: 1.0)
        }
    }
}

/// JSON backed store, one list per book file name.
final class HighlightsStore {

    static let shared = HighlightsStore()

    private let fileName = "Highlights.json"
    private let queue = DispatchQueue(label: "lite.reader.highlights")
    private var cache: [String: [Highlight]]?

    private var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func load() -> [String: [Highlight]] {
        if let cached = cache { return cached }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [Highlight]].self, from: data) else {
            cache = [:]
            return [:]
        }
        cache = decoded
        return decoded
    }

    private func persist(_ all: [String: [Highlight]]) {
        cache = all
        queue.async {
            if let data = try? JSONEncoder().encode(all) {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }

    func highlights(for book: String) -> [Highlight] {
        let list = load()[book] ?? []
        return list.sorted { $0.date > $1.date }
    }

    func add(text: String,
             color: Int = 0,
             note: String = "",
             ratio: Double = 0,
             for book: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var all = load()
        var list = all[book] ?? []
        if list.contains(where: { $0.text == trimmed }) { return }
        list.insert(Highlight(text: trimmed, color: color, note: note, ratio: ratio), at: 0)
        all[book] = list
        persist(all)
    }

    func remove(at index: Int, for book: String) {
        var all = load()
        guard var list = all[book], index >= 0, index < list.count else { return }
        list.remove(at: index)
        all[book] = list
        persist(all)
    }

    func remove(id: String, for book: String) {
        var all = load()
        guard var list = all[book] else { return }
        list.removeAll { $0.id == id }
        all[book] = list
        persist(all)
    }

    func removeAll(for book: String) {
        var all = load()
        all.removeValue(forKey: book)
        persist(all)
    }

    /// Plain text export used by 分享/导出高亮.
    func exportText(for book: String, title: String) -> String {
        let list = highlights(for: book)
        var output = "《\(title)》 高亮与摘录 · \(list.count) 条\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        for item in list {
            let colour = HighlightColor.names[min(item.color, HighlightColor.names.count - 1)]
            output += "\n[\(colour)]"
            output += " \(item.text)"
            if !item.note.isEmpty { output += "\n   备注：\(item.note)" }
            output += "\n   \(Int(item.ratio * 100))% · \(formatter.string(from: item.date))\n"
        }
        return output
    }
}