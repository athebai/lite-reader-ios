import UIKit

final class ReaderChromeView: UIView {

    let slider = UISlider(frame: .zero)
    let progressLabel = UILabel(frame: .zero)
    let toolbar = UIToolbar(frame: .zero)

    var onSeek: ((Double) -> Void)?

    private let stack = UIStackView()
    private let sliderContainer = UIView(frame: .zero)
    private let sliderRow = UIStackView()
    private var bottomInset: NSLayoutConstraint?
    private var showsSlider = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        clipsToBounds = true

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.isContinuous = true
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderCommitted),
                         for: [.touchUpInside, .touchUpOutside, .touchCancel])

        progressLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        progressLabel.textAlignment = .right
        progressLabel.text = "0%"
        progressLabel.setContentHuggingPriority(.required, for: .horizontal)
        progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        sliderRow.axis = .horizontal
        sliderRow.alignment = .center
        sliderRow.spacing = 12
        sliderRow.translatesAutoresizingMaskIntoConstraints = false
        sliderRow.addArrangedSubview(slider)
        sliderRow.addArrangedSubview(progressLabel)
        progressLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        sliderContainer.addSubview(sliderRow)
        NSLayoutConstraint.activate([
            sliderRow.topAnchor.constraint(equalTo: sliderContainer.topAnchor, constant: 6),
            sliderRow.leadingAnchor.constraint(equalTo: sliderContainer.leadingAnchor, constant: 16),
            sliderRow.trailingAnchor.constraint(equalTo: sliderContainer.trailingAnchor, constant: -16),
            sliderRow.bottomAnchor.constraint(equalTo: sliderContainer.bottomAnchor, constant: -2)
        ])

        toolbar.isTranslucent = false
        toolbar.clipsToBounds = true
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true

        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sliderContainer)
        stack.addArrangedSubview(toolbar)
        addSubview(stack)

        let inset = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0)
        bottomInset = inset

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            inset
        ])
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        bottomInset?.constant = -safeAreaInsets.bottom
    }

    func setItems(_ items: [UIBarButtonItem]) {
        toolbar.items = items
    }

    func setShowsSlider(_ show: Bool) {
        showsSlider = show
        sliderContainer.isHidden = !show
    }

    func setProgress(_ ratio: Double, text: String) {
        let clamped = max(0, min(1, ratio))
        if !slider.isTracking {
            slider.value = Float(clamped)
        }
        progressLabel.text = text
    }

    func apply(theme: ReaderTheme) {
        backgroundColor = theme.barBackground
        toolbar.barTintColor = theme.barBackground
        toolbar.tintColor = theme.accent
        toolbar.setNeedsDisplay()
        slider.minimumTrackTintColor = theme.accent
        slider.maximumTrackTintColor = theme.secondary.withAlphaComponent(0.28)
        progressLabel.textColor = theme.secondary
    }

    @objc private func sliderChanged() {
        let percent = Int(round(slider.value * 100))
        progressLabel.text = "\(percent)%"
    }

    @objc private func sliderCommitted() {
        onSeek?(Double(slider.value))
    }
}
