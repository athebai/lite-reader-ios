import UIKit
import PDFKit

final class PDFReaderViewController: UIViewController {

    private let book: Book
    private let pdfView = PDFView(frame: .zero)
    private let chrome = ReaderChromeView()
    private let settings = ReaderSettings.shared

    private var document: PDFDocument?
    private var pageCount = 0
    private var chromeVisible = true

    init(book: Book) {
        self.book = book
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = book.title
        setupPDFView()
        setupChrome()
        applyTheme()
        openDocument()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(pageChanged),
                                               name: Notification.Name.PDFViewPageChanged,
                                               object: pdfView)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(saveProgress),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ReadingClock.shared.start(book.fileName)
        BreakReminder.shared.start()
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake
        UIScreen.main.brightness = settings.brightness
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveProgress()
        if isLeavingReader {
            ReadingClock.shared.stop()
            BreakReminder.shared.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    override var prefersStatusBarHidden: Bool {
        return !chromeVisible
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return settings.theme.isDark ? .lightContent : .default
    }

    // MARK: - Setup

    private func setupPDFView() {
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        view.addSubview(pdfView)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        pdfView.addGestureRecognizer(tap)
    }

    private func setupChrome() {
        chrome.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chrome)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chrome.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let tocItem = UIBarButtonItem(title: "目录", style: .plain,
                                      target: self, action: #selector(showOutline))
        let bookmarkItem = UIBarButtonItem(title: "书签", style: .plain,
                                           target: self, action: #selector(showBookmarks))
        let moreItem = UIBarButtonItem(title: "更多", style: .plain,
                                       target: self, action: #selector(showMore))

        let flex = { () -> UIBarButtonItem in
            return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        }
        chrome.setItems([tocItem, flex(), bookmarkItem, flex(), moreItem])
        chrome.onSeek = { [weak self] ratio in
            self?.goToRatio(ratio)
        }
        chrome.apply(theme: settings.theme)
    }

    private func applyTheme() {
        let theme = settings.theme
        view.backgroundColor = theme.background
        pdfView.backgroundColor = theme.background
        chrome.apply(theme: theme)
        navigationController?.applyReaderTheme(theme)
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Document

    private func openDocument() {
        guard let loaded = PDFDocument(url: book.url) else {
            DispatchQueue.main.async { [weak self] in
                self?.showError("无法打开 PDF 文件")
            }
            return
        }
        document = loaded
        pageCount = loaded.pageCount
        pdfView.document = loaded
        pdfView.autoScales = true

        let saved = ProgressStore.shared.ratio(for: book.fileName)
        let page = pageForRatio(saved)
        if let target = loaded.page(at: page) {
            pdfView.go(to: target)
        }
        updateProgress()
    }

    private func pageForRatio(_ ratio: Double) -> Int {
        guard pageCount > 1 else { return 0 }
        let clamped = max(0, min(1, ratio))
        let page = Int(round(clamped * Double(pageCount - 1)))
        return max(0, min(pageCount - 1, page))
    }

    private func currentRatio() -> Double {
        guard let document = document, pageCount > 1,
              let page = pdfView.currentPage else { return 0 }
        let index = document.index(for: page)
        return Double(index) / Double(pageCount - 1)
    }

    private func updateProgress() {
        guard let document = document, pageCount > 0 else { return }
        let index = pdfView.currentPage.map { document.index(for: $0) } ?? 0
        chrome.setProgress(currentRatio(), text: "\(index + 1)/\(pageCount)")
    }

    private func goToRatio(_ ratio: Double) {
        guard let document = document else { return }
        let page = pageForRatio(ratio)
        if let target = document.page(at: page) {
            pdfView.go(to: target)
        }
    }

    @objc private func saveProgress() {
        guard pageCount > 0 else { return }
        ProgressStore.shared.save(ratio: currentRatio(), for: book.fileName)
    }

    @objc private func pageChanged() {
        updateProgress()
        saveProgress()
    }

    // MARK: - Outline

    @objc private func showOutline() {
        guard let root = document?.outlineRoot else {
            showError("这个 PDF 没有书签目录")
            return
        }
        var entries: [(String, PDFDestination?)] = []
        collectOutline(root, depth: 0, into: &entries)
        guard !entries.isEmpty else {
            showError("这个 PDF 没有书签目录")
            return
        }

        var items: [ChoiceItem] = []
        for entry in entries {
            items.append(ChoiceItem(title: entry.0))
        }
        let controller = ChoiceListViewController(title: "目录", items: items)
        controller.onSelect = { [weak self] index in
            guard let self = self, index < entries.count else { return }
            if let destination = entries[index].1 {
                self.pdfView.go(to: destination)
            }
        }
        present(UINavigationController(rootViewController: controller), animated: true, completion: nil)
    }

    private func collectOutline(_ node: PDFOutline,
                                depth: Int,
                                into entries: inout [(String, PDFDestination?)]) {
        let label = node.label ?? "未命名"
        let prefix = String(repeating: "\u{3000}", count: min(depth, 4))
        entries.append((prefix + label, node.destination))
        for index in 0..<node.numberOfChildren {
            if let child = node.child(at: index) {
                collectOutline(child, depth: depth + 1, into: &entries)
            }
        }
    }

    // MARK: - Bookmarks

    @objc private func showBookmarks() {
        let stored = BookmarkStore.shared.bookmarks(for: book.fileName)
        var items: [ChoiceItem] = []
        for bookmark in stored {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            items.append(ChoiceItem(title: bookmark.title,
                                    subtitle: formatter.string(from: bookmark.date)))
        }
        let controller = ChoiceListViewController(title: "书签",
                                                  items: items,
                                                  emptyText: "还没有书签\n在「更多」→「添加书签」里添加")
        controller.onSelect = { [weak self] index in
            guard let self = self else { return }
            let current = BookmarkStore.shared.bookmarks(for: self.book.fileName)
            guard index < current.count else { return }
            self.goToRatio(current[index].ratio)
        }
        controller.onDelete = { [weak self] index in
            guard let self = self else { return }
            BookmarkStore.shared.remove(at: index, for: self.book.fileName)
        }
        present(UINavigationController(rootViewController: controller), animated: true, completion: nil)
    }

    private func addBookmark() {
        guard pageCount > 0 else { return }
        let ratio = currentRatio()
        let index = pdfView.currentPage.map { document?.index(for: $0) ?? 0 } ?? 0
        let suggested = "第 \(index + 1) 页 · \(Int(ratio * 100))%"

        let alert = UIAlertController(title: "添加书签", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = suggested
            field.placeholder = "书签名称"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "添加", style: .default, handler: { [weak self, weak alert] _ in
            guard let self = self else { return }
            let name = alert?.textFields?.first?.text ?? suggested
            let bookmark = Bookmark(title: name.isEmpty ? suggested : name, ratio: ratio)
            BookmarkStore.shared.add(bookmark, for: self.book.fileName)
        }))
        present(alert, animated: true, completion: nil)
    }

    // MARK: - Actions

    @objc private func handleTap() {
        chromeVisible = !chromeVisible
        chrome.isHidden = !chromeVisible
        navigationController?.setNavigationBarHidden(!chromeVisible, animated: true)
        setNeedsStatusBarAppearanceUpdate()
    }

    private func pageIndex() -> Int {
        return pdfView.currentPage.map { document?.index(for: $0) ?? 0 } ?? 0
    }

    /// 音量键翻页（原版「音量加大键 / 音量降低键」）。
    private func pageStep(_ delta: Int) {
        guard let document = document, pageCount > 0 else { return }
        let target = max(0, min(pageCount - 1, pageIndex() + delta))
        if let page = document.page(at: target) {
            pdfView.go(to: page)
        }
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        guard settings.volumeKeyNav else { return super.keyCommands }
        return [
            UIKeyCommand(input: "volumeUp", modifierFlags: [], action: #selector(volumeUp)),
            UIKeyCommand(input: "volumeDown", modifierFlags: [], action: #selector(volumeDown))
        ]
    }

    @objc private func volumeUp() {
        pageStep(1)
    }

    @objc private func volumeDown() {
        pageStep(-1)
    }

    /// PDF 里没有可精确定位的选区，所以高亮的是「当前页摘录」。
    @objc private func highlightCurrentPage() {
        guard let page = pdfView.currentPage, let raw = page.string else {
            showError("当前页没有可摘录的文字")
            return
        }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            showError("当前页没有可摘录的文字")
            return
        }
        let excerpt = String(cleaned.prefix(120))
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let sheet = UIAlertController(title: "高亮颜色",
                                      message: "摘录当前页（第 \(pageIndex() + 1) 页）",
                                      preferredStyle: .actionSheet)
        for (index, name) in HighlightColor.names.enumerated() {
            sheet.addAction(UIAlertAction(title: name, style: .default, handler: { [weak self] _ in
                guard let self = self else { return }
                HighlightsStore.shared.add(text: excerpt, color: index,
                                           ratio: self.currentRatio(), for: self.book.fileName)
            }))
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        presentSheet(sheet)
    }

    @objc private func showHighlights() {
        let controller = HighlightsViewController(bookName: book.fileName, bookTitle: book.title)
        controller.onJump = { [weak self] ratio in
            guard let self = self else { return }
            self.goToRatio(ratio)
        }
        let navigation = UINavigationController(rootViewController: controller)
        let close = UIBarButtonItem(title: "关闭", style: .plain,
                                    target: self, action: #selector(closePresented))
        navigation.navigationItem.leftBarButtonItem = close
        present(navigation, animated: true, completion: nil)
    }

    @objc private func closePresented() {
        dismiss(animated: true, completion: nil)
    }

    private func presentSheet(_ alert: UIAlertController) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = chrome
            popover.sourceRect = CGRect(x: chrome.bounds.midX, y: chrome.bounds.midY,
                                         width: 1, height: 1)
        }
        present(alert, animated: true, completion: nil)
    }

    @objc private func showMore() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "阅读设置", style: .default, handler: { [weak self] _ in
            self?.showSettings()
        }))
        alert.addAction(UIAlertAction(title: "添加书签", style: .default, handler: { [weak self] _ in
            self?.addBookmark()
        }))
        alert.addAction(UIAlertAction(title: "高亮当前页", style: .default, handler: { [weak self] _ in
            self?.highlightCurrentPage()
        }))
        alert.addAction(UIAlertAction(title: "高亮列表", style: .default, handler: { [weak self] _ in
            self?.showHighlights()
        }))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = chrome
            popover.sourceRect = CGRect(x: chrome.bounds.midX, y: chrome.bounds.midY,
                                        width: 1, height: 1)
        }
        present(alert, animated: true, completion: nil)
    }

    private func showSettings() {
        let controller = SettingsViewController(style: .grouped)
        controller.onChange = { [weak self] in
            guard let self = self else { return }
            self.applyTheme()
            UIApplication.shared.isIdleTimerDisabled = self.settings.keepScreenAwake
        }
        present(UINavigationController(rootViewController: controller), animated: true, completion: nil)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}

extension PDFReaderViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
