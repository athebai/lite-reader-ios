import Foundation

// MARK: - Reading position

struct ReadingPosition: Codable {
    var ratio: Double = 0
    var updated: Date = Date()
}

final class ProgressStore {

    static let shared = ProgressStore()

    private let positionsKey = "reader.positions"
    private let lastBookKey = "reader.lastBook"
    private var cache: [String: ReadingPosition]?

    private func loadPositions() -> [String: ReadingPosition] {
        if let cached = cache { return cached }
        guard let data = UserDefaults.standard.data(forKey: positionsKey),
              let decoded = try? JSONDecoder().decode([String: ReadingPosition].self, from: data) else {
            cache = [:]
            return [:]
        }
        cache = decoded
        return decoded
    }

    private func persist(_ positions: [String: ReadingPosition]) {
        cache = positions
        if let data = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(data, forKey: positionsKey)
        }
    }

    func position(for book: String) -> ReadingPosition? {
        return loadPositions()[book]
    }

    func ratio(for book: String) -> Double {
        return loadPositions()[book]?.ratio ?? 0
    }

    func save(ratio: Double, for book: String) {
        var positions = loadPositions()
        var position = positions[book] ?? ReadingPosition()
        position.ratio = max(0, min(1, ratio))
        position.updated = Date()
        positions[book] = position
        persist(positions)
    }

    func remove(for book: String) {
        var positions = loadPositions()
        positions.removeValue(forKey: book)
        persist(positions)
    }

    var lastBook: String? {
        get { return UserDefaults.standard.string(forKey: lastBookKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastBookKey) }
    }
}

// MARK: - Bookmarks

struct Bookmark: Codable {
    var id: String = UUID().uuidString
    var title: String
    var ratio: Double
    var date: Date = Date()
}

final class BookmarkStore {

    static let shared = BookmarkStore()

    private let storageKey = "reader.bookmarks"
    private var cache: [String: [Bookmark]]?

    private func loadAll() -> [String: [Bookmark]] {
        if let cached = cache { return cached }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [Bookmark]].self, from: data) else {
            cache = [:]
            return [:]
        }
        cache = decoded
        return decoded
    }

    private func persist(_ all: [String: [Bookmark]]) {
        cache = all
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func bookmarks(for book: String) -> [Bookmark] {
        return loadAll()[book] ?? []
    }

    func add(_ bookmark: Bookmark, for book: String) {
        var all = loadAll()
        var list = all[book] ?? []
        list.insert(bookmark, at: 0)
        all[book] = list
        persist(all)
    }

    func remove(at index: Int, for book: String) {
        var all = loadAll()
        guard var list = all[book], index >= 0, index < list.count else { return }
        list.remove(at: index)
        all[book] = list
        persist(all)
    }

    func removeAll(for book: String) {
        var all = loadAll()
        all.removeValue(forKey: book)
        persist(all)
    }
}

// MARK: - Statistics

final class ReadingStats {

    static let shared = ReadingStats()

    private let dailyKey = "stats.daily"
    private let bookKey = "stats.books"
    private let charsKey = "stats.characters"
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func loadDaily() -> [String: Double] {
        return UserDefaults.standard.dictionary(forKey: dailyKey) as? [String: Double] ?? [:]
    }

    private func loadBooks() -> [String: Double] {
        return UserDefaults.standard.dictionary(forKey: bookKey) as? [String: Double] ?? [:]
    }

    private func key(for date: Date) -> String {
        return formatter.string(from: date)
    }

    /// 「阅读速度(字/分钟)」的分子：累计已读字数。
    var charactersRead: Double {
        return UserDefaults.standard.double(forKey: charsKey)
    }

    func addCharacters(_ amount: Double) {
        let value = charactersRead + max(0, amount)
        UserDefaults.standard.set(value, forKey: charsKey)
    }

    /// 平均阅读速度，单位字/分钟。
    var readingSpeed: Double {
        let minutes = totalSeconds / 60
        guard minutes > 0.2 else { return 0 }
        return charactersRead / minutes
    }

    func add(seconds: Double, book: String) {
        guard seconds > 0 else { return }
        var daily = loadDaily()
        let today = key(for: Date())
        daily[today] = (daily[today] ?? 0) + seconds
        UserDefaults.standard.set(daily, forKey: dailyKey)

        var books = loadBooks()
        books[book] = (books[book] ?? 0) + seconds
        UserDefaults.standard.set(books, forKey: bookKey)
    }

    var todaySeconds: Double {
        return loadDaily()[key(for: Date())] ?? 0
    }

    var totalSeconds: Double {
        let daily = loadDaily()
        return daily.values.reduce(0, +)
    }

    func seconds(forBook book: String) -> Double {
        return loadBooks()[book] ?? 0
    }

    func topBooks(_ limit: Int) -> [(name: String, seconds: Double)] {
        let books = loadBooks()
        let sorted = books.sorted { $0.value > $1.value }
        var result: [(name: String, seconds: Double)] = []
        for item in sorted {
            if result.count >= limit { break }
            result.append((name: item.key, seconds: item.value))
        }
        return result
    }

    var streakDays: Int {
        let daily = loadDaily()
        var streak = 0
        var date = Date()
        let calendar = Calendar.current
        for _ in 0..<3650 {
            let dayKey = key(for: date)
            let seconds = daily[dayKey] ?? 0
            if seconds >= 60 {
                streak += 1
            } else if streak == 0 && calendar.isDateInToday(date) {
                // today not counted yet, keep looking at yesterday
            } else {
                break
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return streak
    }

    var dailyHistory: [(day: String, seconds: Double)] {
        let daily = loadDaily()
        return daily.sorted { $0.key > $1.key }.map { (day: $0.key, seconds: $0.value) }
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: dailyKey)
        UserDefaults.standard.removeObject(forKey: bookKey)
    }
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds)
    if total < 60 { return "\(total) 秒" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes) 分钟" }
    let hours = minutes / 60
    let remain = minutes % 60
    if hours < 24 { return "\(hours) 小时 \(remain) 分" }
    let days = hours / 24
    return "\(days) 天 \(hours % 24) 小时"
}

// MARK: - Reading clock

final class ReadingClock {

    static let shared = ReadingClock()

    private var startedAt: Date?
    private var bookName: String?

    func start(_ book: String) {
        stop()
        bookName = book
        startedAt = Date()
    }

    func stop() {
        guard let start = startedAt, let name = bookName else {
            startedAt = nil
            bookName = nil
            return
        }
        let seconds = Date().timeIntervalSince(start)
        if seconds >= 3 && seconds <= 6 * 3600 {
            ReadingStats.shared.add(seconds: seconds, book: name)
        }
        startedAt = nil
        bookName = nil
    }
}
