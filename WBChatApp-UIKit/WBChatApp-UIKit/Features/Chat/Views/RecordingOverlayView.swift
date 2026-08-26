import UIKit

/// 录音浮层：波形 + 实时文字 + 取消/完成。
final class RecordingOverlayView: UIView {

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    private let waveform = WaveformView()
    private let textLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 3
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = Theme.textPrimary
        label.text = "正在聆听…"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("取消", for: .normal)
        button.accessibilityIdentifier = "recording.cancel"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let confirmButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("完成", for: .normal)
        button.accessibilityIdentifier = "recording.confirm"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background
        waveform.translatesAutoresizingMaskIntoConstraints = false

        addSubview(waveform)
        addSubview(textLabel)
        addSubview(cancelButton)
        addSubview(confirmButton)

        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            waveform.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 16),
            waveform.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            waveform.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            waveform.heightAnchor.constraint(equalToConstant: 44),

            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            cancelButton.topAnchor.constraint(equalTo: waveform.bottomAnchor, constant: 16),
            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

            confirmButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            confirmButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
        ])

        cancelButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)
        confirmButton.addTarget(self, action: #selector(handleConfirm), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func update(level: Float) {
        waveform.update(level: level)
    }

    func setText(_ text: String) {
        textLabel.text = text.isEmpty ? "正在聆听…" : text
    }

    @objc private func handleCancel() { onCancel?() }
    @objc private func handleConfirm() { onConfirm?() }
}
