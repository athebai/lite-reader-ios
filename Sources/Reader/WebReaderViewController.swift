import UIKit
import WebKit

final class WebReaderViewController: UIViewController {

    private let book: Book
    private let webView: WKWebView
    private let chrome = ReaderChromeView()
    private let settings = ReaderSettings.shared
    private let speech = SpeechController()

    private var chromeVisible = true
    private var speakItem: UIBarButtonItem?
    private var isReadingAloud = false
    private var highlighter: WebHighlightSupport?

    init(book: Book) {
        self.book = book
        self.webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
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
        applyTheme()
        loadDocument()
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

    override var prefersStatusBarHidden: Bool {
        return !chromeVisible
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return settings.theme.isDark ? .lightContent : .default
    }

    private func setupWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 96, right: 0)
        webView.scrollView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 96, right: 0)
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        webView.addGestureRecognizer(tap)
    }

    private func setupChrome() {
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.setShowsSlider(false)
        view.addSubview(chrome)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chrome.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let speakButton = UIBarButtonItem(title: "朗读", style: .plain,
                                          target: self, action: #selector(toggleSpeech))
        let settingsItem = UIBarButtonItem(title: "设置", style: .plain,
                                           target: self, action: #selector(showSettings))
        speakItem = speakButton
        let flex = { () -> UIBarButtonItem in
            return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        }
        let highlightItem = UIBarButtonItem(title: "高亮", style: .plain,
                                             target: self, action: #selector(highlightTap))
        chrome.setItems([flex(), highlightItem, flex(), speakButton, flex(), settingsItem, flex()])
        chrome.apply(theme: settings.theme)
    }

    private func currentRatio() -> Double {
        let scroll = webView.scrollView
        let maxY = scroll.contentSize.height - scroll.bounds.height
        guard maxY > 1 else { return 0 }
        return Double(max(0, min(1, scroll.contentOffset.y / maxY)))
    }

    private func setupHighlighter() {
        highlighter = WebHighlightSupport(
            webView: webView,
            bookName: book.fileName,
            bookTitle: book.title,
            ratioProvider: { [weak self] in self?.currentRatio() ?? 0 },
            jump: { [weak self] ratio in
                guard let self = self else { return }
                let script = "(function(){var d=document.documentElement;var m=d.scrollHeight-window.innerHeight;if(m>0){window.scrollTo(0,m*\(ratio));}})();"
                self.webView.evaluateJavaScript(script, completionHandler: nil)
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

    private func loadDocument() {
        webView.loadFileURL(book.url, allowingReadAccessTo: book.url.deletingLastPathComponent())
    }

    private func applyStyle() {
        let theme = settings.theme
        let background = theme.background.cssHex
        let foreground = theme.text.cssHex
        let accent = theme.accent.cssHex
        let size = Int(settings.fontSize)
        let script = """
        (function(){
          var id = 'lite-reader-style';
          var old = document.getElementById(id);
          if (old && old.parentNode) { old.parentNode.removeChild(old); }
          var style = document.createElement('style');
          style.id = id;
          style.innerHTML = 'html,body{background:\(background) !important;color:\(foreground) !important;}body{font-size:\(size)px !important;line-height:1.75 !important;}p,div,span,li,td,h1,h2,h3,h4{color:\(foreground) !important;}a{color:\(accent) !important;}img{max-width:100% !important;height:auto !important;}';
          if (document.head) { document.head.appendChild(style); }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    @objc private func saveProgress() {
        let scroll = webView.scrollView
        let maxY = scroll.contentSize.height - scroll.bounds.height
        guard maxY > 1 else { return }
        let ratio = Double(max(0, min(1, scroll.contentOffset.y / maxY)))
        ProgressStore.shared.save(ratio: ratio, for: book.fileName)
    }

    @objc private func handleTap() {
        chromeVisible = !chromeVisible
        chrome.isHidden = !chromeVisible
        navigationController?.setNavigationBarHidden(!chromeVisible, animated: true)
        setNeedsStatusBarAppearanceUpdate()
    }

    @objc private func toggleSpeech() {
        if speech.isSpeaking || speech.isPaused {
            stopSpeech()
            return
        }
        isReadingAloud = true
        speakItem?.title = "停止"
        speech.onRange = nil
        speech.onFinish = { [weak self] in
            self?.stopSpeech()
        }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self = self, self.isReadingAloud else { return }
            let text = (value as? String) ?? ""
            if text.isEmpty {
                self.stopSpeech()
                return
            }
            self.speech.speak(text, rate: self.settings.speechRate)
        }
    }

    private func stopSpeech() {
        isReadingAloud = false
        speech.stop()
        speakItem?.title = "朗读"
    }

    @objc private func showSettings() {
        let controller = SettingsViewController(style: .grouped)
        controller.onChange = { [weak self] in
            guard let self = self else { return }
            self.applyTheme()
            self.applyStyle()
            UIApplication.shared.isIdleTimerDisabled = self.settings.keepScreenAwake
        }
        present(UINavigationController(rootViewController: controller), animated: true, completion: nil)
    }
}

extension WebReaderViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyStyle()
        let saved = ProgressStore.shared.ratio(for: book.fileName)
        if saved > 0.001 {
            let script = "(function(){var d=document.documentElement;var m=d.scrollHeight-window.innerHeight;if(m>0){window.scrollTo(0,m*\(saved));}})();"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

extension WebReaderViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
