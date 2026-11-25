import UIKit

final class TextReaderViewController: UIViewController {

    private let book: Book
    private let textView = UITextView(frame: .zero)
    private let chrome = ReaderChromeView()
    private let loadingLabel = UILabel(frame: .zero)
    private let settings = ReaderSettings.shared
    private let speech = SpeechController()

    private var fullText = NSString(string: "")
    private var chapters: [Chapter] = []
    private var currentChapter = 0
    private var pendingScroll: Double?
    private var chromeVisible = true
    private var autoScrollTimer: Timer?
    private var autoScrolling = false
    private var speakItem: UIBarButtonItem?
    private var isReadingAloud = false
    private var speechBaseOffset = 0

    /// 上一个搜索的命中位置，用于「上一个/下一个」。
    private var lastSearchOffsets: [Int] = []
    private var lastSearchIndex = -1

    private enum SearchScope: Int {
        case all = 0
        case unread = 1
        case read = 2

        var title: String {
            switch self {
            case .all:    return "全书"
            case .unread: return "未读部分（向前）"
            case .read:   return "已读部分（向后）"
            }
        }
    }
    private var searchScope: SearchScope = .all
    private var appliedFlipMode: FlipMode?

    init(book: Book) {
        self.book = book
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        autoScrollTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = book.title
        setupTextView()
        setupChrome()
        setupLoading()
        applyTheme()
        loadText()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(saveProgress),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(settingsChanged),
                                               name: .readerSettingsChanged,
                                               object: nil)
    }

    @objc private func settingsChanged() {
        appliedFlipMode = nil
        applyTheme()
        guard fullText.length > 0, !chapters.isEmpty else { return }
        reloadChapter(localRatio: localRatio())
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
            stopAutoScroll()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool {
        return true
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
        pageForward()
    }

    @objc private func volumeDown() {
        pageBack()
    }

    override var prefersStatusBarHidden: Bool {
        return !chromeVisible
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return settings.theme.isDark ? .lightContent : .default
    }

    // MARK: - Setup

    private func setupTextView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = false
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        textView.delegate = self
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        tap.numberOfTapsRequired = 1
        textView.addGestureRecognizer(tap)
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
                                            target: self, action: #selector(highlightSelection))
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
        loadingLabel.text = "正在载入…"
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
        textView.backgroundColor = theme.background
        textView.indicatorStyle = theme.isDark ? .white : .black
        chrome.apply(theme: theme)
        navigationController?.applyReaderTheme(theme)
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Loading

    private func loadText() {
        let url = book.url
        let type = book.type
        DispatchQueue.global(qos: .userInitiated).async {
            var text: String? = nil
            if type == .txt {
                if let data = try? Data(contentsOf: url) {
                    text = TextDecoder.decode(data)
                }
            } else {
                text = DocumentText.plainText(for: Book(fileName: url.lastPathComponent,
                                                        title: url.deletingPathExtension().lastPathComponent,
                                                        type: type,
                                                        added: Date(),
                                                        fileSize: 0))
            }
            let content = text ?? ""
            let parsed = ChapterParser.parse(content)
            DispatchQueue.main.async {
                if content.isEmpty {
                    self.loadingLabel.text = "文件为空，或编码无法识别"
                    self.loadingLabel.isHidden = false
                    return
                }
                self.fullText = content as NSString
                self.chapters = parsed
                self.loadingLabel.isHidden = true
                let saved = ProgressStore.shared.ratio(for: self.book.fileName)
                self.apply(ratio: saved)
            }
        }
    }

    // MARK: - Position

    private func apply(ratio: Double) {
        guard fullText.length > 0, !chapters.isEmpty else { return }
        let clamped = max(0, min(1, ratio))
        let offset = Int(Double(fullText.length - 1) * clamped)
        let index = ChapterParser.index(of: offset, in: chapters)
        let chapter = chapters[index]
        var local: Double = 0
        if chapter.range.length > 0 {
            local = Double(offset - chapter.range.location) / Double(chapter.range.length)
        }
        showChapter(index: index, localRatio: local)
    }

    private func showChapter(index: Int, localRatio: Double) {
        guard index >= 0, index < chapters.count else { return }
        currentChapter = index
        title = chapters[index].title
        reloadChapter(localRatio: localRatio)
    }

    private func reloadChapter(localRatio: Double) {
        guard !chapters.isEmpty else { return }
        let chapter = chapters[currentChapter]
        let content = fullText.substring(with: chapter.range)
        render(content)
        pendingScroll = localRatio
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let ratio = self.pendingScroll else { return }
            self.pendingScroll = nil
            self.textView.layoutIfNeeded()
            self.scrollToLocalRatio(ratio)
            self.updateProgressLabel()
        }
    }

    private func render(_ content: String) {
        let theme = settings.theme
        view.backgroundColor = theme.background
        textView.backgroundColor = theme.background
        textView.indicatorStyle = theme.isDark ? .white : .black

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = settings.lineSpacing
        paragraph.paragraphSpacing = settings.lineSpacing
        paragraph.firstLineHeadIndent = settings.fontSize * settings.indentChars
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: settings.font,
            .foregroundColor: theme.text,
            .paragraphStyle: paragraph,
            .kern: settings.letterSpacing
        ]
        textView.textContainerInset = UIEdgeInsets(top: 18,
                                                   left: settings.margin,
                                                   bottom: 96,
                                                   right: settings.margin)
        let attributed = NSMutableAttributedString(string: content, attributes: attributes)
        applyHighlights(to: attributed)
        textView.attributedText = attributed
        textView.setContentOffset(.zero, animated: false)
        applyFlipMode()
    }

    /// 左右两种翻页方式（原版「向左/向右翻页」「纸张翻页效果」）。
    private var horizontalMode: Bool {
        return settings.flipMode.isHorizontal
    }

    private func scrollMax() -> CGFloat {
        if horizontalMode {
            return max(0, textView.contentSize.width - textView.bounds.width)
        }
        return max(0, textView.contentSize.height - textView.bounds.height)
    }

    private func scrollPosition() -> CGFloat {
        return max(0, horizontalMode ? textView.contentOffset.x : textView.contentOffset.y)
    }

    private func scrollTo(offset: CGFloat, animated: Bool) {
        if horizontalMode {
            textView.setContentOffset(CGPoint(x: offset, y: 0), animated: animated)
        } else {
            textView.setContentOffset(CGPoint(x: 0, y: offset), animated: animated)
        }
    }

    private func pageForward() {
        let maxOffset = scrollMax()
        if scrollPosition() >= maxOffset - 1 {
            if currentChapter + 1 < chapters.count {
                showChapter(index: currentChapter + 1, localRatio: 0)
            }
            return
        }
        let target = min(maxOffset, scrollPosition() + textView.bounds.width)
        scrollTo(offset: target, animated: true)
    }

    private func pageBack() {
        let target = scrollPosition() - textView.bounds.width
        if target <= 0 {
            if currentChapter > 0 {
                showChapter(index: currentChapter - 1, localRatio: 1)
            } else {
                scrollTo(offset: 0, animated: true)
            }
            return
        }
        scrollTo(offset: max(0, target), animated: true)
    }

    private func scrollToLocalRatio(_ ratio: Double) {
        let maxOffset = scrollMax()
        let clamped = max(0, min(1, ratio))
        scrollTo(offset: CGFloat(clamped) * maxOffset, animated: false)
    }

    private func localRatio() -> Double {
        let maxOffset = max(1, scrollMax())
        return Double(max(0, min(1, scrollPosition() / maxOffset)))
    }

    /// Widens the text container so a page never wraps, which gives real
    /// page-by-page panning instead of a scroll view.
    private func applyFlipMode() {
        guard textView.bounds.width > 0 else { return }
        let mode = settings.flipMode
        if !mode.isHorizontal && appliedFlipMode == mode { return }
        appliedFlipMode = mode
        let inset = textView.textContainerInset
        let width: CGFloat
        if mode.isHorizontal {
            let cap = textView.bounds.width * 40
            let measured = textView.contentSize.width - inset.left - inset.right
            width = max(60, min(cap, measured))
        } else {
            width = max(60, textView.bounds.width - inset.left - inset.right)
        }
        textView.textContainer.size = CGSize(width: width, height: CGFLOAT_MAX)
        textView.textContainer.exclusionPath = nil
    }

    private func currentRatio() -> Double {
        guard fullText.length > 0, !chapters.isEmpty else { return 0 }
        let chapter = chapters[currentChapter]
        let offset = Double(chapter.range.location) + localRatio() * Double(chapter.range.length)
        return max(0, min(1, offset / Double(fullText.length)))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard fullText.length > 0, !chapters.isEmpty else { return }
        applyFlipMode()
    }

    private func updateProgressLabel() {
        chrome.setProgress(currentRatio(), text: progressText(currentRatio()))
    }

    /// 把已保存的高亮按文本匹配画回当前章节（原文/目录/格式都可能重排）。
    private func applyHighlights(to attributed: NSMutableAttributedString) {
        let list = HighlightsStore.shared.highlights(for: book.fileName)
        guard !list.isEmpty else { return }
        let length = attributed.length
        for item in list {
            guard !item.text.isEmpty else { continue }
            let found = (attributed.string as NSString).range(of: item.text,
                                                              options: [],
                                                              range: NSRange(location: 0, length: length))
            if found.location != NSNotFound {
                attributed.addAttribute(.backgroundColor,
                                         value: HighlightColor.color(item.color),
                                         range: found)
            }
        }
    }

    /// 有选中文字时高亮它，否则打开本书的高亮列表。
    @objc private func highlightSelection() {
        let range = textView.selectedRange
        if range.length > 0 {
            let text = textView.text?.substring(with: range) ?? ""
            let sheet = UIAlertController(title: "高亮颜色",
                                          message: "已选中 \(range.length) 字",
                                          preferredStyle: .actionSheet)
            for (index, name) in HighlightColor.names.enumerated() {
                sheet.addAction(UIAlertAction(title: name, style: .default, handler: { [weak self] _ in
                    self?.storeHighlight(text: text, range: range, color: index)
                }))
            }
            sheet.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
            presentSheet(sheet)
            return
        }
        showHighlights()
    }

    private func storeHighlight(text: String, range: NSRange, color: Int) {
        let chapterStart = chapters.isEmpty ? 0 : chapters[currentChapter].range.location
        let location = chapterStart + min(range.location, max(0, fullText.length - chapterStart))
        let ratio = fullText.length > 0 ? Double(location) / Double(fullText.length) : 0
        HighlightsStore.shared.add(text: text, color: color, ratio: ratio, for: book.fileName)
        textView.textStorage?.addAttribute(.backgroundColor,
                                           value: HighlightColor.color(color),
                                           range: range)
        textView.selectedRange = NSRange(location: NSNotFound, length: 0)
    }

    @objc private func showHighlights() {
        let controller = HighlightsViewController(bookName: book.fileName, bookTitle: book.title)
        controller.onJump = { [weak self] ratio in
            guard let self = self else { return }
            self.stopSpeech()
            self.apply(ratio: ratio)
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

    // MARK: - Speech

    @objc private func toggleSpeech() {
        if speech.isSpeaking || speech.isPaused {
            stopSpeech()
        } else {
            startSpeech()
        }
    }

    private func startSpeech() {
        guard !chapters.isEmpty else { return }
        let chapter = chapters[currentChapter]
        let content = fullText.substring(with: chapter.range) as NSString
        let offset = min(content.length, Int(Double(content.length) * localRatio()))
        speechBaseOffset = offset
        let text = content.substring(from: offset)
        guard !text.isEmpty else { return }

        isReadingAloud = true
        speakItem?.title = "停止"

        speech.onRange = { [weak self] range in
            guard let self = self, self.isReadingAloud else { return }
            let localRange = NSRange(location: range.location + self.speechBaseOffset,
                                     length: range.length)
            self.revealIfNeeded(localRange)
        }
        speech.onFinish = { [weak self] in
            guard let self = self, self.isReadingAloud else { return }
            if self.currentChapter + 1 < self.chapters.count {
                self.showChapter(index: self.currentChapter + 1, localRatio: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    guard self.isReadingAloud else { return }
                    self.startSpeech()
                }
            } else {
                self.stopSpeech()
            }
        }
        speech.speak(text, rate: settings.speechRate)
    }

    private func stopSpeech() {
        isReadingAloud = false
        speech.stop()
        speakItem?.title = "朗读"
    }

    private func revealIfNeeded(_ range: NSRange) {
        guard textView.attributedText.length > 0 else { return }
        guard range.location + range.length <= textView.attributedText.length else { return }
        let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range,
                                                           actualCharacterRange: nil)
        let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                       in: textView.textContainer)
        let top = rect.origin.y + textView.textContainerInset.top - textView.contentOffset.y
        if top < 0 || top > textView.bounds.height - 90 {
            textView.scrollRangeToVisible(range)
        }
    }

    // MARK: - Auto scroll

    private func toggleAutoScroll() {
        if autoScrolling {
            stopAutoScroll()
        } else {
            startAutoScroll()
        }
    }

    private func startAutoScroll() {
        stopAutoScroll()
        autoScrolling = true
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let maxOffset = self.scrollMax()
            if self.scrollPosition() >= maxOffset - 1 {
                if self.currentChapter + 1 < self.chapters.count {
                    self.showChapter(index: self.currentChapter + 1, localRatio: 0)
                } else {
                    self.stopAutoScroll()
                }
                return
            }
            let step = self.settings.autoScrollSpeed * 0.05
            self.scrollTo(offset: self.scrollPosition() + step, animated: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        autoScrollTimer = timer
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrolling = false
    }

    private func presentSheet(_ alert: UIAlertController) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = chrome
            popover.sourceRect = CGRect(x: chrome.bounds.midX, y: chrome.bounds.midY,
                                         width: 1, height: 1)
        }
        present(alert, animated: true, completion: nil)
    }

    // MARK: - Actions

    @objc private func handleTap(_ gesture: UITapGestureRecognizer?) {
        if horizontalMode {
            let location = gesture?.location(in: textView) ?? .zero
            let width = max(1, textView.bounds.width)
            if location.x < width * 0.30 {
                pageBack()
                return
            }
            if location.x > width * 0.70 {
                pageForward()
                return
            }
        }
        chromeVisible = !chromeVisible
        chrome.isHidden = !chromeVisible
        navigationController?.setNavigationBarHidden(!chromeVisible, animated: true)
        setNeedsStatusBarAppearanceUpdate()
    }

    @objc private func showTOC() {
        guard !chapters.isEmpty else { return }
        var items: [ChoiceItem] = []
        for (index, chapter) in chapters.enumerated() {
            items.append(ChoiceItem(title: chapter.title,
                                    subtitle: nil,
                                    checked: index == currentChapter))
        }
        let controller = ChoiceListViewController(title: "目录", items: items)
        controller.onSelect = { [weak self] index in
            guard let self = self else { return }
            self.stopSpeech()
            self.showChapter(index: index, localRatio: 0)
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
                                    subtitle: formatter.string(from: bookmark.date),
                                    checked: false))
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
        alert.addAction(UIAlertAction(title: "范围：\(searchScope.title)", style: .default, handler: { [weak self] _ in
            self?.chooseSearchScope()
        }))
        alert.addAction(UIAlertAction(title: "搜索", style: .default, handler: { [weak self, weak alert] _ in
            let keyword = alert?.textFields?.first?.text ?? ""
            self?.runSearch(keyword)
        }))
        present(alert, animated: true, completion: nil)
    }

    /// 原版「只搜索未读的（向前搜索）/ 只搜索已读的（向后搜索）」。
    private func chooseSearchScope() {
        let sheet = UIAlertController(title: "搜索范围", message: nil, preferredStyle: .actionSheet)
        for scope in [SearchScope.all, SearchScope.unread, SearchScope.read] {
            sheet.addAction(UIAlertAction(title: scope.title, style: .default, handler: { [weak self] _ in
                self?.searchScope = scope
                self?.promptSearch()
            }))
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        presentSheet(sheet)
    }

    private func runSearch(_ keyword: String) {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, fullText.length > 0 else { return }

        let currentOffset = currentTextOffset()
        let (start, end) = searchBounds(currentOffset: currentOffset)
        guard end > start else {
            presentNoResult(query)
            return
        }

        var items: [ChoiceItem] = []
        var offsets: [Int] = []
        var searchRange = NSRange(location: start, length: end - start)
        var count = 0

        while count < 200 {
            let found = fullText.range(of: query, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound { break }
            let chapterIndex = ChapterParser.index(of: found.location, in: chapters)
            let chapterTitle = chapters.isEmpty ? "" : chapters[chapterIndex].title
            items.append(ChoiceItem(title: makeSnippet(around: found),
                                    subtitle: chapterTitle,
                                    checked: false))
            offsets.append(found.location)
            count += 1
            let next = found.location + max(1, found.length)
            if next >= fullText.length { break }
            searchRange = NSRange(location: next, length: fullText.length - next)
        }

        guard !items.isEmpty else {
            let alert = UIAlertController(title: "没有找到「\(query)」",
                                          message: nil,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
            return
        }

        lastSearchOffsets = offsets
        lastSearchIndex = -1
        let controller = ChoiceListViewController(title: "\(items.count) 个结果", items: items)
        controller.onSelect = { [weak self] index in
            guard let self = self, index < offsets.count else { return }
            self.stopSpeech()
            self.lastSearchIndex = index
            let ratio = Double(offsets[index]) / Double(max(1, self.fullText.length))
            self.apply(ratio: ratio)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.offerSearchStep()
            }
        }
        present(UINavigationController(rootViewController: controller), animated: true, completion: nil)
    }

    private func presentNoResult(_ query: String) {
        let alert = UIAlertController(title: "没有找到「\(query)」",
                                      message: nil,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    /// 上一次搜索的命中列表，用于「上一个 / 下一个」。
    private func offerSearchStep() {
        guard !lastSearchOffsets.isEmpty else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "上一个", style: .default, handler: { [weak self] _ in
            self?.searchStep(-1)
        }))
        sheet.addAction(UIAlertAction(title: "下一个", style: .default, handler: { [weak self] _ in
            self?.searchStep(1)
        }))
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        presentSheet(sheet)
    }

    private func searchStep(_ delta: Int) {
        guard !lastSearchOffsets.isEmpty else { return }
        guard lastSearchIndex >= 0, lastSearchIndex < lastSearchOffsets.count else { return }
        let target = lastSearchIndex + delta
        guard target >= 0, target < lastSearchOffsets.count else {
            offerSearchStep()
            return
        }
        lastSearchIndex = target
        stopSpeech()
        apply(ratio: Double(lastSearchOffsets[target]) / Double(max(1, fullText.length)))
        offerSearchStep()
    }

    /// Offset of the reading position inside `fullText`.
    private func currentTextOffset() -> Int {
        guard !chapters.isEmpty else { return 0 }
        let chapter = chapters[currentChapter]
        return chapter.range.location + Int(Double(chapter.range.length) * localRatio())
    }

    private func searchBounds(currentOffset: Int) -> (Int, Int) {
        switch searchScope {
        case .all:
            return (0, fullText.length)
        case .unread:
            return (currentOffset, fullText.length)
        case .read:
            return (0, currentOffset)
        }
    }

    private func makeSnippet(around range: NSRange) -> String {
        let padding = 18
        let start = max(0, range.location - padding)
        let end = min(fullText.length, range.location + range.length + padding)
        var snippet = fullText.substring(with: NSRange(location: start, length: end - start))
        snippet = snippet.replacingOccurrences(of: "\n", with: " ")
        snippet = snippet.replacingOccurrences(of: "\r", with: " ")
        snippet = snippet.replacingOccurrences(of: "\t", with: " ")
        return snippet
    }

    @objc private func showMore() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "阅读设置", style: .default, handler: { [weak self] _ in
            self?.showSettings()
        }))
        alert.addAction(UIAlertAction(title: autoScrolling ? "停止自动滚屏" : "自动滚屏",
                                      style: .default,
                                      handler: { [weak self] _ in
            self?.toggleAutoScroll()
        }))
        alert.addAction(UIAlertAction(title: "添加书签", style: .default, handler: { [weak self] _ in
            self?.addBookmark()
        }))
        alert.addAction(UIAlertAction(title: "高亮列表", style: .default, handler: { [weak self] _ in
            self?.showHighlights()
        }))
        alert.addAction(UIAlertAction(title: "清空本书书签", style: .destructive, handler: { [weak self] _ in
            self?.confirmClearBookmarks()
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
        stopAutoScroll()
        let controller = SettingsViewController(style: .grouped)
        controller.onChange = { [weak self] in
            guard let self = self else { return }
            self.applyTheme()
            let ratio = self.localRatio()
            self.reloadChapter(localRatio: ratio)
            UIApplication.shared.isIdleTimerDisabled = self.settings.keepScreenAwake
        }
        let nav = UINavigationController(rootViewController: controller)
        present(nav, animated: true, completion: nil)
    }

    private func addBookmark() {
        guard !chapters.isEmpty else { return }
        let ratio = currentRatio()
        let chapterTitle = chapters[currentChapter].title
        let suggested = "\(chapterTitle) · \(Int(ratio * 100))%"

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

    private func confirmClearBookmarks() {
        guard !BookmarkStore.shared.bookmarks(for: book.fileName).isEmpty else { return }
        let alert = UIAlertController(title: "删除本书所有书签？",
                                      message: "书签列表会清空，高亮不会受影响。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive, handler: { [weak self] _ in
            guard let self = self else { return }
            BookmarkStore.shared.removeAll(for: self.book.fileName)
        }))
        present(alert, animated: true, completion: nil)
    }

    @objc private func saveProgress() {
        guard !chapters.isEmpty else { return }
        let ratio = currentRatio()
        let previous = ProgressStore.shared.ratio(for: book.fileName)
        let total = Double(max(1, fullText.length))
        if ratio > previous {
            ReadingStats.shared.addCharacters(total * (ratio - previous))
        }
        ProgressStore.shared.save(ratio: ratio, for: book.fileName)
    }

    /// 原版「章节剩余时间: %d分钟」：按平均阅读速度估算。
    private func progressText(_ ratio: Double) -> String {
        var text = "\(Int(ratio * 100))%"
        let speed = ReadingStats.shared.readingSpeed
        guard speed > 20 else { return text }
        let remaining = Double(max(1, fullText.length)) * max(0, 1 - ratio)
        let minutes = Int((remaining / speed).rounded())
        text += minutes > 0 ? " · 剩 \(minutes) 分钟" : " · 已读完"
        return text
    }
}

// MARK: - Scroll updates

extension TextReaderViewController: UITextViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !chapters.isEmpty else { return }
        let ratio = currentRatio()
        chrome.setProgress(ratio, text: progressText(ratio))
    }
}

// MARK: - Tap while scrolling

extension TextReaderViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
