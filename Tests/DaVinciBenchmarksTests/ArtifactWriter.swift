import Foundation
import XCTest

/// Writes benchmark JSON artifacts and REPORT.md. Uses test's temporary directory; can copy to repo Benchmarks/ if writable.
public enum ArtifactWriter {

    /// Directory for this run (e.g. .../Benchmarks/Artifacts/2025-02-25_1200 or temp).
    public static func artifactDirectory() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let name = formatter.string(from: Date())
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaVinciBenchmarks", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }

    public static func writeJSON(_ result: BenchmarkResult, to baseURL: URL) {
        let dir = baseURL.appendingPathComponent(result.engine, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(result) else { return }
        let file = dir.appendingPathComponent("\(result.scenario).json")
        try? data.write(to: file)
    }

    public static func writeReport(results: [BenchmarkResult], to baseURL: URL) {
        var md = "# DaVinci Benchmark Proof Report\n\n"
        md += "Generated: \(ISO8601DateFormatter().string(from: Date()))\n\n"
        let byScenario = Dictionary(grouping: results, by: { $0.scenario })
        for (scenario, list) in byScenario.sorted(by: { $0.key < $1.key }) {
            md += "## \(scenario)\n\n"
            md += "| Engine | Duration (s) | CPU (s) | Peak Mem (MB) | Network starts |\n"
            md += "|--------|--------------|---------|---------------|----------------|\n"
            for r in list.sorted(by: { $0.engine < $1.engine }) {
                let mem = r.peakMemoryBytes.map { String(format: "%.1f", Double($0) / 1_048_576) } ?? "—"
                let cpu = r.cpuSeconds.map { String(format: "%.2f", $0) } ?? "—"
                md += "| \(r.engine) | \(String(format: "%.2f", r.durationSeconds)) | \(cpu) | \(mem) | \(r.networkStartCount) |\n"
            }
            md += "\n"
        }
        let data = Data(md.utf8)
        let file = baseURL.appendingPathComponent("REPORT.md")
        try? data.write(to: file)
    }

    /// If repo Benchmarks/Artifacts is writable, copy run dir there and return URL; else return temp dir.
    public static func reportDirectory(repoRoot: URL?) -> URL {
        let runDir = artifactDirectory()
        guard let root = repoRoot else { return runDir }
        let bench = root.appendingPathComponent("Benchmarks", isDirectory: true)
            .appendingPathComponent("Artifacts", isDirectory: true)
        let name = runDir.lastPathComponent
        let dest = bench.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: bench, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: runDir, to: dest)
        return dest
    }
}
