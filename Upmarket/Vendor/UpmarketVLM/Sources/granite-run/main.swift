import Foundation
import UpmarketVLM

// Run Granite-Docling on a page image from the LOCAL in-repo weights (no network).
let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: granite-run <image> [modelDir]\n".data(using: .utf8)!)
    exit(2)
}
// Fast parser-iteration mode: `granite-run --md <doctags-file>` runs DocTags.toMarkdown only.
if args.count >= 3, args[1] == "--md" {
    let raw = (try? String(contentsOfFile: args[2], encoding: .utf8)) ?? ""
    print(DocTags.toMarkdown(raw))
    exit(0)
}

let url = URL(fileURLWithPath: args[1])
let modelDir = args.count >= 3 ? args[2]
    : "/Users/am/GitHub/upmarket-idl-eval/resources/models/upmarket_ai"

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        FileHandle.standardError.write("loading local weights \(modelDir) and running on \(url.lastPathComponent)…\n".data(using: .utf8)!)
        let engine = GraniteDoclingEngine(source: .modelDirectory(URL(fileURLWithPath: modelDir)))
        let md = try await engine.convertToMarkdown(imageURL: url)
        print("===== GRANITE-DOCLING OUTPUT =====")
        print(md)
    } catch {
        FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    }
    sem.signal()
}
sem.wait()
