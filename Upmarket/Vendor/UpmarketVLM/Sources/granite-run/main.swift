import Foundation
import UpmarketVLM

// Dev harness: run a native VLM on a page image from LOCAL downloaded weights (no network),
// or — with --id — from a Hugging Face repo id (auto-downloaded/cached; dev/eval only).
//
//   granite-run <image> [modelDir]                  # Granite-Docling from a flat dir
//   granite-run --lfm2 <image> [modelDir]           # LFM2.5-VL from a flat dir
//   granite-run --lfm2 --id <hfRepoId> <image>      # LFM2.5-VL from a Hugging Face id
//   granite-run --md <doctags-file>                 # DocTags→Markdown only (parser iteration)
let args = CommandLine.arguments

// Fast parser-iteration mode (Granite DocTags only).
if args.count >= 3, args[1] == "--md" {
    let raw = (try? String(contentsOfFile: args[2], encoding: .utf8)) ?? ""
    print(DocTags.toMarkdown(raw))
    exit(0)
}

// Strip flags from anywhere in the argument list; the rest are positional (image, modelDir).
var useLFM2 = false
var rawDocTags = false
var hfID: String?
var positional: [String] = []
var rest = Array(args.dropFirst())
var i = 0
while i < rest.count {
    switch rest[i] {
    case "--lfm2": useLFM2 = true
    case "--raw-doctags": rawDocTags = true
    case "--id":   i += 1; if i < rest.count { hfID = rest[i] }
    default:       positional.append(rest[i])
    }
    i += 1
}

guard let imagePath = positional.first else {
    FileHandle.standardError.write("usage: granite-run [--lfm2] [--raw-doctags] [--id <hfRepoId>] <image> [modelDir]\n".data(using: .utf8)!)
    exit(2)
}
let url = URL(fileURLWithPath: imagePath)
let modelDir = positional.count >= 2 ? positional[1]
    : "/Users/am/GitHub/upmarket-idl-eval/resources/models/granite_docling"

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let md: String
        if useLFM2 {
            let source: LFM2VLEngine.Source = hfID.map { .huggingFaceID($0) }
                ?? .modelDirectory(URL(fileURLWithPath: modelDir))
            FileHandle.standardError.write("LFM2.5-VL: loading \(hfID ?? modelDir), running on \(url.lastPathComponent)…\n".data(using: .utf8)!)
            md = try await LFM2VLEngine(source: source).convertToMarkdown(imageURL: url)
            print("===== LFM2.5-VL OUTPUT =====")
        } else {
            FileHandle.standardError.write("Granite-Docling: loading \(modelDir), running on \(url.lastPathComponent)…\n".data(using: .utf8)!)
            let engine = GraniteDoclingEngine(
                source: .modelDirectory(URL(fileURLWithPath: modelDir)))
            if rawDocTags {
                md = try await engine.convertToDocTags(imageURL: url)
                print("===== GRANITE-DOCLING DOCTAGS =====")
            } else {
                md = try await engine.convertToMarkdown(imageURL: url)
                print("===== GRANITE-DOCLING OUTPUT =====")
            }
        }
        print(md)
    } catch {
        FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    }
    sem.signal()
}
sem.wait()
