import Foundation
import TableEvalKit

// Scores every engine's HTML table output against ground truth across a corpus directory,
// reporting mean structural + total TEDS per engine.
//
//   swift run table-eval [corpus-dir]
//
// The corpus holds, per table image, a ground-truth file `<id>.gt.html` alongside one
// `<id>.<engine>.html` per engine (granite, docling, vision, visionband, slanext, …).
// Engines are discovered from the filenames, so adding a new engine's outputs needs no code.

func corpusDirectory() -> URL {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1])
    }
    if let env = ProcessInfo.processInfo.environment["UPMARKET_TABLE_CORPUS"], !env.isEmpty {
        return URL(fileURLWithPath: env)
    }
    // Default: <repo>/tests/corpus/tables/fintabnet, derived from this file's location
    // (.../scripts/eval/Sources/table-eval/main.swift → up 4 → repo root).
    return URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("tests/corpus/tables/fintabnet")
}

let corpus = corpusDirectory()
let fm = FileManager.default
guard let entries = try? fm.contentsOfDirectory(atPath: corpus.path), !entries.isEmpty else {
    FileHandle.standardError.write(Data("error: no corpus at \(corpus.path)\n".utf8))
    exit(2)
}

// id → set of engine suffixes; plus the ground-truth ids.
let htmlFiles = entries.filter { $0.hasSuffix(".html") }
let gtIDs = htmlFiles
    .filter { $0.hasSuffix(".gt.html") }
    .map { String($0.dropLast(".gt.html".count)) }
    .sorted()

// Discover engine names: <id>.<engine>.html where engine != gt.
var engines = Set<String>()
for file in htmlFiles {
    let parts = file.dropLast(".html".count).split(separator: ".")
    if parts.count >= 2, parts.last! != "gt" {
        engines.insert(String(parts.last!))
    }
}

// ponytail: exact Zhang–Shasha is ~O(n²·…) per pair, so a pathological huge table can
// dominate the whole run. Skip any pair above this node count (counted, not silently dropped);
// swap in APTED if these tables ever need real scores.
let maxNodes = ProcessInfo.processInfo.environment["UPMARKET_TEDS_MAX_NODES"].flatMap { Int($0) } ?? 4000

struct Acc { var structural = [Double](); var total = [Double](); var missing = 0; var skipped = 0 }
var perEngine = [String: Acc]()

for id in gtIDs {
    guard let gtHTML = try? String(contentsOf: corpus.appendingPathComponent("\(id).gt.html"), encoding: .utf8) else { continue }
    let gtTree = TableTreeNode.parse(html: gtHTML)
    for engine in engines {
        let url = corpus.appendingPathComponent("\(id).\(engine).html")
        var acc = perEngine[engine] ?? Acc()
        guard let predHTML = try? String(contentsOf: url, encoding: .utf8) else {
            acc.missing += 1
            perEngine[engine] = acc
            continue
        }
        let predTree = TableTreeNode.parse(html: predHTML)
        if max(gtTree?.nodeCount ?? 0, predTree?.nodeCount ?? 0) > maxNodes {
            acc.skipped += 1
            perEngine[engine] = acc
            continue
        }
        acc.structural.append(TEDS.score(predTree, gtTree, structural: true))
        acc.total.append(TEDS.score(predTree, gtTree, structural: false))
        perEngine[engine] = acc
    }
}

func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
func col(_ s: String, _ w: Int) -> String { s.count >= w ? s : String(repeating: " ", count: w - s.count) + s }

print("\nTable TEDS — \(gtIDs.count) ground-truth tables in \(corpus.lastPathComponent)\n")
print(pad("engine", 12) + col("n", 5) + col("structural", 12) + col("total", 12) + col("missing", 8) + col("skipped", 8))
print(String(repeating: "-", count: 57))
// Sort by total TEDS descending — best engine first.
for engine in perEngine.keys.sorted(by: { mean(perEngine[$0]!.total) > mean(perEngine[$1]!.total) }) {
    let a = perEngine[engine]!
    print(pad(engine, 12)
        + col("\(a.structural.count)", 5)
        + col(String(format: "%.1f", mean(a.structural) * 100), 12)
        + col(String(format: "%.1f", mean(a.total) * 100), 12)
        + col("\(a.missing)", 8)
        + col("\(a.skipped)", 8))
}
print("")
