import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import idl_eval


class IDLEvalTests(unittest.TestCase):
    def test_picture_only_markdown_has_no_meaningful_words(self):
        self.assertEqual(idl_eval.meaningful_word_count("<!-- image -->"), 0)
        self.assertEqual(
            idl_eval.meaningful_word_count("![ Image Description](image_url)"),
            0,
        )
        self.assertGreater(idl_eval.meaningful_word_count("# Invoice\nTotal: $42"), 0)

    def test_picture_only_success_is_recorded_as_model_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pdf = root / "poster.pdf"
            pdf.touch()
            (root / "poster.gt.txt").write_text("visible poster text", encoding="utf-8")

            def convert(*_args, **_kwargs):
                (root / "poster.granite.md").write_text("<!-- image -->", encoding="utf-8")
                return SimpleNamespace(returncode=0, stderr="")

            with patch.object(idl_eval, "CORPUS", root), patch.object(
                idl_eval.subprocess,
                "run",
                side_effect=convert,
            ):
                row = idl_eval.score_one(
                    pdf,
                    engine="",
                    ai_engine="granite",
                    eng="granite",
                    cli="/tmp/upmarket-cli",
                    timeout=10,
                )

            self.assertEqual(row["status"], idl_eval.LOW_CONTENT_STATUS)
            self.assertIn("image placeholders", row["error"])

    def test_sample_manifest_is_shared_and_stable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pdfs = []
            for key in ("a", "b", "c", "d", "e"):
                pdf = root / f"{key}.pdf"
                pdf.touch()
                pdfs.append(pdf)

            manifest = root / "sample.json"
            with patch.object(idl_eval, "CORPUS", root), patch.dict(
                idl_eval.os.environ,
                {"IDL_SAMPLE_MANIFEST": str(manifest)},
            ):
                granite = idl_eval.sampled_pdfs(pdfs, 3)
                lfm2 = idl_eval.sampled_pdfs(list(reversed(pdfs)), 3)

            self.assertEqual([pdf.stem for pdf in granite], [pdf.stem for pdf in lfm2])
            saved = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(saved["keys"], [pdf.stem for pdf in granite])
            self.assertEqual(saved["sample_size"], 3)

    def test_resume_rechecks_legacy_low_content_but_keeps_model_failure_terminal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            results = root / "results.jsonl"
            (root / "legacy.granite.md").write_text("<!-- image -->", encoding="utf-8")
            (root / "classified.granite.md").write_text("<!-- image -->", encoding="utf-8")
            results.write_text(
                "\n".join(
                    [
                        json.dumps(
                            {
                                "key": "legacy",
                                "engine": "granite",
                                "status": "ok",
                            }
                        ),
                        json.dumps(
                            {
                                "key": "classified",
                                "engine": "granite",
                                "status": idl_eval.LOW_CONTENT_STATUS,
                            }
                        ),
                    ]
                ),
                encoding="utf-8",
            )

            with patch.object(idl_eval, "CORPUS", root), patch.object(
                idl_eval,
                "RESULTS",
                results,
            ):
                done = idl_eval.scored_keys("granite")

            self.assertNotIn("legacy", done)
            self.assertIn("classified", done)

    def test_sample_manifest_is_applied_before_resume_filtering(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pdfs = []
            for key in ("a", "b", "c", "d"):
                pdf = root / f"{key}.pdf"
                pdf.touch()
                pdfs.append(pdf)

            manifest = root / "sample.json"
            manifest.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "sample_size": 2,
                        "corpus_size": 4,
                        "seed": 0,
                        "keys": ["b", "d"],
                    }
                ),
                encoding="utf-8",
            )
            with patch.dict(
                idl_eval.os.environ,
                {"IDL_SAMPLE_MANIFEST": str(manifest)},
            ):
                selected = idl_eval.sampled_pdfs(pdfs, 2)

            granite_done = {"b"}
            lfm2_done = set()
            self.assertEqual(
                [pdf.stem for pdf in selected if pdf.stem not in granite_done],
                ["d"],
            )
            self.assertEqual(
                [pdf.stem for pdf in selected if pdf.stem not in lfm2_done],
                ["b", "d"],
            )


if __name__ == "__main__":
    unittest.main()
