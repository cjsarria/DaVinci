#if canImport(UIKit)
import UIKit
import LabCore

final class BenchmarkResultsViewController: UIViewController {
    private let report: BenchmarkReport
    private let textView = UITextView()

    init(report: BenchmarkReport) {
        self.report = report
        super.init(nibName: nil, bundle: nil)
        title = "Results"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        textView.isEditable = false
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Export", style: .plain, target: self, action: #selector(exportJSON))

        render()
    }

    private func render() {
        let last = report.snapshots.last
        let header = "Mode: \(report.mode.rawValue)\nDuration: \(report.durationSeconds)s\nDevice: \(report.deviceModel)\nSystem: \(report.systemVersion)\nSettings: prefetch=\(report.settings.prefetchEnabled) downsample=\(report.settings.downsampleEnabled) fade=\(report.settings.fadeEnabled)\n"

        let tail: String
        if let last {
            let decodeText = last.avgDecodeMs.map { String(format: "%.1f", $0) } ?? "—"
            let hitText: String
            if let hit = last.cacheHitRate {
                let suffix = last.cacheHitRateIsEstimated ? " ~" : ""
                hitText = String(format: "%.0f%%%@", hit * 100, suffix)
            } else {
                hitText = "—"
            }
            let bytesText: String
            if let bytes = last.totalBytes {
                let suffix = last.totalBytesIsEstimated ? " ~" : ""
                bytesText = "\(bytes)\(suffix)"
            } else {
                bytesText = "—"
            }
            tail = "\nFinal:\nSamples: \(last.count)\nAvg load: \(String(format: "%.1f", last.avgLoadMs)) ms\nAvg decode: \(decodeText) ms\nCache hit: \(hitText)\nTotal bytes: \(bytesText)\n"
        } else {
            tail = ""
        }

        textView.text = header + tail
    }

    @objc private func exportJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(report) else { return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("DaVinciLabReport.json")
        try? data.write(to: tmp)

        let vc = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        present(vc, animated: true)
    }
}
#endif
