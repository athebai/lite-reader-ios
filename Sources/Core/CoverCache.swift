import UIKit
import PDFKit

final class CoverCache {

    static let shared = CoverCache()

    private let memory = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "lite.reader.covers", qos: .utility)
    private let directory: URL
    private let cacheRoot: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheRoot = caches
        directory = caches.appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        memory.countLimit = 60
    }

    private func cacheKey(for book: Book) -> String {
        return "\(book.fileName)-\(book.fileSize)-\(Int(book.added.timeIntervalSince1970))"
    }

    private func cacheFile(for book: Book) -> URL {
        return directory.appendingPathComponent(FileKey.make(cacheKey(for: book), maxPrefix: 36) + ".jpg")
    }

    func cachedCover(for book: Book) -> UIImage? {
        let key = cacheKey(for: book) as NSString
        if let image = memory.object(forKey: key) { return image }
        if let image = UIImage(contentsOfFile: cacheFile(for: book).path) {
            memory.setObject(image, forKey: key)
            return image
        }
        return nil
    }

    func cover(for book: Book, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        if let image = cachedCover(for: book) {
            completion(image)
            return
        }
        queue.async {
            let image = self.generate(book: book, size: size)
            if let image = image {
                self.memory.setObject(image, forKey: self.cacheKey(for: book) as NSString)
                if let data = image.jpegData(compressionQuality: 0.82) {
                    try? data.write(to: self.cacheFile(for: book))
                }
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func removeCover(for book: Book) {
        memory.removeObject(forKey: cacheKey(for: book) as NSString)
        try? FileManager.default.removeItem(at: cacheFile(for: book))
    }

    // MARK: - Generation

    private func generate(book: Book, size: CGSize) -> UIImage? {
        switch book.type {
        case .pdf:
            if let image = pdfCover(book, size: size) { return image }
        case .epub:
            if let image = epubCover(book, size: size) { return image }
        default:
            break
        }
        return generatedCover(book, size: size)
    }

    private func pdfCover(_ book: Book, size: CGSize) -> UIImage? {
        guard let document = PDFDocument(url: book.url),
              let page = document.page(at: 0) else { return nil }
        let thumbnail = page.thumbnail(of: size, for: .cropBox)
        return fitted(thumbnail, size: size)
    }

    private func epubCover(_ book: Book, size: CGSize) -> UIImage? {
        guard let epub = try? EPUBParser.prepare(epubURL: book.url, cacheDirectory: cacheRoot),
              let coverURL = epub.coverURL,
              let image = UIImage(contentsOfFile: coverURL.path) else { return nil }
        return fitted(image, size: size)
    }

    private func fitted(_ image: UIImage, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let widthScale = size.width / max(1, image.size.width)
            let heightScale = size.height / max(1, image.size.height)
            let scale = max(widthScale, heightScale)
            let drawSize = CGSize(width: image.size.width * scale,
                                  height: image.size.height * scale)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2,
                                 y: (size.height - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    private func generatedCover(_ book: Book, size: CGSize) -> UIImage {
        let palettes: [(UIColor, UIColor)] = [
            (UIColor(red: 0.20, green: 0.28, blue: 0.36, alpha: 1), UIColor(red: 0.10, green: 0.14, blue: 0.19, alpha: 1)),
            (UIColor(red: 0.38, green: 0.30, blue: 0.24, alpha: 1), UIColor(red: 0.19, green: 0.14, blue: 0.11, alpha: 1)),
            (UIColor(red: 0.26, green: 0.36, blue: 0.30, alpha: 1), UIColor(red: 0.12, green: 0.18, blue: 0.15, alpha: 1)),
            (UIColor(red: 0.40, green: 0.26, blue: 0.28, alpha: 1), UIColor(red: 0.20, green: 0.12, blue: 0.13, alpha: 1)),
            (UIColor(red: 0.30, green: 0.30, blue: 0.40, alpha: 1), UIColor(red: 0.14, green: 0.14, blue: 0.20, alpha: 1))
        ]
        var seed = 0
        for scalar in book.title.unicodeScalars { seed = (seed &* 31 &+ Int(scalar.value)) & 0xFFFF }
        let palette = palettes[abs(seed) % palettes.count]

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [palette.0.cgColor, palette.1.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: [0, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: 0, y: 0),
                                      end: CGPoint(x: size.width * 0.3, y: size.height),
                                      options: [])
            } else {
                palette.1.setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }

            let spineWidth = max(3, size.width * 0.035)
            UIColor(white: 1.0, alpha: 0.16).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: spineWidth, height: size.height))

            let white = UIColor(white: 1.0, alpha: 0.92)
            let titleFont = UIFont.systemFont(ofSize: max(11, size.width * 0.115), weight: .medium)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: white,
                .paragraphStyle: paragraph
            ]
            let inset = size.width * 0.12
            let textRect = CGRect(x: inset,
                                  y: size.height * 0.30,
                                  width: size.width - inset * 2,
                                  height: size.height * 0.42)
            (book.title as NSString).draw(in: textRect, withAttributes: attributes)

            let typeFont = UIFont.systemFont(ofSize: max(8, size.width * 0.065), weight: .regular)
            let typeAttributes: [NSAttributedString.Key: Any] = [
                .font: typeFont,
                .foregroundColor: UIColor(white: 1.0, alpha: 0.55)
            ]
            let typeRect = CGRect(x: inset,
                                  y: size.height - size.height * 0.12,
                                  width: size.width - inset * 2,
                                  height: size.height * 0.08)
            (book.type.displayName as NSString).draw(in: typeRect, withAttributes: typeAttributes)
        }
    }
}
