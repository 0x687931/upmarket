#!/usr/bin/env python3
"""
Prepare HuggingFace dataset manifests from pixparse datasets.

This script extracts a stratified sample from each dataset and generates
manifest.json files compatible with the existing corpus validation infrastructure.

Usage:
  python3 scripts/datasets/prepare_hf_corpus.py --dataset all --sample 200 --seed 42
  python3 scripts/datasets/prepare_hf_corpus.py --dataset pdfa --sample 150 --seed 42
"""

import argparse
import json
import os
import random
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import pdfplumber
    import webdataset as wds
except ImportError:
    print("Error: required packages not installed.")
    print("Install with: pip install webdataset pdfplumber")
    sys.exit(1)


class HFDatasetProcessor:
    """Process HuggingFace datasets and generate manifests."""

    def __init__(self, datasets_dir: Path, manifest_dir: Path):
        self.datasets_dir = datasets_dir
        self.manifest_dir = manifest_dir
        self.manifest_dir.mkdir(parents=True, exist_ok=True)

    def process_pdfa(self, sample_size: int, seed: int) -> None:
        """Process PDFA dataset: extract PDFs and embedded text ground truth."""
        dataset_path = self.datasets_dir / "pdfa-eng-wds"
        if not dataset_path.exists():
            print(f"⚠️  {dataset_path} not found, skipping PDFA")
            return

        print("📄 Processing PDFA-eng-wds...")
        manifest = []
        documents = []

        # Scan for tar shards
        tar_files = sorted(dataset_path.glob("*.tar"))
        if not tar_files:
            print("   ⚠️  No .tar shards found")
            return

        # Collect document metadata from all shards
        for tar_file in tar_files[:5]:  # Limit to first 5 shards for speed
            try:
                with tarfile.open(tar_file, 'r') as tf:
                    members = tf.getmembers()
                    # Group by document ID (webdataset format: 00000.pdf, 00000.json, etc.)
                    doc_ids = set()
                    for member in members:
                        if member.name.endswith('.pdf'):
                            doc_id = member.name.split('.')[0]
                            doc_ids.add(doc_id)

                    for doc_id in sorted(doc_ids):
                        pdf_member = next((m for m in members if m.name == f"{doc_id}.pdf"), None)
                        json_member = next((m for m in members if m.name == f"{doc_id}.json"), None)

                        if pdf_member:
                            documents.append({
                                'id': f"hf-pdfa-{doc_id}",
                                'tar_file': tar_file,
                                'pdf_member': pdf_member,
                                'json_member': json_member,
                            })
            except Exception as e:
                print(f"   ⚠️  Error reading {tar_file}: {e}")
                continue

        if not documents:
            print("   ⚠️  No documents found")
            return

        # Stratified sample
        random.seed(seed)
        sampled = random.sample(documents, min(sample_size, len(documents)))
        sampled.sort(key=lambda x: x['id'])

        # Extract and build manifest
        extract_dir = self.datasets_dir / "pdfa-eng-wds-extracted"
        extract_dir.mkdir(exist_ok=True)

        for doc in sampled:
            doc_id = doc['id']
            print(f"   Extracting {doc_id}...", end=" ", flush=True)

            try:
                # Extract PDF
                with tarfile.open(doc['tar_file'], 'r') as tf:
                    pdf_member = doc['pdf_member']
                    json_member = doc['json_member']

                    # Extract PDF to temp file and get embedded text
                    with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as tmp:
                        tf.extract(pdf_member, path=tempfile.gettempdir())
                        extracted_pdf = Path(tempfile.gettempdir()) / pdf_member.name

                        # Extract embedded text using pdfplumber
                        embedded_text = ""
                        try:
                            with pdfplumber.open(extracted_pdf) as pdf:
                                for page in pdf.pages:
                                    embedded_text += page.extract_text() or ""
                                    embedded_text += "\n"
                        except Exception:
                            pass

                        # Save ground truth
                        gt_file = extract_dir / f"{doc_id}.expected.txt"
                        gt_file.write_text(embedded_text, encoding='utf-8')

                        # Copy PDF to extract_dir
                        pdf_dest = extract_dir / f"{doc_id}.pdf"
                        extracted_pdf.rename(pdf_dest)

                    # Extract metadata JSON
                    metadata = {}
                    if json_member:
                        tf.extract(json_member, path=tempfile.gettempdir())
                        extracted_json = Path(tempfile.gettempdir()) / json_member.name
                        try:
                            metadata = json.loads(extracted_json.read_text())
                        except Exception:
                            pass

                # Add to manifest
                manifest.append({
                    "id": doc_id,
                    "file": f"tests/datasets/pdfa-eng-wds-extracted/{doc_id}.pdf",
                    "ground_truth": f"tests/datasets/pdfa-eng-wds-extracted/{doc_id}.expected.txt",
                    "category": "pdf",
                    "format": "PDF",
                    "expected_features": {
                        "headings": 0,
                        "tables": metadata.get('table_count', 0),
                        "estimated_words": len(embedded_text.split())
                    },
                    "bucket": "digital-complex"
                })
                print("✓")
            except Exception as e:
                print(f"✗ ({e})")
                continue

        # Write manifest
        manifest_file = self.manifest_dir / "hf_pdfa_manifest.json"
        manifest_file.write_text(json.dumps(manifest, indent=2))
        print(f"   ✓ Manifest: {len(manifest)} documents → {manifest_file}")

    def process_idl(self, sample_size: int, seed: int) -> None:
        """Process IDL dataset: scanned industrial documents (no GT)."""
        dataset_path = self.datasets_dir / "idl-wds"
        if not dataset_path.exists():
            print(f"⚠️  {dataset_path} not found, skipping IDL")
            return

        print("📊 Processing IDL-wds...")
        manifest = []
        documents = []

        # Scan for image files
        for ext in ['*.jpg', '*.png', '*.tiff']:
            documents.extend(dataset_path.glob(f"**/{ext}"))

        if not documents:
            print("   ⚠️  No images found")
            return

        # Sample
        random.seed(seed)
        sampled = random.sample(documents, min(sample_size, len(documents)))
        sampled.sort()

        extract_dir = self.datasets_dir / "idl-wds-extracted"
        extract_dir.mkdir(exist_ok=True)

        for idx, doc_path in enumerate(sampled):
            doc_id = f"hf-idl-{idx:06d}"
            print(f"   {doc_id}: {doc_path.name}...", end=" ", flush=True)

            try:
                # Copy to extract dir
                dest = extract_dir / f"{doc_id}{doc_path.suffix}"
                if not dest.exists():
                    dest.write_bytes(doc_path.read_bytes())

                manifest.append({
                    "id": doc_id,
                    "file": f"tests/datasets/idl-wds-extracted/{doc_id}{doc_path.suffix}",
                    "ground_truth": None,
                    "category": "image",
                    "format": "TIFF" if doc_path.suffix.lower() == '.tiff' else "JPEG",
                    "expected_features": {
                        "headings": 0,
                        "tables": 0,
                        "estimated_words": 0
                    },
                    "bucket": "scanned-or-unknown"
                })
                print("✓")
            except Exception as e:
                print(f"✗ ({e})")
                continue

        # Write manifest
        manifest_file = self.manifest_dir / "hf_idl_manifest.json"
        manifest_file.write_text(json.dumps(manifest, indent=2))
        print(f"   ✓ Manifest: {len(manifest)} documents → {manifest_file}")

    def process_docvqa(self, sample_size: int, seed: int) -> None:
        """Process DocVQA dataset: document images with Q&A pairs."""
        dataset_path = self.datasets_dir / "docvqa-wds"
        if not dataset_path.exists():
            print(f"⚠️  {dataset_path} not found, skipping DocVQA")
            return

        print("❓ Processing DocVQA-wds...")
        manifest = []
        documents = []

        # Scan for image/json pairs
        for img_path in sorted(dataset_path.glob("**/*.png")):
            json_path = img_path.with_suffix('.json')
            if json_path.exists():
                documents.append((img_path, json_path))

        if not documents:
            print("   ⚠️  No document/annotation pairs found")
            return

        # Sample
        random.seed(seed)
        sampled = random.sample(documents, min(sample_size, len(documents)))
        sampled.sort(key=lambda x: x[0].name)

        extract_dir = self.datasets_dir / "docvqa-wds-extracted"
        extract_dir.mkdir(exist_ok=True)

        for idx, (img_path, json_path) in enumerate(sampled):
            doc_id = f"hf-docvqa-{idx:06d}"
            print(f"   {doc_id}...", end=" ", flush=True)

            try:
                # Load annotation
                annotation = json.loads(json_path.read_text())
                qa_pairs = annotation.get('qa', [])

                # Copy image
                dest_img = extract_dir / f"{doc_id}.png"
                if not dest_img.exists():
                    dest_img.write_bytes(img_path.read_bytes())

                manifest.append({
                    "id": doc_id,
                    "file": f"tests/datasets/docvqa-wds-extracted/{doc_id}.png",
                    "ground_truth": None,
                    "category": "image",
                    "format": "PNG",
                    "expected_features": {
                        "headings": 0,
                        "tables": 0,
                        "estimated_words": 0,
                        "qa_count": len(qa_pairs)
                    },
                    "expected_qa": [
                        {"question": qa.get('question'), "answer": qa.get('answer')}
                        for qa in qa_pairs
                    ]
                })
                print("✓")
            except Exception as e:
                print(f"✗ ({e})")
                continue

        # Write manifest
        manifest_file = self.manifest_dir / "hf_docvqa_manifest.json"
        manifest_file.write_text(json.dumps(manifest, indent=2))
        print(f"   ✓ Manifest: {len(manifest)} documents → {manifest_file}")


def main():
    parser = argparse.ArgumentParser(description="Prepare HuggingFace dataset manifests")
    parser.add_argument('--dataset', choices=['pdfa', 'idl', 'docvqa', 'all'], default='all',
                        help='Which dataset(s) to process')
    parser.add_argument('--sample', type=int, default=200,
                        help='Number of documents to sample from each dataset')
    parser.add_argument('--seed', type=int, default=42,
                        help='Random seed for reproducible sampling')

    args = parser.parse_args()

    repo_root = Path(__file__).parent.parent.parent
    datasets_dir = repo_root / "tests" / "datasets" / "huggingface"
    manifest_dir = repo_root / "tests" / "datasets" / "manifests"

    processor = HFDatasetProcessor(datasets_dir, manifest_dir)

    if args.dataset in ('pdfa', 'all'):
        processor.process_pdfa(args.sample, args.seed)

    if args.dataset in ('idl', 'all'):
        processor.process_idl(args.sample, args.seed)

    if args.dataset in ('docvqa', 'all'):
        processor.process_docvqa(args.sample, args.seed)

    print("\n✅ Manifest preparation complete!")


if __name__ == "__main__":
    main()
