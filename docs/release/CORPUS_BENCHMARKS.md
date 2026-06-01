# Corpus Pathway Benchmark Comparison

This report compares convert-to-Markdown quality by pathway. Shipping decisions use the stored baseline ledger; internal reference pathways are evidence only and do not imply approval to ship those dependencies.

## Pathway Summary

| Pathway | Status | Pipeline | Documents | Overall | Failed |
| --- | --- | --- | ---: | ---: | ---: |
| internal-reference-paddleocr | internal-reference-only | not run | 0 | - | - |
| internal-reference-poppler | internal-reference-only | not run | 0 | - | - |
| internal-reference-pymupdf | internal-reference-only | not run | 0 | - | - |
| internal-reference-rapidocr | internal-reference-only | not run | 0 | - | - |
| python-ai-docling | shipping | not run | 0 | - | - |
| python-enhanced-docling | shipping | not run | 0 | - | - |
| python-fast-markitdown | shipping | fast | 111 | 83.8% | 0 |
| python-fast-pdfium | shipping | fast | 60 | 80.1% | 1 |
| swift-avfoundation-metadata | shipping | not run | 0 | - | - |
| swift-imageio-metadata | shipping | not run | 0 | - | - |
| swift-pdfkit | shipping | not run | 0 | - | - |
| swift-speech | shipping | not run | 0 | - | - |
| swift-vision-document | shipping | not run | 0 | - | - |

## Category Summary

### python-fast-markitdown

| Category | Documents | Overall | Failed |
| --- | ---: | ---: | ---: |
| asciidoc | 3 | 90.0% | 0 |
| csv | 9 | 86.7% | 0 |
| docx | 25 | 91.7% | 0 |
| html | 30 | 87.8% | 0 |
| image | 15 | 61.3% | 0 |
| pptx | 6 | 94.2% | 0 |
| webvtt | 4 | 95.0% | 0 |
| xlsx | 7 | 85.7% | 0 |
| xml | 12 | 72.1% | 0 |

### python-fast-pdfium

| Category | Documents | Overall | Failed |
| --- | ---: | ---: | ---: |
| pdf | 60 | 80.1% | 1 |

## Document Score Matrix

Scores are overall percentages. `ERR` means the pathway ran and failed for that file. `-` means that converter was not run for that file.

| File | Category | python-fast-markitdown | python-fast-pdfium |
| --- | --- | ---: | ---: |
| tests/data/asciidoc/test_01.asciidoc | asciidoc | 95.0% | - |
| tests/data/asciidoc/test_02.asciidoc | asciidoc | 80.0% | - |
| tests/data/asciidoc/test_03.asciidoc | asciidoc | 95.0% | - |
| tests/data/csv/csv-comma-in-cell.csv | csv | 90.0% | - |
| tests/data/csv/csv-comma.csv | csv | 90.0% | - |
| tests/data/csv/csv-inconsistent-header.csv | csv | 60.0% | - |
| tests/data/csv/csv-pipe.csv | csv | 90.0% | - |
| tests/data/csv/csv-semicolon.csv | csv | 90.0% | - |
| tests/data/csv/csv-single-column.csv | csv | 90.0% | - |
| tests/data/csv/csv-tab.csv | csv | 90.0% | - |
| tests/data/csv/csv-too-few-columns.csv | csv | 90.0% | - |
| tests/data/csv/csv-too-many-columns.csv | csv | 90.0% | - |
| tests/data/docx/docx_checkboxes.docx | docx | 90.0% | - |
| tests/data/docx/docx_external_image.docx | docx | 95.0% | - |
| tests/data/docx/docx_grouped_images.docx | docx | 95.0% | - |
| tests/data/docx/docx_rich_cells.docx | docx | 90.0% | - |
| tests/data/docx/docx_vml_images.docx | docx | 95.0% | - |
| tests/data/docx/drawingml.docx | docx | 65.0% | - |
| tests/data/docx/equations.docx | docx | 95.0% | - |
| tests/data/docx/list_after_num_headers.docx | docx | 95.0% | - |
| tests/data/docx/lorem_ipsum.docx | docx | 95.0% | - |
| tests/data/docx/omml_frac_superscript.docx | docx | 95.0% | - |
| tests/data/docx/omml_func_log.docx | docx | 95.0% | - |
| tests/data/docx/omml_multi_equation_paragraph.docx | docx | 95.0% | - |
| tests/data/docx/omml_text_escapes_in_math.docx | docx | 95.0% | - |
| tests/data/docx/table_with_equations.docx | docx | 90.0% | - |
| tests/data/docx/tablecell.docx | docx | 90.0% | - |
| tests/data/docx/test_emf_docx.docx | docx | 95.0% | - |
| tests/data/docx/textbox.docx | docx | 95.0% | - |
| tests/data/docx/unit_test_formatting.docx | docx | 95.0% | - |
| tests/data/docx/unit_test_headers.docx | docx | 95.0% | - |
| tests/data/docx/unit_test_headers_numbered.docx | docx | 95.0% | - |
| tests/data/docx/unit_test_lists.docx | docx | 95.0% | - |
| tests/data/docx/word_comments.docx | docx | 95.0% | - |
| tests/data/docx/word_image_anchors.docx | docx | 95.0% | - |
| tests/data/docx/word_sample.docx | docx | 67.3% | - |
| tests/data/docx/word_tables.docx | docx | 90.0% | - |
| tests/data/html/example_01.html | html | 95.0% | - |
| tests/data/html/example_02.html | html | 95.0% | - |
| tests/data/html/example_03.html | html | 90.0% | - |
| tests/data/html/example_04.html | html | 90.0% | - |
| tests/data/html/example_05.html | html | 90.0% | - |
| tests/data/html/example_06.html | html | 95.0% | - |
| tests/data/html/example_07.html | html | 95.0% | - |
| tests/data/html/example_08.html | html | 90.0% | - |
| tests/data/html/formatting.html | html | 95.0% | - |
| tests/data/html/html_code_snippets.html | html | 95.0% | - |
| tests/data/html/html_heading_in_p.html | html | 90.0% | - |
| tests/data/html/html_inline_group_in_table_cell.html | html | 90.0% | - |
| tests/data/html/html_rich_table_cells.html | html | 90.0% | - |
| tests/data/html/hyperlink_01.html | html | 65.0% | - |
| tests/data/html/hyperlink_02.html | html | 95.0% | - |
| tests/data/html/hyperlink_03.html | html | 95.0% | - |
| tests/data/html/hyperlink_04.html | html | 65.0% | - |
| tests/data/html/hyperlink_05.html | html | 95.0% | - |
| tests/data/html/hyperlink_06.html | html | 95.0% | - |
| tests/data/html/kvp_data_example.html | html | 90.0% | - |
| tests/data/html/table_01.html | html | 60.0% | - |
| tests/data/html/table_02.html | html | 90.0% | - |
| tests/data/html/table_03.html | html | 90.0% | - |
| tests/data/html/table_04.html | html | 90.0% | - |
| tests/data/html/table_05.html | html | 90.0% | - |
| tests/data/html/table_06.html | html | 90.0% | - |
| tests/data/html/table_with_heading_01.html | html | 60.0% | - |
| tests/data/html/table_with_heading_02.html | html | 90.0% | - |
| tests/data/html/unit_test_01.html | html | 95.0% | - |
| tests/data/html/wiki_duck.html | html | 80.0% | - |
| tests/data/2305.03393v1-pg9-img.png | image | 65.0% | - |
| tests/data/2305.03393v1-table_crop.png | image | 65.0% | - |
| tests/data/html/example_image_01.png | image | 65.0% | - |
| tests/data/latex/1706.03762/Figures/ModalNet-19.png | image | 65.0% | - |
| tests/data/latex/1706.03762/Figures/ModalNet-20.png | image | 65.0% | - |
| tests/data/latex/1706.03762/Figures/ModalNet-21.png | image | 65.0% | - |
| tests/data/latex/1706.03762/Figures/ModalNet-22.png | image | 65.0% | - |
| tests/data/latex/1706.03762/Figures/ModalNet-23.png | image | 65.0% | - |
| tests/data/latex/1706.03762/Figures/ModalNet-32.png | image | 65.0% | - |
| tests/data/latex/2305.03393/figs/html_freq_v4.png | image | 65.0% | - |
| tests/data/latex/2310.06825/images/230927_bars.png | image | 65.0% | - |
| tests/data/latex/2310.06825/images/230927_effective_sizes.png | image | 65.0% | - |
| tests/data/latex/2310.06825/images/llama_vs_mistral_example.png | image | 65.0% | - |
| tests/data/tiff/2206.01062.tif | image | 10.1% | - |
| tests/data/webp/webp-test.webp | image | 65.0% | - |
| tests/data/latex/1706.03762/vis/anaphora_resolution2_new.pdf | pdf | - | 95.0% |
| tests/data/latex/1706.03762/vis/anaphora_resolution_new.pdf | pdf | - | 95.0% |
| tests/data/latex/1706.03762/vis/attending_to_head2_new.pdf | pdf | - | 95.0% |
| tests/data/latex/1706.03762/vis/attending_to_head_new.pdf | pdf | - | 95.0% |
| tests/data/latex/1706.03762/vis/making_more_difficult5_new.pdf | pdf | - | 95.0% |
| tests/data/latex/1706.03762/vis/making_more_difficult_new.pdf | pdf | - | 95.0% |
| tests/data/latex/2305.03393/figs/HTMLvOTSLv7.pdf | pdf | - | 95.0% |
| tests/data/latex/2305.03393/figs/html_v_otsl_intro_v2.pdf | pdf | - | 95.0% |
| tests/data/latex/2305.03393/figs/otsl_proof_v3.pdf | pdf | - | 95.0% |
| tests/data/latex/2305.03393/figs/otsl_vs_html_ex3_v2.pdf | pdf | - | 95.0% |
| tests/data/latex/2305.03393/figs/tablemodel_overview_otsl.pdf | pdf | - | 95.0% |
| tests/data/latex/2305.03393/llncsdoc.pdf | pdf | - | 95.0% |
| tests/data/latex/2310.06825/images/chunking.pdf | pdf | - | 65.0% |
| tests/data/latex/2310.06825/images/rolling_buffer.pdf | pdf | - | 69.0% |
| tests/data/latex/2310.06825/images/swa.pdf | pdf | - | 69.0% |
| tests/data/latex/2412.19437/figures/basic_arch.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/dsv3_performance.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/dualpipe.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/fp8-128accumulatorv4.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/fp8-frameworkv3.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/fp8-v.s.-bf16.pdf | pdf | - | 69.0% |
| tests/data/latex/2412.19437/figures/needle_in_a_haystack.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/nextn.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/overlap.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi_1-6.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi_13-18.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi_19-24.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi_25-26.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/figures/relative_expert_load_multi_7-12.pdf | pdf | - | 95.0% |
| tests/data/latex/2412.19437/logo/DeepSeek.pdf | pdf | - | 69.0% |
| tests/data/latex/2501.00089/138-bpt_scatter_examples_3x3.pdf | pdf | - | 65.0% |
| tests/data/latex/2501.00089/157-bpt_scatter_examples_3x3.pdf | pdf | - | 65.0% |
| tests/data/latex/2501.00089/17-bpt_scatter_examples_3x3.pdf | pdf | - | 65.0% |
| tests/data/latex/2501.00089/322-bpt_scatter_examples_3x3.pdf | pdf | - | 65.0% |
| tests/data/latex/2501.00089/SFNet_ResNet18-TopK.pdf | pdf | - | 95.0% |
| tests/data/latex/2501.00089/equations.pdf | pdf | - | 95.0% |
| tests/data/latex/2501.00089/pca-comparison.pdf | pdf | - | 95.0% |
| tests/data/latex/arXiv-2501.01300v2/BQSC-1003.pdf | pdf | - | 95.0% |
| tests/data/latex/arXiv-2501.01300v2/D-BQSC-0004-1003.pdf | pdf | - | 95.0% |
| tests/data/latex/arXiv-2501.01300v2/P_B.pdf | pdf | - | 95.0% |
| tests/data/latex/arXiv-2501.01300v2/P_M.pdf | pdf | - | 95.0% |
| tests/data/latex/arXiv-2501.01300v2/P_q.pdf | pdf | - | 65.0% |
| tests/data/latex/arXiv-2501.01300v2/m_q.pdf | pdf | - | 65.0% |
| tests/data/pdf/2203.01017v2.pdf | pdf | - | 39.4% |
| tests/data/pdf/2206.01062.pdf | pdf | - | 36.0% |
| tests/data/pdf/2305.03393v1-pg9.pdf | pdf | - | 51.8% |
| tests/data/pdf/2305.03393v1.pdf | pdf | - | 41.2% |
| tests/data/pdf/amt_handbook_sample.pdf | pdf | - | 64.4% |
| tests/data/pdf/code_and_formula.pdf | pdf | - | 93.0% |
| tests/data/pdf/multi_page.pdf | pdf | - | 64.5% |
| tests/data/pdf/normal_4pages.pdf | pdf | - | 36.5% |
| tests/data/pdf/picture_classification.pdf | pdf | - | 93.7% |
| tests/data/pdf/redp5110_sampled.pdf | pdf | - | 22.7% |
| tests/data/pdf/right_to_left_01.pdf | pdf | - | 56.0% |
| tests/data/pdf/right_to_left_02.pdf | pdf | - | 89.5% |
| tests/data/pdf/right_to_left_03.pdf | pdf | - | 60.9% |
| tests/data/pdf/skipped_1page.pdf | pdf | - | 95.0% |
| tests/data/pdf/skipped_2pages.pdf | pdf | - | 95.0% |
| tests/data/pdf_password/2206.01062_pg3.pdf | pdf | - | ERR |
| tests/data/pptx/powerpoint_bad_text.pptx | pptx | 95.0% | - |
| tests/data/pptx/powerpoint_issue_2663.pptx | pptx | 95.0% | - |
| tests/data/pptx/powerpoint_malformed_pictures.pptx | pptx | 95.0% | - |
| tests/data/pptx/powerpoint_sample.pptx | pptx | 90.0% | - |
| tests/data/pptx/powerpoint_unrecognized_shape.pptx | pptx | 95.0% | - |
| tests/data/pptx/powerpoint_with_image.pptx | pptx | 95.0% | - |
| tests/data/webvtt/webvtt_example_01.vtt | webvtt | 95.0% | - |
| tests/data/webvtt/webvtt_example_02.vtt | webvtt | 95.0% | - |
| tests/data/webvtt/webvtt_example_03.vtt | webvtt | 95.0% | - |
| tests/data/webvtt/webvtt_example_04.vtt | webvtt | 95.0% | - |
| tests/data/xlsx/xlsx_01.xlsx | xlsx | 90.0% | - |
| tests/data/xlsx/xlsx_03_chartsheet.xlsx | xlsx | 90.0% | - |
| tests/data/xlsx/xlsx_04_inflated.xlsx | xlsx | 90.0% | - |
| tests/data/xlsx/xlsx_05_table_with_title.xlsx | xlsx | 90.0% | - |
| tests/data/xlsx/xlsx_06_edge_cases_.xlsx | xlsx | 90.0% | - |
| tests/data/xlsx/xlsx_07_gap_tolerance_.xlsx | xlsx | 90.0% | - |
| tests/data/xlsx/xlsx_08_one_cell_anchor.xlsx | xlsx | 60.0% | - |
| tests/data/jats/elife-56337.xml | xml | 90.0% | - |
| tests/data/uspto/ipa20110039701.xml | xml | 95.0% | - |
| tests/data/uspto/ipa20180000016.xml | xml | 15.4% | - |
| tests/data/uspto/ipa20200022300.xml | xml | 38.9% | - |
| tests/data/uspto/ipg07997973.xml | xml | 95.0% | - |
| tests/data/uspto/ipg08672134.xml | xml | 95.0% | - |
| tests/data/uspto/ipgD0701016.xml | xml | 95.0% | - |
| tests/data/uspto/pa20010031492.xml | xml | 15.7% | - |
| tests/data/uspto/pg06442728.xml | xml | 39.6% | - |
| tests/data/uspto/tables_ipa20180000016.xml | xml | 95.0% | - |
| tests/data/xbrl/grve_10q_htm.xml | xml | 95.0% | - |
| tests/data/xbrl/mlac-20251231.xml | xml | 95.0% | - |

## Document-Level Data

Use the JSON reports in the same artifact for component scores, elapsed time, errors, regression review, and uplift review.
