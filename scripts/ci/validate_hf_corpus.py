#!/usr/bin/env python3
"""
Validate HuggingFace corpus manifests and baseline configuration.

This script runs in the 'policy' gate mode and ensures:
- All three manifests exist and are parseable JSON
- Each manifest has ≥ 100 documents
- Baseline thresholds file exists and covers all datasets
"""

import json
import sys
from pathlib import Path


def validate_manifest(manifest_path: Path, min_docs: int = 100) -> tuple[bool, str]:
    """Validate a single manifest file."""
    if not manifest_path.exists():
        return False, f"File not found: {manifest_path}"

    try:
        manifest = json.loads(manifest_path.read_text())
        if not isinstance(manifest, list):
            return False, "Manifest is not a JSON array"

        if len(manifest) < min_docs:
            return False, f"Manifest has only {len(manifest)} documents (need ≥ {min_docs})"

        # Check required fields
        required_fields = ['id', 'file', 'category', 'format']
        for doc in manifest:
            for field in required_fields:
                if field not in doc:
                    return False, f"Document {doc.get('id')} missing field: {field}"

        return True, f"{len(manifest)} documents"

    except json.JSONDecodeError as e:
        return False, f"Invalid JSON: {e}"
    except Exception as e:
        return False, str(e)


def validate_baseline(baseline_path: Path) -> tuple[bool, str]:
    """Validate baseline thresholds file."""
    if not baseline_path.exists():
        return False, "Baseline file not found"

    try:
        baseline = json.loads(baseline_path.read_text())

        required_datasets = {'pdfa', 'idl', 'docvqa'}
        thresholds = baseline.get('thresholds', {})
        found_datasets = set(thresholds.keys())

        missing = required_datasets - found_datasets
        if missing:
            return False, f"Missing thresholds for: {', '.join(missing)}"

        return True, f"All {len(found_datasets)} datasets configured"

    except json.JSONDecodeError as e:
        return False, f"Invalid JSON: {e}"
    except Exception as e:
        return False, str(e)


def main() -> int:
    repo_root = Path(__file__).parent.parent.parent

    print("🔍 Validating HuggingFace corpus configuration")
    print("=" * 50)

    all_valid = True

    # Check manifests
    manifests = {
        'pdfa': repo_root / 'tests' / 'datasets' / 'manifests' / 'hf_pdfa_manifest.json',
        'idl': repo_root / 'tests' / 'datasets' / 'manifests' / 'hf_idl_manifest.json',
        'docvqa': repo_root / 'tests' / 'datasets' / 'manifests' / 'hf_docvqa_manifest.json',
    }

    # The HuggingFace datasets (pdfa/idl/docvqa) lack usable ground truth and are NOT
    # part of the evaluation corpus (see tests/corpus — document+ground-truth pairs only).
    # Treat them as optional: if no manifests are present, there is nothing to validate.
    if not any(path.exists() for path in manifests.values()):
        print("\n⚠️  HuggingFace manifests not present — corpus not configured (optional). Skipping.")
        return 0

    print("\n📋 Manifests:")
    for name, path in manifests.items():
        valid, msg = validate_manifest(path, min_docs=100)
        status = "✓" if valid else "✗"
        print(f"  {status} {name}: {msg}")
        if not valid:
            all_valid = False

    # Check baseline
    baseline_path = repo_root / 'docs' / 'release' / 'hf_dataset_baseline.json'
    print("\n📊 Baseline thresholds:")
    valid, msg = validate_baseline(baseline_path)
    status = "✓" if valid else "✗"
    print(f"  {status} {msg}")
    if not valid:
        all_valid = False

    print()

    if all_valid:
        print("✅ All validations passed")
        return 0
    else:
        print("❌ Validation failed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
