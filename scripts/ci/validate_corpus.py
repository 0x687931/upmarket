#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def resolve(corpus: Path, rel: str) -> Path | None:
    # Manifest paths are repo-root-relative (Document + GroundTruth schema); fall back to
    # corpus-relative for any legacy entries.
    candidates = [
        Path(rel),
        corpus / rel,
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def main() -> int:
    corpus = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("tests/corpus")
    manifest = corpus / "manifest.json"

    if not manifest.exists():
        print(f"error: corpus manifest missing: {manifest}")
        return 1

    data = json.loads(manifest.read_text())
    docs = data.get("documents", [])
    if not isinstance(docs, list) or not docs:
        print("error: corpus manifest has no documents")
        return 1

    failed = False
    ids: set[str] = set()
    for doc in docs:
        doc_id = doc.get("id")
        if not doc_id:
            print("error: corpus document missing id")
            failed = True
            continue
        if doc_id in ids:
            print(f"error: duplicate corpus id: {doc_id}")
            failed = True
        ids.add(doc_id)

        rel_file = doc.get("document")
        if not rel_file or resolve(corpus, rel_file) is None:
            print(f"error: corpus file missing for {doc_id}: {rel_file}")
            failed = True

        rel_gt = doc.get("ground_truth")
        if rel_gt and resolve(corpus, rel_gt) is None:
            print(f"error: ground truth missing for {doc_id}: {rel_gt}")
            failed = True

    if failed:
        return 1

    print(f"ok: corpus manifest valid ({len(docs)} documents)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
