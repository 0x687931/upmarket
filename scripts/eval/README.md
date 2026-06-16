# Table eval (TEDS)

Standalone harness that scores engine HTML table output against ground truth using
**TEDS** (Tree-Edit-Distance Similarity, Zhong et al. / PubTabNet) — structural and total.
Lives outside the app target so it runs with plain SwiftPM, no Xcode host.

```sh
cd scripts/eval
swift test                                              # TEDS kernel unit tests
swift run table-eval                                    # default corpus: tests/corpus/tables/fintabnet
swift run table-eval /path/to/corpus                    # or point at any corpus dir
```

The corpus holds, per table image, a ground truth `<id>.gt.html` next to one
`<id>.<engine>.html` per engine. Engines are discovered from filenames, so dropping a new
engine's outputs into the corpus needs no code change. Output is mean structural / total
TEDS (×100) per engine, best first.

`TableEvalKit` is the reusable kernel: `TableTreeNode.parse(html:)` →
`TEDS.score(predictedHTML:groundTruthHTML:structural:)`.
