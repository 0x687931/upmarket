# Corpus Pathway Benchmark Comparison

This report compares convert-to-Markdown quality by pathway. Shipping decisions use the stored baseline ledger; internal reference pathways are evidence only and do not imply approval to ship those dependencies.

Note: the `python-ai-docling` rows in this historical report predate the Granite Docling MLX wiring and were produced by the enhanced Docling path relabeled as AI. Do not use those rows as Pro AI quality evidence. SmolDocling preview is deprecated. Regenerate this report with `scripts/benchmark.sh --pathway python-ai-docling --bucket scanned-or-unknown` on an Apple Silicon/Metal host after the Upmarket AI model is validated.

## Benchmark Environment

| Pathway | macOS | Machine | CPU | Requested Compute | Repeats |
| --- | --- | --- | --- | --- | --- |
| internal-reference-paddleocr@cpu | 26.5 | arm64 | Apple M4 Pro | cpu | 1 |
| internal-reference-poppler@cpu | 26.5 | arm64 | arm | cpu | 3 |
| internal-reference-pymupdf@cpu | 26.5 | arm64 | arm | cpu | 3 |
| internal-reference-rapidocr@cpu | 26.5 | arm64 | arm | cpu | 1 |
| python-ai-docling | 26.5 | arm64 | Apple M4 Pro | auto | 1 |
| python-enhanced-docling | 26.5 | arm64 | Apple M4 Pro | auto | 1 |
| python-fast-markitdown | 26.5 | arm64 | arm | auto | 3 |
| python-fast-pdfium | 26.5 | arm64 | arm | auto | 3 |
| swift-pdfkit@cpu | 26.5 | arm64 | arm | cpu | 1 |

## Pathway Summary

| Pathway | Status | Compute Capability | Control | Pipeline | Compute | Repeats | Documents | Overall | Avg Sec/Doc | Failed |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| internal-reference-paddleocr@cpu | internal-reference-only blocked/deprecated | cpu, gpu | environment-dependent; developer reference only | paddleocr-reference | cpu | 1 | 75 | 67.5% | 8.242s | 14 |
| internal-reference-poppler@cpu | internal-reference-only | cpu | none | poppler-reference | cpu | 3 | 60 | 81.9% | 0.015s | 1 |
| internal-reference-pymupdf@cpu | internal-reference-only | cpu | none | pymupdf-reference | cpu | 3 | 60 | 79.7% | 0.007s | 1 |
| internal-reference-rapidocr@cpu | internal-reference-only | cpu | none for rapidocr-onnxruntime default package | rapidocr-reference | cpu | 1 | 75 | 78.6% | 1.287s | 1 |
| python-ai-docling | shipping | cpu, gpu-metal-mps | partial; Python model stack may use PyTorch MPS/MLX when available | ai | auto | 1 | 171 | 83.3% | 0.617s | 1 |
| python-enhanced-docling | shipping | cpu, gpu-metal-mps | partial; Python model stack may use PyTorch MPS/MLX when available | enhanced | auto | 1 | 171 | 83.3% | 0.453s | 1 |
| python-fast-markitdown | shipping | cpu | none for current fast non-PDF path | fast | auto | 3 | 111 | 83.8% | 0.035s | 0 |
| python-fast-pdfium | shipping | cpu | none | fast | auto | 3 | 60 | 80.1% | 0.013s | 1 |
| swift-avfoundation-metadata | shipping | cpu, hardware-codec | none | not run | - | - | 0 | - | - | - |
| swift-imageio-metadata | shipping | cpu, hardware-codec | none | not run | - | - | 0 | - | - | - |
| swift-pdfkit@cpu | shipping | cpu | none | swift-pdfkit | cpu | 1 | 60 | 83.2% | 0.009s | 1 |
| swift-speech | shipping | os-managed-cpu-gpu-ane | none; Speech framework chooses available Apple hardware internally | not run | - | - | 0 | - | - | - |
| swift-vision-document | shipping | os-managed-cpu-gpu-ane | none; Vision chooses available Apple hardware internally | not run | - | - | 0 | - | - | - |

## Category Summary

### internal-reference-paddleocr@cpu

| Category | Documents | Overall | Avg Sec/Doc | Failed |
| --- | ---: | ---: | ---: | ---: |
| image | 15 | 48.0% | 8.065s | 5 |
| pdf | 60 | 72.3% | 8.286s | 9 |

### internal-reference-poppler@cpu

| Category | Documents | Overall | Avg Sec/Doc | Failed |
| --- | ---: | ---: | ---: | ---: |
| pdf | 60 | 81.9% | 0.015s | 1 |

### internal-reference-pymupdf@cpu

| Category | Documents | Overall | Avg Sec/Doc | Failed |
| --- | ---: | ---: | ---: | ---: |
| pdf | 60 | 79.7% | 0.007s | 1 |

### internal-reference-rapidocr@cpu

| Category | Documents | Overall | Avg Sec/Doc | Failed |
| --- | ---: | ---: | ---: | ---: |
| image | 15 | 79.5% | 0.444s | 0 |
| pdf | 60 | 78.4% | 1.498s | 1 |

### python-ai-docling

| Category | Documents | Overall | Avg Sec/Doc | Failed |
| --- | ---: | ---: | ---: | ---: |
| asciidoc | 3 | 91.7% | 0.985s | 0 |
| csv | 9 | 86.7% | 0.007s | 0 |
| docx | 25 | 92.8% | 0.208s | 0 |
| html | 30 | 87.2% | 0.201s | 0 |
| image | 15 | 61.3% | 0.140s | 0 |
| pdf | 60 | 82.5% | 1.397s | 1 |
| pptx | 6 | 84.2% | 0.198s | 0 |
| webvtt | 4 | 95.0% | 0.007s | 0 |
| xlsx | 7 | 90.0% | 0.201s | 0 |
| xml | 12 | 72.1% | 0.219s | 0 |

### python-enhanced-docling

| Category | Documents | Overall | Avg Sec/Doc | Failed |
| --- | ---: | ---: | ---: | ---: |
| asciidoc | 3 | 91.7% | 0.766s | 0 |
| csv | 9 | 86.7% | 0.007s | 0 |
| docx | 25 | 92.8% | 0.015s | 0 |
| html | 30 | 87.2% | 0.009s | 0 |
| image | 15 | 61.3% | 0.136s | 0 |
| pdf | 60 | 82.5% | 1.201s | 1 |
| pptx | 6 | 84.2% | 0.006s | 0 |
| webvtt | 4 | 95.0% | 0.008s | 0 |
| xlsx | 7 | 90.0% | 0.010s | 0 |
| xml | 12 | 72.1% | 0.026s | 0 |

### python-fast-markitdown

| Category | Documents | Overall | Avg Sec/Doc | Failed |
| --- | ---: | ---: | ---: | ---: |
| asciidoc | 3 | 90.0% | 0.008s | 0 |
| csv | 9 | 86.7% | 0.007s | 0 |
| docx | 25 | 91.7% | 0.044s | 0 |
| html | 30 | 87.8% | 0.010s | 0 |
| image | 15 | 61.3% | 0.109s | 0 |
| pptx | 6 | 94.2% | 0.010s | 0 |
| webvtt | 4 | 95.0% | 0.008s | 0 |
| xlsx | 7 | 85.7% | 0.049s | 0 |
| xml | 12 | 72.1% | 0.024s | 0 |

### python-fast-pdfium

| Category | Documents | Overall | Avg Sec/Doc | Failed |
| --- | ---: | ---: | ---: | ---: |
| pdf | 60 | 80.1% | 0.013s | 1 |

### swift-pdfkit@cpu

| Category | Documents | Overall | Avg Sec/Doc | Failed |
| --- | ---: | ---: | ---: | ---: |
| pdf | 60 | 83.2% | 0.009s | 1 |

## Document Score Matrix

Cells are `accuracy / average wall time`. `ERR` means the pathway ran and failed for that file. `-` means that converter was not run for that file.

| File | Category | internal-reference-paddleocr@cpu | internal-reference-poppler@cpu | internal-reference-pymupdf@cpu | internal-reference-rapidocr@cpu | python-ai-docling | python-enhanced-docling | python-fast-markitdown | python-fast-pdfium | swift-pdfkit@cpu |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| tests/data/asciidoc/test_01.asciidoc | asciidoc | - | - | - | - | 90.0% / 2.565s | 90.0% / 2.293s | 95.0% / 0.007s | - | - |
| tests/data/asciidoc/test_02.asciidoc | asciidoc | - | - | - | - | 90.0% / 0.196s | 90.0% / 0.003s | 80.0% / 0.008s | - | - |
| tests/data/asciidoc/test_03.asciidoc | asciidoc | - | - | - | - | 95.0% / 0.194s | 95.0% / 0.001s | 95.0% / 0.008s | - | - |
| tests/data/csv/csv-comma-in-cell.csv | csv | - | - | - | - | 90.0% / 0.007s | 90.0% / 0.008s | 90.0% / 0.008s | - | - |
| tests/data/csv/csv-comma.csv | csv | - | - | - | - | 90.0% / 0.007s | 90.0% / 0.007s | 90.0% / 0.008s | - | - |
| tests/data/csv/csv-inconsistent-header.csv | csv | - | - | - | - | 60.0% / 0.007s | 60.0% / 0.006s | 60.0% / 0.007s | - | - |
| tests/data/csv/csv-pipe.csv | csv | - | - | - | - | 90.0% / 0.008s | 90.0% / 0.007s | 90.0% / 0.007s | - | - |
| tests/data/csv/csv-semicolon.csv | csv | - | - | - | - | 90.0% / 0.007s | 90.0% / 0.007s | 90.0% / 0.007s | - | - |
| tests/data/csv/csv-single-column.csv | csv | - | - | - | - | 90.0% / 0.007s | 90.0% / 0.007s | 90.0% / 0.007s | - | - |
| tests/data/csv/csv-tab.csv | csv | - | - | - | - | 90.0% / 0.009s | 90.0% / 0.009s | 90.0% / 0.006s | - | - |
| tests/data/csv/csv-too-few-columns.csv | csv | - | - | - | - | 90.0% / 0.007s | 90.0% / 0.007s | 90.0% / 0.008s | - | - |
| tests/data/csv/csv-too-many-columns.csv | csv | - | - | - | - | 90.0% / 0.009s | 90.0% / 0.009s | 90.0% / 0.007s | - | - |
| tests/data/docx/docx_checkboxes.docx | docx | - | - | - | - | 90.0% / 0.208s | 90.0% / 0.015s | 90.0% / 0.030s | - | - |
| tests/data/docx/docx_external_image.docx | docx | - | - | - | - | 95.0% / 0.198s | 95.0% / 0.007s | 95.0% / 0.081s | - | - |
| tests/data/docx/docx_grouped_images.docx | docx | - | - | - | - | 95.0% / 0.215s | 95.0% / 0.023s | 95.0% / 0.027s | - | - |
| tests/data/docx/docx_rich_cells.docx | docx | - | - | - | - | 90.0% / 0.238s | 90.0% / 0.046s | 90.0% / 0.041s | - | - |
| tests/data/docx/docx_vml_images.docx | docx | - | - | - | - | 95.0% / 0.202s | 95.0% / 0.010s | 95.0% / 0.078s | - | - |
| tests/data/docx/drawingml.docx | docx | - | - | - | - | 65.0% / 0.200s | 65.0% / 0.007s | 65.0% / 0.020s | - | - |
| tests/data/docx/equations.docx | docx | - | - | - | - | 95.0% / 0.220s | 95.0% / 0.029s | 95.0% / 0.048s | - | - |
| tests/data/docx/list_after_num_headers.docx | docx | - | - | - | - | 95.0% / 0.204s | 95.0% / 0.011s | 95.0% / 0.028s | - | - |
| tests/data/docx/lorem_ipsum.docx | docx | - | - | - | - | 95.0% / 0.197s | 95.0% / 0.004s | 95.0% / 0.013s | - | - |
| tests/data/docx/omml_frac_superscript.docx | docx | - | - | - | - | 95.0% / 0.199s | 95.0% / 0.006s | 95.0% / 0.080s | - | - |
| tests/data/docx/omml_func_log.docx | docx | - | - | - | - | 95.0% / 0.200s | 95.0% / 0.007s | 95.0% / 0.082s | - | - |
| tests/data/docx/omml_multi_equation_paragraph.docx | docx | - | - | - | - | 95.0% / 0.199s | 95.0% / 0.006s | 95.0% / 0.084s | - | - |
| tests/data/docx/omml_text_escapes_in_math.docx | docx | - | - | - | - | 95.0% / 0.200s | 95.0% / 0.006s | 95.0% / 0.085s | - | - |
| tests/data/docx/table_with_equations.docx | docx | - | - | - | - | 90.0% / 0.197s | 90.0% / 0.004s | 90.0% / 0.015s | - | - |
| tests/data/docx/tablecell.docx | docx | - | - | - | - | 90.0% / 0.199s | 90.0% / 0.005s | 90.0% / 0.024s | - | - |
| tests/data/docx/test_emf_docx.docx | docx | - | - | - | - | 95.0% / 0.228s | 95.0% / 0.034s | 95.0% / 0.045s | - | - |
| tests/data/docx/textbox.docx | docx | - | - | - | - | 95.0% / 0.215s | 95.0% / 0.021s | 95.0% / 0.056s | - | - |
| tests/data/docx/unit_test_formatting.docx | docx | - | - | - | - | 95.0% / 0.210s | 95.0% / 0.016s | 95.0% / 0.027s | - | - |
| tests/data/docx/unit_test_headers.docx | docx | - | - | - | - | 95.0% / 0.211s | 95.0% / 0.017s | 95.0% / 0.016s | - | - |
| tests/data/docx/unit_test_headers_numbered.docx | docx | - | - | - | - | 95.0% / 0.222s | 95.0% / 0.028s | 95.0% / 0.031s | - | - |
| tests/data/docx/unit_test_lists.docx | docx | - | - | - | - | 95.0% / 0.210s | 95.0% / 0.017s | 95.0% / 0.026s | - | - |
| tests/data/docx/word_comments.docx | docx | - | - | - | - | 95.0% / 0.201s | 95.0% / 0.008s | 95.0% / 0.081s | - | - |
| tests/data/docx/word_image_anchors.docx | docx | - | - | - | - | 95.0% / 0.201s | 95.0% / 0.007s | 95.0% / 0.015s | - | - |
| tests/data/docx/word_sample.docx | docx | - | - | - | - | 94.0% / 0.217s | 94.0% / 0.023s | 67.3% / 0.035s | - | - |
| tests/data/docx/word_tables.docx | docx | - | - | - | - | 90.0% / 0.217s | 90.0% / 0.022s | 90.0% / 0.038s | - | - |
| tests/data/html/example_01.html | html | - | - | - | - | 95.0% / 0.204s | 95.0% / 0.011s | 95.0% / 0.007s | - | - |
| tests/data/html/example_02.html | html | - | - | - | - | 95.0% / 0.194s | 95.0% / 0.002s | 95.0% / 0.007s | - | - |
| tests/data/html/example_03.html | html | - | - | - | - | 90.0% / 0.196s | 90.0% / 0.004s | 90.0% / 0.007s | - | - |
| tests/data/html/example_04.html | html | - | - | - | - | 90.0% / 0.195s | 90.0% / 0.002s | 90.0% / 0.015s | - | - |
| tests/data/html/example_05.html | html | - | - | - | - | 90.0% / 0.194s | 90.0% / 0.002s | 90.0% / 0.007s | - | - |
| tests/data/html/example_06.html | html | - | - | - | - | 95.0% / 0.194s | 95.0% / 0.002s | 95.0% / 0.008s | - | - |
| tests/data/html/example_07.html | html | - | - | - | - | 95.0% / 0.196s | 95.0% / 0.003s | 95.0% / 0.007s | - | - |
| tests/data/html/example_08.html | html | - | - | - | - | 90.0% / 0.198s | 90.0% / 0.005s | 90.0% / 0.009s | - | - |
| tests/data/html/formatting.html | html | - | - | - | - | 95.0% / 0.199s | 95.0% / 0.008s | 95.0% / 0.008s | - | - |
| tests/data/html/html_code_snippets.html | html | - | - | - | - | 95.0% / 0.197s | 95.0% / 0.005s | 95.0% / 0.009s | - | - |
| tests/data/html/html_heading_in_p.html | html | - | - | - | - | 90.0% / 0.198s | 90.0% / 0.006s | 90.0% / 0.009s | - | - |
| tests/data/html/html_inline_group_in_table_cell.html | html | - | - | - | - | 90.0% / 0.196s | 90.0% / 0.004s | 90.0% / 0.007s | - | - |
| tests/data/html/html_rich_table_cells.html | html | - | - | - | - | 90.0% / 0.201s | 90.0% / 0.008s | 90.0% / 0.010s | - | - |
| tests/data/html/hyperlink_01.html | html | - | - | - | - | 65.0% / 0.194s | 65.0% / 0.002s | 65.0% / 0.006s | - | - |
| tests/data/html/hyperlink_02.html | html | - | - | - | - | 65.0% / 0.193s | 65.0% / 0.001s | 95.0% / 0.007s | - | - |
| tests/data/html/hyperlink_03.html | html | - | - | - | - | 95.0% / 0.196s | 95.0% / 0.003s | 95.0% / 0.008s | - | - |
| tests/data/html/hyperlink_04.html | html | - | - | - | - | 65.0% / 0.193s | 65.0% / 0.001s | 65.0% / 0.007s | - | - |
| tests/data/html/hyperlink_05.html | html | - | - | - | - | 95.0% / 0.194s | 95.0% / 0.001s | 95.0% / 0.007s | - | - |
| tests/data/html/hyperlink_06.html | html | - | - | - | - | 95.0% / 0.195s | 95.0% / 0.002s | 95.0% / 0.007s | - | - |
| tests/data/html/kvp_data_example.html | html | - | - | - | - | 90.0% / 0.199s | 90.0% / 0.006s | 90.0% / 0.009s | - | - |
| tests/data/html/table_01.html | html | - | - | - | - | 60.0% / 0.194s | 60.0% / 0.002s | 60.0% / 0.007s | - | - |
| tests/data/html/table_02.html | html | - | - | - | - | 90.0% / 0.194s | 90.0% / 0.002s | 90.0% / 0.007s | - | - |
| tests/data/html/table_03.html | html | - | - | - | - | 90.0% / 0.195s | 90.0% / 0.002s | 90.0% / 0.007s | - | - |
| tests/data/html/table_04.html | html | - | - | - | - | 90.0% / 0.195s | 90.0% / 0.002s | 90.0% / 0.008s | - | - |
| tests/data/html/table_05.html | html | - | - | - | - | 90.0% / 0.195s | 90.0% / 0.002s | 90.0% / 0.007s | - | - |
| tests/data/html/table_06.html | html | - | - | - | - | 90.0% / 0.195s | 90.0% / 0.003s | 90.0% / 0.007s | - | - |
| tests/data/html/table_with_heading_01.html | html | - | - | - | - | 60.0% / 0.194s | 60.0% / 0.001s | 60.0% / 0.007s | - | - |
| tests/data/html/table_with_heading_02.html | html | - | - | - | - | 90.0% / 0.195s | 90.0% / 0.002s | 90.0% / 0.008s | - | - |
| tests/data/html/unit_test_01.html | html | - | - | - | - | 95.0% / 0.194s | 95.0% / 0.002s | 95.0% / 0.007s | - | - |
| tests/data/html/wiki_duck.html | html | - | - | - | - | 90.0% / 0.361s | 90.0% / 0.164s | 80.0% / 0.065s | - | - |
| tests/data/2305.03393v1-pg9-img.png | image | 95.0% / 24.310s | - | - | 95.0% / 1.482s | 65.0% / 0.546s | 65.0% / 0.538s | 65.0% / 0.342s | - | - |
| tests/data/2305.03393v1-table_crop.png | image | 95.0% / 7.627s | - | - | 95.0% / 0.416s | 65.0% / 0.117s | 65.0% / 0.114s | 65.0% / 0.113s | - | - |
| tests/data/html/example_image_01.png | image | 95.0% / 7.024s | - | - | 95.0% / 0.210s | 65.0% / 0.118s | 65.0% / 0.113s | 65.0% / 0.100s | - | - |
| tests/data/latex/1706.03762/Figures/ModalNet-19.png | image | 65.0% / 3.751s | - | - | 65.0% / 0.105s | 65.0% / 0.114s | 65.0% / 0.110s | 65.0% / 0.098s | - | - |
| tests/data/latex/1706.03762/Figures/ModalNet-20.png | image | 65.0% / 5.691s | - | - | 65.0% / 0.133s | 65.0% / 0.114s | 65.0% / 0.112s | 65.0% / 0.098s | - | - |
| tests/data/latex/1706.03762/Figures/ModalNet-21.png | image | 95.0% / 20.638s | - | - | 95.0% / 0.401s | 65.0% / 0.117s | 65.0% / 0.112s | 65.0% / 0.097s | - | - |
| tests/data/latex/1706.03762/Figures/ModalNet-22.png | image | 65.0% / 3.612s | - | - | 65.0% / 0.105s | 65.0% / 0.114s | 65.0% / 0.112s | 65.0% / 0.098s | - | - |
| tests/data/latex/1706.03762/Figures/ModalNet-23.png | image | 65.0% / 2.704s | - | - | 65.0% / 0.079s | 65.0% / 0.113s | 65.0% / 0.110s | 65.0% / 0.098s | - | - |
| tests/data/latex/1706.03762/Figures/ModalNet-32.png | image | 65.0% / 5.752s | - | - | 65.0% / 0.164s | 65.0% / 0.116s | 65.0% / 0.110s | 65.0% / 0.099s | - | - |
| tests/data/latex/2305.03393/figs/html_freq_v4.png | image | ERR | - | - | 95.0% / 0.486s | 65.0% / 0.178s | 65.0% / 0.170s | 65.0% / 0.141s | - | - |
| tests/data/latex/2310.06825/images/230927_bars.png | image | ERR | - | - | 95.0% / 0.411s | 65.0% / 0.147s | 65.0% / 0.140s | 65.0% / 0.112s | - | - |
| tests/data/latex/2310.06825/images/230927_effective_sizes.png | image | ERR | - | - | 95.0% / 0.702s | 65.0% / 0.129s | 65.0% / 0.123s | 65.0% / 0.099s | - | - |
| tests/data/latex/2310.06825/images/llama_vs_mistral_example.png | image | ERR | - | - | 95.0% / 0.809s | 65.0% / 0.167s | 65.0% / 0.166s | 65.0% / 0.138s | - | - |
| tests/data/tiff/2206.01062.tif | image | 15.5% / 39.863s | - | - | 11.8% / 0.867s | 10.1% / 0.001s | 10.1% / 0.001s | 10.1% / 0.002s | - | - |
| tests/data/webp/webp-test.webp | image | ERR | - | - | 95.0% / 0.291s | 65.0% / 0.002s | 65.0% / 0.002s | 65.0% / 0.003s | - | - |
| tests/data/latex/1706.03762/vis/anaphora_resolution2_new.pdf | pdf | 95.0% / 5.828s | 95.0% / 0.025s | 95.0% / 0.027s | 95.0% / 0.330s | 95.0% / 2.042s | 95.0% / 1.804s | - | 95.0% / 0.019s | 95.0% / 0.031s |
| tests/data/latex/1706.03762/vis/anaphora_resolution_new.pdf | pdf | 95.0% / 5.655s | 95.0% / 0.018s | 95.0% / 0.006s | 95.0% / 0.299s | 65.0% / 0.355s | 65.0% / 0.142s | - | 95.0% / 0.009s | 95.0% / 0.009s |
| tests/data/latex/1706.03762/vis/attending_to_head2_new.pdf | pdf | 95.0% / 5.704s | 95.0% / 0.016s | 95.0% / 0.005s | 95.0% / 0.301s | 65.0% / 0.334s | 65.0% / 0.132s | - | 95.0% / 0.007s | 95.0% / 0.009s |
| tests/data/latex/1706.03762/vis/attending_to_head_new.pdf | pdf | 95.0% / 5.576s | 95.0% / 0.017s | 95.0% / 0.005s | 95.0% / 0.289s | 65.0% / 0.360s | 65.0% / 0.138s | - | 95.0% / 0.008s | 95.0% / 0.009s |
| tests/data/latex/1706.03762/vis/making_more_difficult5_new.pdf | pdf | 95.0% / 6.991s | 95.0% / 0.019s | 95.0% / 0.006s | 95.0% / 0.367s | 65.0% / 0.363s | 65.0% / 0.147s | - | 95.0% / 0.010s | 95.0% / 0.010s |
| tests/data/latex/1706.03762/vis/making_more_difficult_new.pdf | pdf | 95.0% / 6.728s | 95.0% / 0.020s | 95.0% / 0.007s | 95.0% / 0.371s | 65.0% / 0.356s | 65.0% / 0.150s | - | 95.0% / 0.011s | 95.0% / 0.010s |
| tests/data/latex/2305.03393/figs/HTMLvOTSLv7.pdf | pdf | 95.0% / 8.414s | 95.0% / 0.011s | 95.0% / 0.003s | 85.0% / 1.364s | 95.0% / 1.676s | 95.0% / 1.473s | - | 95.0% / 0.004s | 95.0% / 0.003s |
| tests/data/latex/2305.03393/figs/html_v_otsl_intro_v2.pdf | pdf | 95.0% / 9.091s | 95.0% / 0.010s | 95.0% / 0.002s | 95.0% / 0.469s | 95.0% / 0.631s | 95.0% / 0.413s | - | 95.0% / 0.002s | 95.0% / 0.003s |
| tests/data/latex/2305.03393/figs/otsl_proof_v3.pdf | pdf | 95.0% / 3.951s | 95.0% / 0.009s | 95.0% / 0.001s | 95.0% / 0.291s | 95.0% / 0.575s | 95.0% / 0.365s | - | 95.0% / 0.001s | 95.0% / 0.003s |
| tests/data/latex/2305.03393/figs/otsl_vs_html_ex3_v2.pdf | pdf | ERR | 95.0% / 0.010s | 95.0% / 0.003s | 95.0% / 3.325s | 95.0% / 7.102s | 95.0% / 6.883s | - | 95.0% / 0.002s | 95.0% / 0.001s |
| tests/data/latex/2305.03393/figs/tablemodel_overview_otsl.pdf | pdf | 95.0% / 8.636s | 95.0% / 0.011s | 95.0% / 0.002s | 95.0% / 0.517s | 95.0% / 0.709s | 95.0% / 0.526s | - | 95.0% / 0.003s | 95.0% / 0.003s |
| tests/data/latex/2305.03393/llncsdoc.pdf | pdf | ERR | 95.0% / 0.022s | 95.0% / 0.018s | 95.0% / 4.093s | 90.0% / 1.639s | 90.0% / 1.401s | - | 95.0% / 0.022s | 95.0% / 0.018s |
| tests/data/latex/2310.06825/images/chunking.pdf | pdf | 95.0% / 10.244s | 95.0% / 0.010s | 95.0% / 0.002s | 95.0% / 0.416s | 65.0% / 0.351s | 65.0% / 0.146s | - | 65.0% / 0.002s | 95.0% / 0.002s |
| tests/data/latex/2310.06825/images/rolling_buffer.pdf | pdf | 95.0% / 7.592s | 69.0% / 0.008s | 69.0% / 0.000s | 95.0% / 0.623s | 95.0% / 1.000s | 95.0% / 0.791s | - | 69.0% / 0.000s | 69.0% / 0.000s |
| tests/data/latex/2310.06825/images/swa.pdf | pdf | 95.0% / 9.949s | 69.0% / 0.008s | 69.0% / 0.001s | 95.0% / 0.515s | 95.0% / 1.096s | 95.0% / 0.905s | - | 69.0% / 0.000s | 69.0% / 0.000s |
| tests/data/latex/2412.19437/figures/basic_arch.pdf | pdf | 95.0% / 12.280s | 95.0% / 0.011s | 95.0% / 0.004s | 95.0% / 0.393s | 95.0% / 0.492s | 95.0% / 0.289s | - | 95.0% / 0.005s | 95.0% / 0.007s |
| tests/data/latex/2412.19437/figures/dsv3_performance.pdf | pdf | 95.0% / 10.694s | 95.0% / 0.009s | 95.0% / 0.002s | 95.0% / 0.413s | 95.0% / 0.463s | 95.0% / 0.297s | - | 95.0% / 0.003s | 95.0% / 0.003s |
| tests/data/latex/2412.19437/figures/dualpipe.pdf | pdf | 95.0% / 17.751s | 95.0% / 0.014s | 95.0% / 0.002s | 95.0% / 1.158s | 95.0% / 0.396s | 95.0% / 0.179s | - | 95.0% / 0.005s | 95.0% / 0.005s |
| tests/data/latex/2412.19437/figures/fp8-128accumulatorv4.pdf | pdf | 95.0% / 4.954s | 95.0% / 0.010s | 95.0% / 0.001s | 95.0% / 0.265s | 95.0% / 1.133s | 95.0% / 0.899s | - | 95.0% / 0.001s | 95.0% / 0.002s |
| tests/data/latex/2412.19437/figures/fp8-frameworkv3.pdf | pdf | 95.0% / 5.352s | 95.0% / 0.010s | 95.0% / 0.002s | 95.0% / 0.290s | 95.0% / 0.659s | 95.0% / 0.444s | - | 95.0% / 0.002s | 95.0% / 0.002s |
| tests/data/latex/2412.19437/figures/fp8-v.s.-bf16.pdf | pdf | 95.0% / 6.213s | 69.0% / 0.009s | 69.0% / 0.000s | 95.0% / 0.280s | 95.0% / 0.772s | 95.0% / 0.579s | - | 69.0% / 0.000s | 69.0% / 0.000s |
| tests/data/latex/2412.19437/figures/needle_in_a_haystack.pdf | pdf | 95.0% / 8.986s | 95.0% / 0.010s | 95.0% / 0.001s | 95.0% / 0.375s | 65.0% / 0.460s | 65.0% / 0.248s | - | 95.0% / 0.002s | 95.0% / 0.001s |
| tests/data/latex/2412.19437/figures/nextn.pdf | pdf | 95.0% / 9.539s | 95.0% / 0.010s | 95.0% / 0.003s | 95.0% / 0.453s | 95.0% / 0.437s | 95.0% / 0.219s | - | 95.0% / 0.003s | 95.0% / 0.005s |
| tests/data/latex/2412.19437/figures/overlap.pdf | pdf | 95.0% / 3.819s | 95.0% / 0.010s | 95.0% / 0.001s | 95.0% / 0.320s | 65.0% / 0.307s | 65.0% / 0.109s | - | 95.0% / 0.001s | 95.0% / 0.002s |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi.pdf | pdf | 95.0% / 10.757s | 95.0% / 0.012s | 95.0% / 0.003s | 95.0% / 0.675s | 95.0% / 0.423s | 95.0% / 0.224s | - | 95.0% / 0.007s | 95.0% / 0.003s |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi_1-6.pdf | pdf | 95.0% / 17.936s | 95.0% / 0.019s | 95.0% / 0.006s | 95.0% / 0.902s | 95.0% / 0.663s | 95.0% / 0.447s | - | 95.0% / 0.030s | 95.0% / 0.009s |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi_13-18.pdf | pdf | 95.0% / 17.606s | 95.0% / 0.019s | 95.0% / 0.006s | 95.0% / 1.026s | 95.0% / 0.652s | 95.0% / 0.471s | - | 95.0% / 0.030s | 95.0% / 0.009s |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi_19-24.pdf | pdf | 95.0% / 17.951s | 95.0% / 0.021s | 95.0% / 0.006s | 95.0% / 0.860s | 95.0% / 0.660s | 95.0% / 0.464s | - | 95.0% / 0.030s | 95.0% / 0.010s |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi_25-26.pdf | pdf | 95.0% / 10.531s | 95.0% / 0.012s | 95.0% / 0.002s | 95.0% / 0.606s | 95.0% / 0.417s | 95.0% / 0.213s | - | 95.0% / 0.007s | 95.0% / 0.003s |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi_7-12.pdf | pdf | 95.0% / 18.666s | 95.0% / 0.018s | 95.0% / 0.006s | 95.0% / 0.907s | 95.0% / 0.635s | 95.0% / 0.440s | - | 95.0% / 0.030s | 95.0% / 0.010s |
| tests/data/latex/2412.19437/logo/DeepSeek.pdf | pdf | 65.0% / 2.283s | 69.0% / 0.009s | 69.0% / 0.000s | 65.0% / 0.182s | 69.0% / 0.270s | 69.0% / 0.075s | - | 69.0% / 0.001s | 69.0% / 0.001s |
| tests/data/latex/2501.00089/138-bpt_scatter_examples_3x3.pdf | pdf | 65.0% / 4.056s | 95.0% / 0.010s | 65.0% / 0.002s | 65.0% / 0.186s | 65.0% / 0.638s | 65.0% / 0.420s | - | 65.0% / 0.002s | 95.0% / 0.001s |
| tests/data/latex/2501.00089/157-bpt_scatter_examples_3x3.pdf | pdf | 65.0% / 4.062s | 95.0% / 0.010s | 65.0% / 0.002s | 65.0% / 0.169s | 65.0% / 0.612s | 65.0% / 0.402s | - | 65.0% / 0.002s | 95.0% / 0.001s |
| tests/data/latex/2501.00089/17-bpt_scatter_examples_3x3.pdf | pdf | 65.0% / 4.091s | 95.0% / 0.010s | 65.0% / 0.002s | 65.0% / 0.166s | 65.0% / 0.614s | 65.0% / 0.414s | - | 65.0% / 0.002s | 95.0% / 0.001s |
| tests/data/latex/2501.00089/322-bpt_scatter_examples_3x3.pdf | pdf | 65.0% / 4.094s | 95.0% / 0.009s | 65.0% / 0.002s | 65.0% / 0.166s | 65.0% / 0.608s | 65.0% / 0.418s | - | 65.0% / 0.002s | 95.0% / 0.001s |
| tests/data/latex/2501.00089/SFNet_ResNet18-TopK.pdf | pdf | 95.0% / 4.441s | 95.0% / 0.009s | 95.0% / 0.001s | 95.0% / 0.274s | 65.0% / 0.310s | 65.0% / 0.111s | - | 95.0% / 0.001s | 95.0% / 0.001s |
| tests/data/latex/2501.00089/equations.pdf | pdf | 95.0% / 5.135s | 95.0% / 0.009s | 95.0% / 0.002s | 95.0% / 0.311s | 95.0% / 0.884s | 95.0% / 0.692s | - | 95.0% / 0.002s | 95.0% / 0.001s |
| tests/data/latex/2501.00089/pca-comparison.pdf | pdf | 95.0% / 4.640s | 95.0% / 0.010s | 95.0% / 0.001s | 95.0% / 0.236s | 65.0% / 0.293s | 65.0% / 0.100s | - | 95.0% / 0.002s | 95.0% / 0.001s |
| tests/data/latex/arXiv-2501.01300v2/BQSC-1003.pdf | pdf | 95.0% / 4.534s | 95.0% / 0.010s | 95.0% / 0.002s | 95.0% / 0.173s | 65.0% / 0.316s | 65.0% / 0.114s | - | 95.0% / 0.003s | 95.0% / 0.003s |
| tests/data/latex/arXiv-2501.01300v2/D-BQSC-0004-1003.pdf | pdf | 95.0% / 4.568s | 95.0% / 0.010s | 95.0% / 0.002s | 95.0% / 0.170s | 65.0% / 0.333s | 65.0% / 0.112s | - | 95.0% / 0.003s | 95.0% / 0.003s |
| tests/data/latex/arXiv-2501.01300v2/P_B.pdf | pdf | 95.0% / 5.018s | 95.0% / 0.010s | 95.0% / 0.002s | 95.0% / 0.195s | 65.0% / 0.327s | 65.0% / 0.115s | - | 95.0% / 0.003s | 95.0% / 0.003s |
| tests/data/latex/arXiv-2501.01300v2/P_M.pdf | pdf | 95.0% / 5.116s | 95.0% / 0.010s | 95.0% / 0.002s | 95.0% / 0.174s | 65.0% / 0.333s | 65.0% / 0.112s | - | 95.0% / 0.003s | 95.0% / 0.002s |
| tests/data/latex/arXiv-2501.01300v2/P_q.pdf | pdf | 65.0% / 4.319s | 95.0% / 0.010s | 65.0% / 0.001s | 65.0% / 0.131s | 65.0% / 0.322s | 65.0% / 0.109s | - | 65.0% / 0.002s | 95.0% / 0.002s |
| tests/data/latex/arXiv-2501.01300v2/m_q.pdf | pdf | 95.0% / 4.233s | 95.0% / 0.009s | 95.0% / 0.001s | 95.0% / 0.140s | 65.0% / 0.325s | 65.0% / 0.110s | - | 65.0% / 0.002s | 95.0% / 0.002s |
| tests/data/pdf/2203.01017v2.pdf | pdf | ERR | 24.8% / 0.056s | 28.5% / 0.052s | 20.4% / 18.317s | 74.3% / 21.625s | 74.3% / 21.938s | - | 39.4% / 0.158s | 29.3% / 0.082s |
| tests/data/pdf/2206.01062.pdf | pdf | ERR | 35.7% / 0.061s | 34.3% / 0.057s | 32.8% / 12.526s | 95.0% / 6.051s | 95.0% / 5.665s | - | 36.0% / 0.153s | 21.6% / 0.087s |
| tests/data/pdf/2305.03393v1-pg9.pdf | pdf | 36.5% / 19.069s | 38.0% / 0.012s | 36.6% / 0.004s | 35.6% / 0.899s | 94.8% / 0.813s | 94.8% / 0.608s | - | 51.8% / 0.007s | 37.0% / 0.007s |
| tests/data/pdf/2305.03393v1.pdf | pdf | ERR | 36.7% / 0.036s | 37.7% / 0.035s | 36.6% / 9.676s | 95.0% / 7.262s | 95.0% / 7.095s | - | 41.2% / 0.048s | 39.3% / 0.039s |
| tests/data/pdf/amt_handbook_sample.pdf | pdf | 58.2% / 21.154s | 58.1% / 0.030s | 64.7% / 0.010s | 57.8% / 0.991s | 95.0% / 0.969s | 95.0% / 0.801s | - | 64.4% / 0.010s | 64.5% / 0.009s |
| tests/data/pdf/code_and_formula.pdf | pdf | 63.7% / 34.146s | 62.7% / 0.011s | 63.7% / 0.005s | 62.9% / 1.468s | 95.0% / 0.503s | 95.0% / 0.305s | - | 93.0% / 0.006s | 92.7% / 0.004s |
| tests/data/pdf/multi_page.pdf | pdf | ERR | 64.6% / 0.014s | 64.5% / 0.008s | 62.8% / 2.728s | 95.0% / 1.005s | 95.0% / 0.769s | - | 64.5% / 0.013s | 69.9% / 0.008s |
| tests/data/pdf/normal_4pages.pdf | pdf | ERR | 37.8% / 0.016s | 36.5% / 0.016s | 12.2% / 3.655s | 95.0% / 2.427s | 95.0% / 2.205s | - | 36.5% / 0.020s | 37.7% / 0.019s |
| tests/data/pdf/picture_classification.pdf | pdf | 56.0% / 28.050s | 63.4% / 0.010s | 62.6% / 0.003s | 58.9% / 1.134s | 95.0% / 0.917s | 95.0% / 0.729s | - | 93.7% / 0.003s | 93.1% / 0.002s |
| tests/data/pdf/redp5110_sampled.pdf | pdf | ERR | 27.5% / 0.034s | 29.2% / 0.039s | 10.8% / 11.033s | 94.3% / 6.476s | 94.3% / 6.328s | - | 22.7% / 0.039s | 34.8% / 0.032s |
| tests/data/pdf/right_to_left_01.pdf | pdf | 36.3% / 10.427s | 58.2% / 0.010s | 62.7% / 0.003s | 39.0% / 0.347s | 95.0% / 0.420s | 95.0% / 0.211s | - | 56.0% / 0.006s | 63.1% / 0.005s |
| tests/data/pdf/right_to_left_02.pdf | pdf | 60.9% / 11.907s | 84.9% / 0.011s | 82.8% / 0.003s | 59.1% / 0.431s | 95.0% / 0.583s | 95.0% / 0.372s | - | 89.5% / 0.003s | 83.8% / 0.003s |
| tests/data/pdf/right_to_left_03.pdf | pdf | 29.0% / 8.681s | 56.4% / 0.011s | 60.7% / 0.007s | 36.5% / 0.304s | 95.0% / 0.457s | 95.0% / 0.262s | - | 60.9% / 0.005s | 60.3% / 0.007s |
| tests/data/pdf/skipped_1page.pdf | pdf | 95.0% / 14.387s | 95.0% / 0.013s | 95.0% / 0.004s | 95.0% / 0.506s | 95.0% / 0.496s | 95.0% / 0.249s | - | 95.0% / 0.004s | 95.0% / 0.008s |
| tests/data/pdf/skipped_2pages.pdf | pdf | 95.0% / 21.354s | 95.0% / 0.021s | 95.0% / 0.009s | 95.0% / 0.705s | 95.0% / 0.464s | 95.0% / 0.264s | - | 95.0% / 0.011s | 95.0% / 0.015s |
| tests/data/pdf_password/2206.01062_pg3.pdf | pdf | ERR | ERR | ERR | ERR | ERR | ERR | - | ERR | ERR |
| tests/data/pptx/powerpoint_bad_text.pptx | pptx | - | - | - | - | 95.0% / 0.195s | 95.0% / 0.004s | 95.0% / 0.009s | - | - |
| tests/data/pptx/powerpoint_issue_2663.pptx | pptx | - | - | - | - | 95.0% / 0.197s | 95.0% / 0.006s | 95.0% / 0.010s | - | - |
| tests/data/pptx/powerpoint_malformed_pictures.pptx | pptx | - | - | - | - | 65.0% / 0.195s | 65.0% / 0.004s | 95.0% / 0.008s | - | - |
| tests/data/pptx/powerpoint_sample.pptx | pptx | - | - | - | - | 90.0% / 0.201s | 90.0% / 0.010s | 90.0% / 0.013s | - | - |
| tests/data/pptx/powerpoint_unrecognized_shape.pptx | pptx | - | - | - | - | 95.0% / 0.203s | 95.0% / 0.007s | 95.0% / 0.011s | - | - |
| tests/data/pptx/powerpoint_with_image.pptx | pptx | - | - | - | - | 65.0% / 0.198s | 65.0% / 0.007s | 95.0% / 0.009s | - | - |
| tests/data/webvtt/webvtt_example_01.vtt | webvtt | - | - | - | - | 95.0% / 0.008s | 95.0% / 0.007s | 95.0% / 0.007s | - | - |
| tests/data/webvtt/webvtt_example_02.vtt | webvtt | - | - | - | - | 95.0% / 0.007s | 95.0% / 0.007s | 95.0% / 0.008s | - | - |
| tests/data/webvtt/webvtt_example_03.vtt | webvtt | - | - | - | - | 95.0% / 0.007s | 95.0% / 0.008s | 95.0% / 0.008s | - | - |
| tests/data/webvtt/webvtt_example_04.vtt | webvtt | - | - | - | - | 95.0% / 0.008s | 95.0% / 0.010s | 95.0% / 0.008s | - | - |
| tests/data/xlsx/xlsx_01.xlsx | xlsx | - | - | - | - | 90.0% / 0.210s | 90.0% / 0.020s | 90.0% / 0.019s | - | - |
| tests/data/xlsx/xlsx_03_chartsheet.xlsx | xlsx | - | - | - | - | 90.0% / 0.196s | 90.0% / 0.005s | 90.0% / 0.010s | - | - |
| tests/data/xlsx/xlsx_04_inflated.xlsx | xlsx | - | - | - | - | 90.0% / 0.209s | 90.0% / 0.018s | 90.0% / 0.265s | - | - |
| tests/data/xlsx/xlsx_05_table_with_title.xlsx | xlsx | - | - | - | - | 90.0% / 0.198s | 90.0% / 0.003s | 90.0% / 0.010s | - | - |
| tests/data/xlsx/xlsx_06_edge_cases_.xlsx | xlsx | - | - | - | - | 90.0% / 0.197s | 90.0% / 0.005s | 90.0% / 0.014s | - | - |
| tests/data/xlsx/xlsx_07_gap_tolerance_.xlsx | xlsx | - | - | - | - | 90.0% / 0.205s | 90.0% / 0.014s | 90.0% / 0.017s | - | - |
| tests/data/xlsx/xlsx_08_one_cell_anchor.xlsx | xlsx | - | - | - | - | 90.0% / 0.193s | 90.0% / 0.003s | 60.0% / 0.008s | - | - |
| tests/data/jats/elife-56337.xml | xml | - | - | - | - | 90.0% / 0.214s | 90.0% / 0.021s | 90.0% / 0.051s | - | - |
| tests/data/uspto/ipa20110039701.xml | xml | - | - | - | - | 95.0% / 0.273s | 95.0% / 0.069s | 95.0% / 0.100s | - | - |
| tests/data/uspto/ipa20180000016.xml | xml | - | - | - | - | 15.4% / 0.203s | 15.4% / 0.012s | 15.4% / 0.019s | - | - |
| tests/data/uspto/ipa20200022300.xml | xml | - | - | - | - | 38.9% / 0.202s | 38.9% / 0.011s | 38.9% / 0.009s | - | - |
| tests/data/uspto/ipg07997973.xml | xml | - | - | - | - | 95.0% / 0.310s | 95.0% / 0.118s | 95.0% / 0.029s | - | - |
| tests/data/uspto/ipg08672134.xml | xml | - | - | - | - | 95.0% / 0.204s | 95.0% / 0.012s | 95.0% / 0.011s | - | - |
| tests/data/uspto/ipgD0701016.xml | xml | - | - | - | - | 95.0% / 0.202s | 95.0% / 0.010s | 95.0% / 0.009s | - | - |
| tests/data/uspto/pa20010031492.xml | xml | - | - | - | - | 15.7% / 0.201s | 15.7% / 0.008s | 15.7% / 0.007s | - | - |
| tests/data/uspto/pg06442728.xml | xml | - | - | - | - | 39.6% / 0.201s | 39.6% / 0.012s | 39.6% / 0.008s | - | - |
| tests/data/uspto/tables_ipa20180000016.xml | xml | - | - | - | - | 95.0% / 0.199s | 95.0% / 0.008s | 95.0% / 0.007s | - | - |
| tests/data/xbrl/grve_10q_htm.xml | xml | - | - | - | - | 95.0% / 0.209s | 95.0% / 0.018s | 95.0% / 0.022s | - | - |
| tests/data/xbrl/mlac-20251231.xml | xml | - | - | - | - | 95.0% / 0.209s | 95.0% / 0.019s | 95.0% / 0.017s | - | - |

## Document-Level Data

Use the JSON reports in the same artifact for component scores, elapsed time, errors, regression review, and uplift review.
