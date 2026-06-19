# Native VLM Validation

Date: 2026-06-20

## Release decision

Both native engines are suitable for release with the output validator and OCR fallback enabled.

- **Fast** (Granite-Docling): release. It is strongest on the dense table page and remains the default.
- **Best for tables** (LFM2.5-VL): release as an opt-in Max-tier model. It is materially better on the email thread and the six-page mixed prose/table report, and all 13 IDL pages completed without runaway output after the processor fix.

Neither engine is universally better. Routing remains user-selectable and failed/pathological output falls back to the existing native OCR path.

## Pinned artifacts

| Component | Revision / format |
| --- | --- |
| Granite weights | `ibm-granite/granite-docling-258M-mlx` at `e9939db25d2f296c8678d0491c4609a8c596c50a`, MLX BF16 |
| LFM weights | `mlx-community/LFM2.5-VL-1.6B-8bit` at `051260290c8361562915be1b0292636a6ac8a7a3`, MLX 8-bit |
| LFM GGUF reference | `LiquidAI/LFM2.5-VL-1.6B-GGUF` at `48c6a306939241d1ddc99b090df552cb47a066c6`, Q8_0 |
| Native runtime | `mlx-swift-lm` at `0767814d29254017f348e4b97b770d974e291d0e` |
| MLX dependency | `mlx-swift` 0.31.4 |
| Granite reference runtime | `mlx-vlm` 0.3.3 |
| LFM reference runtime | `mlx-vlm` 0.3.10 and current Homebrew `llama.cpp` |

The LFM 4-bit MLX checkpoint was rejected: it emitted only padding tokens through the Swift loader. Production and developer downloads use the exact pinned 8-bit revision. A small provenance manifest remains in the repository; generated model files are downloaded on demand and are not stored in Git or Git-LFS.

## Reference recipes

### Granite-Docling

- Prompt: `Convert this page to docling.`
- Temperature: `0.0`
- Maximum generation: 4096 tokens
- Stop as soon as `</doctag>` is complete
- Parse DocTags and export Markdown
- Image path: Idefics3 split-image processing, 512-pixel frames, global thumbnail

Reference: <https://huggingface.co/ibm-granite/granite-docling-258M-mlx>

### LFM2.5-VL

- System: `You are a helpful multimodal assistant by Liquid AI.`
- User prompt: `Convert this document page to Markdown. Preserve headings, lists, and tables.`
- Temperature: `0.1`
- Min-p: `0.15`
- Repetition penalty: `1.05` over 64 recent tokens
- Maximum generation: 4096 tokens
- Vision: 64–256 thumbnail image tokens, 512×512 tiling, 2–10 tiles, thumbnail enabled
- Prompt image sequence: image start token, row/column marker per tile, image tokens, thumbnail marker and tokens, image end token

References:

- <https://docs.liquid.ai/llms.txt>
- <https://docs.liquid.ai/lfm/models/vision-models>
- <https://docs.liquid.ai/lfm/key-concepts/text-generation-and-prompting>
- <https://docs.liquid.ai/lfm/key-concepts/chat-template>
- <https://docs.liquid.ai/deployment/on-device/mlx>

## Defects found and fixed

### Granite

1. Generation inherited the runtime default temperature (`0.6`) instead of the model-card recipe.
2. Generation did not stop at the completed `</doctag>`.
3. Early termination could tear down a still-active Metal command buffer in the command-line harness.
4. The Swift DocTags parser discarded OTSL `<srow>` table cells.

Fixes: explicit deterministic generation, completed-tag stop helper, stream synchronization, and `<srow>` parsing with tests.

The authoritative DocTags sample exported through `docling-core` and the Swift parser reached a 0.9785 word-sequence ratio. Remaining differences were table column padding and HTML escaping, not lost document content.

### LFM2.5-VL

1. The original Swift path used the chat session's default 512×512 resize, distorting document pages.
2. The vendored processor decoded model settings but did not implement the reference processor. It stretched the whole page into a tile grid and omitted the model's variable-resolution thumbnail behavior.
3. The first compatibility processor implemented only the thumbnail patch grid. It omitted 512×512 tiles.
4. The prompt omitted required `<|image_start|>`, per-tile `<|img_row_N_col_N|>`, `<|img_thumbnail|>`, and `<|image_end|>` tokens.
5. Greedy decoding did not match Liquid's documented vision recipe.

Fixes: exact grid selection, six-tile-plus-thumbnail behavior for the representative portrait page, padded patch tensors and spatial shapes, ceiling-based post-unshuffle token counts, full image special-token construction, documented sampling, and the documented multimodal system prompt.

For the 1695×2187 validation page, the reference and Swift inputs now agree on:

- grid: 2 columns × 3 rows
- frames: six 512×512 tiles plus one 448×576 thumbnail
- patch tensors: six `[1024, 768]` frames plus one padded `[1024, 768]` frame
- spatial shapes: six `32×32` frames plus one `36×28` frame
- valid thumbnail patches: 1008
- thumbnail image tokens after 2× downsampling: 252

The Swift image resampler is bicubic because the dependency exposes bicubic/Lanczos but not the reference bilinear mode. Tensor dimensions, ordering, normalization, masks, and token construction match; visual results did not show a systematic integration error from this interpolation difference.

## Corpus results

Command:

```sh
python3 /tmp/idl_compare.py
```

Automated scores use a difflib word ratio against Textract text and are diagnostic only.

| Document | Pages | Granite | LFM2 | Automated winner | Visual decision |
| --- | ---: | ---: | ---: | --- | --- |
| `hqcx0242` email thread | 2 | 0.548 | 0.721 | LFM2 | LFM2; correct thread order and fields, while Granite omitted content |
| `fnpd0075` prose + complex tables | 6 | 0.414 | 0.403 | tie | LFM2; substantially more complete prose and usable tables |
| `kykb0006` long business lists | 2 | 0.920 | 0.831 | Granite | LFM2 slight; cleaner names and fewer OCR substitutions |
| `klpb0135` dense table | 1 | 0.763 | 0.593 | Granite | Granite; materially better row/column values |
| `hlhj0239` letter + lists | 2 | 0.961 | 0.942 | tie | tie; both faithful, LFM2 preserves some omitted list content |
| **Mean** | **13** | **0.721** | **0.698** | Granite | complementary engines |

All 13 corrected LFM pages completed with bounded output. Word counts ranged from 140 to 515 words per page. No page hit the token cap or triggered the repetition/empty/excessive-length validator.

## Safeguards and regression coverage

- Reject empty model output.
- Reject output above 3,500 words or 120,000 UTF-8 bytes per page.
- Reject exact-line repetition at six occurrences.
- Reject repeated 12-word phrases at six occurrences.
- Fall back to native OCR when validation or inference throws.
- Tests cover LFM grid selection, thumbnail dimensions, patch/token counts, image special-token ordering, documented generation settings, Granite stop behavior, OTSL structured rows, and pathological output.

## Validation commands

```sh
cd Upmarket/Vendor/UpmarketVLM
swift test
swift build -c release --product granite-run

cd /Users/am/GitHub/upmarket-lfm2
scripts/dev/set_debug_tier.sh basic
pkill -9 -f 'Upmarket.app/Contents/MacOS/Upmarket'
scripts/ci/gate.sh quick
scripts/dev/set_debug_tier.sh max
```

Results:

- UpmarketVLM: 13 tests, 0 failures
- Canonical quick gate: 383 tests, 16 skipped, 0 failures
- App build: succeeded

## Remaining model limitations

- LFM occasionally reorganizes a table rather than preserving every source column. Granite remains better on `klpb0135`.
- Granite is less robust on long email threads and some degraded multi-page scans.
- Sampling at the documented LFM temperature is not byte-for-byte deterministic. Structural preprocessing and generation configuration are deterministic and regression-tested.
- The Textract corpus text is not a perfect ground truth; release decisions use both automated comparison and direct page inspection.
