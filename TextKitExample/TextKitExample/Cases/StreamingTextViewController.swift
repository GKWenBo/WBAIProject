//
//  StreamingTextViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 9 / 10 共用的演示页：定时器每隔一小段时间吐出一块文本，交给渲染器更新，
/// 并实时显示这次更新让排版引擎重做了多少工作。
///
/// 子类只需要提供元数据和一个 `IncrementalTextRenderer`。两种模式可以切换对比：
/// - 增量追加：只把新的一块追加到末尾。
/// - 全量替换：每次都用"到目前为止的全部内容"整体替换 —— 相当于 `textView.text = 全文`。
class StreamingTextViewController: CaseViewController {

    /// 子类重写：提供具体的渲染器。
    func makeRenderer() -> IncrementalTextRenderer {
        fatalError("子类必须重写 makeRenderer()")
    }

    /// 子类重写：流式吐出的原文。
    var sampleText: String { SampleText.streamingAnswer }

    /// 子类重写：两个模式的标题，第一个是增量写法，第二个是全量对照组。
    var modeTitles: [String] { ["增量追加", "全量替换"] }

    /// 子类重写：处理一块新文本。`replacingAll` 为 true 时走全量对照组，`emitted` 是到目前为止的全部原文。
    func applyUpdate(chunk: String, emitted: String, replacingAll: Bool) -> IncrementalUpdateReport {
        if replacingAll {
            return renderer.replaceAll(with: NSAttributedString(string: emitted, attributes: TextStyle.body))
        }
        return renderer.append(NSAttributedString(string: chunk, attributes: TextStyle.body))
    }

    /// 子类重写：重置流时清空内容（子类如果在渲染器之外还有状态，需要一并清掉）。
    func resetContent() {
        renderer.reset()
    }

    private enum Mode: Int {
        case append, replace
    }

    /// 每块的间隔。50ms 接近真实大模型流式输出的节奏。
    private static let tickInterval: TimeInterval = 0.05

    private(set) lazy var renderer = makeRenderer()
    private lazy var source = StreamingTextSource(text: sampleText)
    private var timer: Timer?
    private var mode = Mode.append

    private var textView: UITextView!
    private lazy var modeControl = UISegmentedControl(items: modeTitles)
    private let playButton = UIButton(configuration: .borderedProminent())
    private let resetButton = UIButton(configuration: .bordered())
    private let statsLabel = UILabel()

    // 累计统计：增量模式下约等于文本长度的常数倍，全量模式下随长度平方增长。
    private var chunkCount = 0
    private var totalRelaidCharacters = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        textView = renderer.makeTextView()
        textView.isEditable = false
        textView.font = TextStyle.bodyFont
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 10
        textView.layer.cornerCurve = .continuous

        modeControl.selectedSegmentIndex = Mode.append.rawValue
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        playButton.addTarget(self, action: #selector(togglePlaying), for: .touchUpInside)
        resetButton.configuration?.title = "重置"
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        statsLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        statsLabel.textColor = .secondaryLabel
        statsLabel.numberOfLines = 0

        let controls = UIStackView(arrangedSubviews: [modeControl, playButton, resetButton])
        controls.spacing = 8
        modeControl.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [controls, statsLabel, textView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        resetStream()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Timer 会强引用 target，离开页面必须停掉，否则控制器永远释放不了。
        stopTimer()
    }

    // MARK: - 定时器

    @objc private func togglePlaying() {
        if timer != nil {
            stopTimer()
        } else {
            if source.isFinished { resetStream() }
            startTimer()
        }
        updatePlayButton()
    }

    private func startTimer() {
        let timer = Timer(timeInterval: Self.tickInterval,
                          target: self,
                          selector: #selector(tick),
                          userInfo: nil,
                          repeats: true)
        // .common：滚动时（tracking 模式）也继续吐字，和真实流式输出一致。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func tick() {
        guard let chunk = source.next() else {
            stopTimer()
            updatePlayButton()
            return
        }

        let report = applyUpdate(chunk: chunk,
                                 emitted: String(source.emitted),
                                 replacingAll: mode == .replace)

        chunkCount += 1
        totalRelaidCharacters += report.relaidCharacters
        updateStats(with: report)
        scrollToBottom()

        if source.isFinished {
            stopTimer()
            updatePlayButton()
        }
    }

    // MARK: - 交互

    @objc private func modeChanged() {
        mode = Mode(rawValue: modeControl.selectedSegmentIndex) ?? .append
        // 换模式就从头来，累计数字才有可比性。
        let wasPlaying = timer != nil
        stopTimer()
        resetStream()
        if wasPlaying { startTimer() }
        updatePlayButton()
    }

    @objc private func resetTapped() {
        stopTimer()
        resetStream()
    }

    private func resetStream() {
        source.reset()
        resetContent()
        chunkCount = 0
        totalRelaidCharacters = 0
        statsLabel.text = "点「开始」，定时器每 \(Int(Self.tickInterval * 1000))ms 吐出一小块文本\n \n "
        updatePlayButton()
    }

    private func updatePlayButton() {
        let title: String
        if timer != nil {
            title = "暂停"
        } else if source.isFinished {
            title = "重播"
        } else {
            title = chunkCount == 0 ? "开始" : "继续"
        }
        playButton.configuration?.title = title
    }

    // MARK: - 展示

    private func updateStats(with report: IncrementalUpdateReport) {
        let fullLength = (source.text as NSString).length
        let ratio = Double(totalRelaidCharacters) / Double(max(report.totalLength, 1))
        statsLabel.text = String(
            format: "进度 %d / %d 字符 · 第 %d 块\n本次重排 %d 字符 · %d %@ · %.2fms\n累计重排 %d 字符，是当前文本长度的 %.1f 倍",
            report.totalLength, fullLength, chunkCount,
            report.relaidCharacters, report.relaidUnits, report.unitName, report.duration * 1000,
            totalRelaidCharacters, ratio)
    }

    private func scrollToBottom() {
        // 渲染器里已经把版排完，这里让视图同步一下内容尺寸再滚，拿到的才是新高度。
        textView.layoutIfNeeded()
        let maxOffset = textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom
        guard maxOffset > -textView.adjustedContentInset.top else { return }
        textView.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
    }
}
