#!/usr/bin/env python3
import os
import sys
import tempfile
import base64
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "UpmarketPython"))


def reset_converter_preflight(converter) -> None:
    converter._AI_RUNTIME_PRECHECK = None


def convert_fixture(converter, root: Path) -> dict:
    fixture = root / "sample.png"
    fixture.write_bytes(base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC"
    ))
    os.environ["UPMARKET_ALLOWED_INPUT_ROOTS"] = str(root)
    return converter.convert(str(fixture), {"use_ai": True})


def main() -> int:
    from docling_bridge import converter

    os.environ["UPMARKET_ENABLE_TEST_DOUBLES"] = "1"
    os.environ["UPMARKET_TEST_UPMARKET_AI_CONVERTER"] = "stub"

    with tempfile.TemporaryDirectory(prefix="upmarket-ai-runtime-doubles-") as temp:
        root = Path(temp)

        os.environ["UPMARKET_TEST_UPMARKET_AI_HARDWARE"] = "available"
        os.environ["UPMARKET_TEST_UPMARKET_AI_RUNTIME"] = "available"
        reset_converter_preflight(converter)
        result = convert_fixture(converter, root)
        if not result["success"] or result["pipeline"] != "ai":
            raise AssertionError(f"AI available stub did not succeed: {result}")

        os.environ["UPMARKET_TEST_UPMARKET_AI_HARDWARE"] = "unavailable"
        os.environ["UPMARKET_TEST_UPMARKET_AI_RUNTIME"] = "available"
        reset_converter_preflight(converter)
        result = convert_fixture(converter, root)
        if result["success"] or "Apple Silicon with Metal" not in result["error"]:
            raise AssertionError(f"AI hardware-unavailable stub did not block: {result}")

        os.environ["UPMARKET_TEST_UPMARKET_AI_HARDWARE"] = "available"
        os.environ["UPMARKET_TEST_UPMARKET_AI_RUNTIME"] = "unavailable"
        reset_converter_preflight(converter)
        result = convert_fixture(converter, root)
        if result["success"] or "graphics processor" not in result["error"]:
            raise AssertionError(f"AI runtime-unavailable stub did not block: {result}")

    print("ok: AI runtime test doubles cover available and unavailable hosts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
