#if canImport(UIKit)
import UIKit
import LabCore

final class DashboardViewController: UIViewController {
    private let aggregator: MetricsAggregator
    private let stack = UIStackView()

    init(aggregator: MetricsAggregator) {
        self.aggregator = aggregator
        super.init(nibName: nil, bundle: nil)
        title = "Dashboard"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Refresh", style: .plain, target: self, action: #selector(refresh))
        refresh()
    }

    @objc private func refresh() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let engines = aggregator.allEngineNames()
        if engines.isEmpty {
            let label = UILabel()
            label.text = "Run the feed to collect metrics."
            label.textColor = .secondaryLabel
            stack.addArrangedSubview(label)
            return
        }

        for name in engines {
            let snap = aggregator.snapshot(engineName: name)
            stack.addArrangedSubview(makeCard(for: snap))
        }
    }

    private func makeCard(for snap: MetricsAggregator.Snapshot) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.secondarySystemBackground
        card.layer.cornerRadius = 16
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.06
        card.layer.shadowRadius = 14
        card.layer.shadowOffset = CGSize(width: 0, height: 6)

        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .headline)
        title.text = snap.engineName

        let body = UILabel()
        body.numberOfLines = 0
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.textColor = .secondaryLabel

        func format(_ snap: MetricsAggregator.Snapshot) -> String {
            let decodeText = snap.avgDecodeMs.map { String(format: "%.1f ms", $0) } ?? "—"
            let hitText: String
            if let hit = snap.cacheHitRate {
                let suffix = snap.cacheHitRateIsEstimated ? " ~" : ""
                hitText = String(format: "%.0f%%%@", hit * 100, suffix)
            } else {
                hitText = "—"
            }
            let bytesText: String
            if let bytes = snap.totalBytes {
                let suffix = snap.totalBytesIsEstimated ? " ~" : ""
                bytesText = "\(bytes)\(suffix)"
            } else {
                bytesText = "—"
            }
            return "Samples: \(snap.count)\nAvg load: \(String(format: "%.1f ms", snap.avgLoadMs))\nAvg decode: \(decodeText)\nCache hit: \(hitText)\nTotal bytes: \(bytesText)"
        }

        let cold = aggregator.snapshot(engineName: snap.engineName, runMode: .cold)
        let warm = aggregator.snapshot(engineName: snap.engineName, runMode: .warm)
        if cold.count > 0 || warm.count > 0 {
            var text = ""
            if cold.count > 0 { text += "Cold\n" + format(cold) }
            if warm.count > 0 {
                if text.isEmpty == false { text += "\n\n" }
                text += "Warm\n" + format(warm)
            }
            body.text = text
        } else {
            body.text = format(snap)
        }

        let v = UIStackView(arrangedSubviews: [title, body])
        v.axis = .vertical
        v.spacing = 8
        v.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            v.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            v.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            v.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }
}

#endif
