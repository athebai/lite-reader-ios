import UIKit
import WebKit

/// Shared 高亮 plumbing for the WKWebView readers (EPUB / HTML).
/// WKWebView already does the selection work; we only read the selected text.
final class WebHighlightSupport {

    private let webView: WKWebView
    private let bookName: String
    private let bookTitle: String
    private let ratioProvider: () -> Double
    private let jump: (Double) -> Void
    private let presenter: (UIViewController) -> Void
    private let closer: () -> Void

    init(webView: WKWebView,
         bookName: String,
         bookTitle: String,
         ratioProvider: @escaping () -> Double,
         jump: @escaping (Double) -> Void,
         presenter: @escaping (UIViewController) -> Void,
         closer: @escaping () -> Void) {
        self.webView = webView
        self.bookName = bookName
        self.bookTitle = bookTitle
        self.ratioProvider = ratioProvider
        self.jump = jump
        self.presenter = presenter
        self.closer = closer
    }

    /// 有选中文字时高亮它，否则打开本书的高亮列表。
    func handleSelection() {
        webView.evaluateJavaScript("window.getSelection() ? window.getSelection().toString() : ''") { [weak self] value, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let text = ((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    self.showList()
                } else {
                    self.askColor(for: text)
                }
            }
        }
    }

    private func askColor(for text: String) {
        let sheet = UIAlertController(title: "高亮颜色",
                                      message: "已选中 \(text.count) 字",
                                      preferredStyle: .actionSheet)
        for (index, name) in HighlightColor.names.enumerated() {
            let label = name
            sheet.addAction(UIAlertAction(title: label, style: .default, handler: { [weak self] _ in
                guard let self = self else { return }
                HighlightsStore.shared.add(text: text, color: index,
                                           ratio: self.ratioProvider(), for: self.bookName)
            }))
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        presenter(sheet)
    }

    /// 直接打开本书的高亮列表。
    func showList() {
        let controller = HighlightsViewController(bookName: bookName, bookTitle: bookTitle)
        controller.onJump = { [weak self] ratio in
            self?.jump(ratio)
        }
        let navigation = UINavigationController(rootViewController: controller)
        let closeButton = UIBarButtonItem(title: "关闭", style: .plain, target: self,
                                          action: #selector(closeList))
        navigation.navigationItem.leftBarButtonItem = closeButton
        presenter(navigation)
    }

    @objc private func closeList() {
        closer()
    }
}