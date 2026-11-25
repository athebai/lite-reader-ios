import UIKit
import WebKit

final class EPUBReaderViewController: UIViewController {

    private let book: Book
    private let webView: WKWebView
    private let chrome = ReaderChromeView()
    private let loadingLabel = UILabel(frame: .zero)
    private let settings = ReaderSettings.shared
    private let speech = SpeechController()

    private var epub: EPUBBook?
    private var chapters: [EPUBChapter] = []
    private var currentIndex = 0
    private var pendingScroll: Double = 0
    private var chromeVisible = true
    private var speakItem: UIBarButtonItem?
    private var isReadingAloud = false
    private var pendingSpeechStart = false
    private var chapterTextCache: [Int: String] = [:]
    private var highlighter: WebHighlightSupport?

    init(book: Book) {
        self.book = book
        let configuration = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = book.title
        setupWebView()
        setupChrome()
        setupLoading()
        applyTheme()
        loadEPUB()
        setupHighlighter()

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
            stopSpeech()
        }
    }

    deinit {
        webView.scrollView.removeObserver(self, forKeyPath: "contentOffset")
    }

    override var prefersStatusBarHidden: Bool {
        return !chromeVisible
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return settings.theme.isDark ? .lightContent : .default
    }

    // MARK: - Setup

    private func setupWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = settings.theme.background
        webView.scrollView.backgroundColor = settings.theme.background
        webView.scrollView.addObserver(self, forKeyPath: "contentOffset", options: [.new], context: nil)
        webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 112, right: 0)
        webView.scrollView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 112, right: 0)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let controller = webView.configuration.userContentController
        controller.addUserScript(WKUserScript(source: documentStartScript(),
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        webView.addGestureRecognizer(tap)
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
                                      target: self, action: #selector(showTOC))
        let searchItem = UIBarButtonItem(title: "搜索", style: .plain,
                                         target: self, action: #selector(promptSearch))
        let bookmarkItem = UIBarButtonItem(title: "书签", style: .plain,
                                           target: self, action: #selector(showBookmarks))
        let speakButton = UIBarButtonItem(title: "朗读", style: .plain,
                                          target: self, action: #selector(toggleSpeech))
        let moreItem = UIBarButtonItem(title: "更多", style: .plain,
                                       target: self, action: #selector(showMore))
        speakItem = speakButton

        let flex = { () -> UIBarButtonItem in
            return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        }
        let highlightItem = UIBarButtonItem(title: "高亮", style: .plain,
                                            target: self, action: #selector(highlightTap))
        chrome.setItems([tocItem, flex(), searchItem, flex(), highlightItem, flex(),
                         bookmarkItem, flex(), speakButton, flex(), moreItem])
        chrome.onSeek = { [weak self] ratio in
            guard let self = self else { return }
            self.stopSpeech()
            self.apply(ratio: ratio)
        }
        chrome.apply(theme: settings.theme)
    }

    private func setupLoading() {
        loadingLabel.text = "正在解析 EPUB…"
        loadingLabel.textAlignment = .center
        loadingLabel.textColor = .gray
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingLabel)
        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func applyTheme() {
        let theme = settings.theme
        view.backgroundColor = theme.background
        webView.backgroundColor = theme.background
        webView.scrollView.backgroundColor = theme.background
        webView.scrollView.indicatorStyle = theme.isDark ? .white : .black
        chrome.apply(theme: theme)
        navigationController?.applyReaderTheme(theme)
        setNeedsStatusBarAppearanceUpdate()
    }

    private func setupHighlighter() {
        highlighter = WebHighlightSupport(
            webView: webView,
            bookName: book.fileName,
            bookTitle: book.title,
            ratioProvider: { [weak self] in self?.displayRatio() ?? 0 },
            jump: { [weak self] ratio in
                guard let self = self else { return }
                self.stopSpeech()
                self.apply(ratio: ratio)
            },
            presenter: { [weak self] alert in
                guard let self = self else { return }
                if let popover = alert.popoverPresentationController {
                    popover.sourceView = self.chrome
                    popover.sourceRect = CGRect(x: self.chrome.bounds.midX,
                                                y: self.chrome.bounds.midY, width: 1, height: 1)
                    popover.permittedArrowDirections = []
                }
                self.present(alert, animated: true, completion: nil)
            },
            closer: { [weak self] in
                self?.dismiss(animated: true, completion: nil)
            })
    }

    // MARK: - Loading

    private func loadEPUB() {
        let url = book.url
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let parsed = try EPUBParser.prepare(epubURL: url, cacheDirectory: caches)
                DispatchQueue.main.async {
                    self.epub = parsed
                    self.chapters = parsed.chapters
                    if let bookTitle = parsed.title, !bookTitle.isEmpty {
                        self.title = bookTitle
                    }
                    self.loadingLabel.isHidden = true
                    let saved = ProgressStore.shared.ratio(for: self.book.fileName)
                    self.apply(ratio: saved)
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadingLabel.isHidden = true
                    self.showError(readerMessage(error))
                }
            }
        }
    }

    // MARK: - Position

    private func apply(ratio: Double) {
        guard !chapters.isEmpty else { return }
        let clamped = max(0, min(1, ratio))
        let position = min(Double(chapters.count) - 0.000001, clamped * Double(chapters.count))
        var index = Int(position)
        if index < 0 { index = 0 }
        if index >= chapters.count { index = chapters.count - 1 }
        let scroll = position - Double(index)
        showChapter(index: index, scrollRatio: scroll)
    }

    private func showChapter(index: Int, scrollRatio: Double) {
        guard index >= 0 && index < chapters.count else { return }
        currentIndex = index
        pendingScroll = max(0, min(1, scrollRatio))
        title = chapters[index].title
        let root = epub?.root ?? chapters[index].url.deletingLastPathComponent()
        webView.loadFileURL(chapters[index].url, allowingReadAccessTo: root)
        updateProgress()
    }

    private func localScrollRatio() -> Double {
        let scroll = webView.scrollView
        let maxY = scroll.contentSize.height - scroll.bounds.height
        if maxY <= 1 { return 0 }
        return Double(max(0, min(1, scroll.contentOffset.y / maxY)))
    }

    private func displayRatio() -> Double {
        guard !chapters.isEmpty else { return 0 }
        return (Double(currentIndex) + localScrollRatio()) / Double(chapters.count)
    }

    private func updateProgress() {
        let ratio = displayRatio()
        chrome.setProgress(ratio, text: "\(currentIndex + 1)/\(max(1, chapters.count))")
    }

    @objc private func saveProgress() {
        guard !chapters.isEmpty else { return }
        ProgressStore.shared.save(ratio: displayRatio(), for: book.fileName)
    }

    // MARK: - Styling

    private func documentStartScript() -> String {
        let theme = settings.theme
        let background = theme.background.cssHex
        let foreground = theme.text.cssHex
        let size = Int(settings.fontSize)
        let css = "html,body{background:\(background) !important;color:\(foreground) !important;}body{font-size:\(size)px !important;}img{max-width:100% !important;height:auto !important;}"
        let script = """
        (function(){
          var css = '\(css)';
          function inject(){
            var s = document.createElement('style');
            s.innerHTML = css;
            if (document.head) { document.head.appendChild(s); }
          }
          if (document.head) { inject(); }
          else { document.addEventListener('DOMContentLoaded', inject); }
        })();
        """
        return script
    }

    private func applyStyle(completion: (() -> Void)? = nil) {
        let theme = settings.theme
        let background = theme.background.cssHex
        let foreground = theme.text.cssHex
        let accent = theme.accent.cssHex
        let size = Int(settings.fontSize)
        let lineHeight = Double(1.6 + Double(settings.lineSpacing) * 0.02)

        let script = """
        (function(){
          var id = 'lite-reader-style';
          var old = document.getElementById(id);
          if (old && old.parentNode) { old.parentNode.removeChild(old); }
          var style = document.createElement('style');
          style.id = id;
          style.innerHTML = 'html,body{background:\(background) !important;color:\(foreground) !important;}body{font-size:\(size)px !important;line-height:\(lineHeight) !important;padding-left:6px !important;padding-right:6px !important;}p,div,span,li,td,h1,h2,h3,h4,pre{color:\(foreground) !important;}a{color:\(accent) !important;}img{max-width:100% !important;height:auto !important;}';
          if (document.head) { document.head.appendChild(style); }
        })();
        """
        webView.evaluateJavaScript(script) { _, _ in
            completion?()
        }
    }

    private func scrollTo(ratio: Double) {
        let clamped = max(0, min(1, ratio))
        let script = "(function(){var d=document.documentElement;var m=d.scrollHeight-window.innerHeight;if(m>0){window.scrollTo(0,m*\(clamped));}})();"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - Speech

    @objc private func toggleSpeech() {
        if speech.isSpeaking || speech.isPaused {
            stopSpeech()
        } else {
            startSpeech()
        }
    }

    private func startSpeech() {
        guard currentIndex < chapters.count else { return }
        isReadingAloud = true
        speakItem?.title = "停止"

        speech.onRange = nil
        speech.onFinish = { [weak self] in
            guard let self = self, self.isReadingAloud else { return }
            if self.currentIndex + 1 < self.chapters.count {
                self.pendingSpeechStart = true
                self.showChapter(index: self.currentIndex + 1, scrollRatio: 0)
            } else {
                self.stopSpeech()
            }
        }

        if let cached = chapterTextCache[currentIndex], !cached.isEmpty {
            speech.speak(cached, rate: settings.speechRate)
            return
        }

        let index = currentIndex
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self = self, self.isReadingAloud, self.currentIndex == index else { return }
            let text = (value as? String) ?? ""
            if text.isEmpty {
                self.stopSpeech()
                return
            }
            self.chapterTextCache[index] = text
            self.speech.speak(text, rate: self.settings.speechRate)
        }
    }

    private func stopSpeech() {
        isReadingAloud = false
        pendingSpeechStart = false
        speech.stop()
        speakItem?.title = "朗读"
    }

    // MARK: - Actions

    @objc private func handleTap() {
        chromeVisible = !chromeVisible
        chrome.isHidden = !chromeVisible
        navigationController?.setNavigationBarHidden(!chromeVisible, animated: true)
        setNeedsStatusBarAppearanceUpdate()
    }

    @objc private func showTOC() {
        guard !chapters.isEmpty else { return }
        var items: [ChoiceItem] = []
        for (index, chapter) in chapters.enumerated() {
            items.append(ChoiceItem(title: chapter.title, checked: index == currentIndex))
        }
        let controller = ChoiceListViewController(title: "目录", items: items)
        controller.onSelect = { [weak self] index in
            guard let self = self else { return }
            self.stopSpeech()
            self.showChapter(index: index, scrollRatio: 0)
        }
        present(UINavigationController(rootViewController: controller), animated: true, completion: nil)
    }

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
            self.stopSpeech()
            self.apply(ratio: current[index].ratio)
        }
        controller.onDelete = { [weak self] index in
            guard let self = self else { return }
            BookmarkStore.shared.remove(at: index, for: self.book.fileName)
        }
        present(UINavigationController(rootViewController: controller), animated: true, completion: nil)
    }

    @objc private func promptSearch() {
        guard !chapters.isEmpty else { return }
        let alert = UIAlertController(title: "全文搜索", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "输入关键词"
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "搜索", style: .default, handler: { [weak self, weak alert] _ in
            let keyword = alert?.textFields?.first?.text ?? ""
            self?.runSearch(keyword)
        }))
        present(alert, animated: true, completion: nil)
    }

    private func runSearch(_ keyword: String) {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        loadingLabel.text = "正在搜索…"
        loadingLabel.isHidden = false
        let chaptersCopy = chapters

        DispatchQueue.global(qos: .userInitiated).async {
            var items: [ChoiceItem] = []
            var indexes: [Int] = []

            for (index, chapter) in chaptersCopy.enumerated() {
                if items.count >= 120 { break }
                let data = (try? Data(contentsOf: chapter.url)) ?? Data()
                let html = TextDecoder.decode(data) ?? ""
                let text = DocumentText.htmlToText(html) as NSString
                if text.length == 0 { continue }

                var searchRange = NSRange(location: 0, length: text.length)
                var hits = 0
                while hits < 6 && items.count < 120 {
                    let found = text.range(of: query, options: [.caseInsensitive], range: searchRange)
                    if found.location == NSNotFound { break }
                    let padding = 20
                    let start = max(0, found.location - padding)
                    let end = min(text.length, found.location + found.length + padding)
                    var snippet = text.substring(with: NSRange(location: start, length: end - start))
                    snippet = snippet.replacingOccurrences(of: "\n", with: " ")
                    items.append(ChoiceItem(title: snippet, subtitle: chapter.title))
                    indexes.append(index)
                    hits += 1
                    let next = found.location + max(1, found.length)
                    if next >= text.length { break }
                    searchRange = NSRange(location: next, length: text.length - next)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.loadingLabel.isHidden = true
                guard !items.isEmpty else {
                    let alert = UIAlertController(title: "没有找到「\(query)」",
                                                  message: nil,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                    return
                }
                let controller = ChoiceListViewController(title: "\(items.count) 个结果", items: items)
                controller.onSelect = { [weak self] index in
                    guard let self = self, index < indexes.count else { return }
                    self.stopSpeech()
                    let chapterIndex = indexes[index]
                    self.showChapter(index: chapterIndex, scrollRatio: 0)
                }
                self.present(UINavigationController(rootViewController: controller),
                             animated: true,
                             completion: nil)
            }
        }
    }

    @objc private func highlightTap() {
        highlighter?.handleSelection()
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    /// 音量键翻页（原版「音量加大键 / 音量降低键」）。
    override var keyCommands: [UIKeyCommand]? {
        guard settings.volumeKeyNav else { return super.keyCommands }
        return [
            UIKeyCommand(input: "volumeUp", modifierFlags: [], action: #selector(volumeUp)),
            UIKeyCommand(input: "volumeDown", modifierFlags: [], action: #selector(volumeDown))
        ]
    }

    @objc private func volumeUp() {
        scrollByPage(forward: true)
    }

    @objc private func volumeDown() {
        scrollByPage(forward: false)
    }

    private func scrollByPage(forward: Bool) {
        let direction = forward ? "1" : "-1"
        let script = "(function(){window.scrollBy(0, \(direction) * window.innerHeight * 0.9);})();"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    @objc private func showMore() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "阅读设置", style: .default, handler: { [weak self] _ in
            self?.showSettings()
        }))
        alert.addAction(UIAlertAction(title: "添加书签", style: .default, handler: { [weak self] _ in
            self?.addBookmark()
        }))
        alert.addAction(UIAlertAction(title: "高亮列表", style: .default, handler: { [weak self] _ in
            self?.highlighter?.showList()
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
            self.applyStyle()
            UIApplication.shared.isIdleTimerDisabled = self.settings.keepScreenAwake
        }
        present(UINavigationController(rootViewController: controller), animated: true, completion: nil)
    }

    private func addBookmark() {
        guard !chapters.isEmpty else { return }
        let ratio = displayRatio()
        let suggested = "\(chapters[currentIndex].title) · \(Int(ratio * 100))%"

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

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "打不开这本书", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "contentOffset" && !chapters.isEmpty {
            updateProgress()
        }
    }
}

// MARK: - Web navigation

extension EPUBReaderViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let ratio = pendingScroll
        pendingScroll = 0
        applyStyle { [weak self] in
            guard let self = self else { return }
            self.scrollTo(ratio: ratio)
            self.updateProgress()
            if self.pendingSpeechStart {
                self.pendingSpeechStart = false
                self.startSpeech()
            }
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        updateProgress()
        if pendingSpeechStart {
            stopSpeech()
        }
    }
}

// MARK: - Tap gesture

extension EPUBReaderViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
