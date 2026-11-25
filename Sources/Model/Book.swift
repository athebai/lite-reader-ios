import Foundation

enum BookType: String {
    case txt
    case epub
    case pdf
    case html
    case docx
    case rtf

    var displayName: String {
        switch self {
        case .txt:  return "TXT"
        case .epub: return "EPUB"
        case .pdf:  return "PDF"
        case .html: return "HTML"
        case .docx: return "DOCX"
        case .rtf:  return "RTF"
        }
    }

    init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "txt", "text":
            self = .txt
        case "epub":
            self = .epub
        case "pdf":
            self = .pdf
        case "html", "htm", "xhtml":
            self = .html
        case "docx":
            self = .docx
        case "rtf":
            self = .rtf
        default:
            return nil
        }
    }
}

struct Book {
    let fileName: String
    let title: String
    let type: BookType
    let added: Date
    let fileSize: Int64

    var key: String { return fileName }

    var url: URL {
        return BookStore.shared.booksDirectory.appendingPathComponent(fileName)
    }

    var sizeText: String {
        if fileSize >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(fileSize) / 1024.0 / 1024.0)
        }
        return String(format: "%ld KB", max(1, fileSize / 1024))
    }
}

final class BookStore {

    static let shared = BookStore()

    let booksDirectory: URL
    private(set) var books: [Book] = []
    private let favoritesKey = "library.favorites"

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        booksDirectory = docs.appendingPathComponent("Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDirectory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
    }

    func reload() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let keySet = Set(keys)
        let urls = (try? fm.contentsOfDirectory(at: booksDirectory,
                                                includingPropertiesForKeys: keys,
                                                options: [.skipsHiddenFiles])) ?? []

        var result: [Book] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
            guard values.isRegularFile == true else { continue }
            guard let type = BookType(fileExtension: url.pathExtension) else { continue }
            let date = values.contentModificationDate ?? Date()
            let size = Int64(values.fileSize ?? 0)
            let title = url.deletingPathExtension().lastPathComponent
            result.append(Book(fileName: url.lastPathComponent,
                               title: title,
                               type: type,
                               added: date,
                               fileSize: size))
        }

        books = result.sorted { $0.added > $1.added }
    }

    @discardableResult
    func importFile(from url: URL) -> Book? {
        guard BookType(fileExtension: url.pathExtension) != nil else { return nil }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let name = url.lastPathComponent
        let destination = booksDirectory.appendingPathComponent(name)
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }
        do {
            try fm.copyItem(at: url, to: destination)
        } catch {
            NSLog("import failed: \(error)")
            return nil
        }
        reload()
        return books.first { $0.fileName == name }
    }

    func delete(_ book: Book) {
        try? FileManager.default.removeItem(at: book.url)
        reload()
    }

    var favoriteNames: Set<String> {
        get { return Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: favoritesKey) }
    }

    func isFavorite(_ book: Book) -> Bool {
        return favoriteNames.contains(book.fileName)
    }

    @discardableResult
    func toggleFavorite(_ book: Book) -> Bool {
        var names = favoriteNames
        let nowFavorite: Bool
        if names.contains(book.fileName) {
            names.remove(book.fileName)
            nowFavorite = false
        } else {
            names.insert(book.fileName)
            nowFavorite = true
        }
        favoriteNames = names
        return nowFavorite
    }
}

func readerMessage(_ error: Error) -> String {
    if let readerError = error as? ReaderError {
        switch readerError {
        case .message(let text):
            return text
        }
    }
    return error.localizedDescription
}
