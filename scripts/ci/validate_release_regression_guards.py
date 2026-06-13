#!/usr/bin/env python3
"""Guard release-critical paths that have regressed before."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def require_text(path: str, needles: list[str], label: str, errors: list[str]) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    for needle in needles:
        require(
            needle in text,
            f"{label} must include {needle}",
            errors,
        )


def main() -> int:
    errors: list[str] = []

    builder = (ROOT / "scripts" / "build_python_env.sh").read_text(encoding="utf-8")
    require(
        'Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/$PYTHON_VERSION' in builder,
        "build_python_env.sh must rebuild the embedded Python.xcframework runtime",
        errors,
    )
    require(
        'SITE="$FRAMEWORK_ROOT/lib/python$PYTHON_VERSION/site-packages"' in builder,
        "build_python_env.sh must install dependencies into Python.xcframework site-packages",
        errors,
    )
    require(
        "python-stdlib" not in builder,
        "build_python_env.sh must not install into Upmarket/Python/python-stdlib",
        errors,
    )

    rc = (ROOT / ".github" / "workflows" / "release-candidate.yml").read_text(encoding="utf-8")
    require(
        'APP="$ARCHIVE_PATH/Products/Applications/Upmarket.app"' in rc,
        "release-candidate workflow must define the archived Upmarket.app path",
        errors,
    )
    require(
        'scripts/ci/verify_release_app.sh "$APP"' in rc,
        "release-candidate workflow must verify the archived app bundle",
        errors,
    )
    require(
        not re.search(r"smoke_convert_offline\.sh\s*(?:\n|$)", rc),
        "release-candidate workflow must not run offline smoke without an app bundle argument",
        errors,
    )

    vision = (ROOT / "Upmarket" / "Upmarket" / "Services" / "VisionOCR.swift").read_text(encoding="utf-8")
    require(
        "VisionProcessingLimits.renderSize(for: bounds, dpi: 150)" in vision,
        "VisionOCR must cap PDF render dimensions through VisionProcessingLimits before OCR",
        errors,
    )
    require(
        not re.search(r"let\s+scale\s*:\s*CGFloat\s*=\s*150\.0\s*/\s*72\.0", vision),
        "VisionOCR must not render PDF pages at uncapped raw 150 DPI",
        errors,
    )

    require_text(
        "Upmarket/UpmarketUITests/UpmarketUITests.swift",
        [
            "testPrimaryConversionWindowIsMounted",
            "PrimaryConversionView",
            "ChooseDocumentButton",
        ],
        "primary conversion UI regression test",
        errors,
    )
    require_text(
        "Upmarket/UpmarketTests/ConversionQueueTests.swift",
        [
            "testRejectedInputCreatesVisibleFailedJobWithoutRunningQueue",
            "testJobLookupKeepsTrackedPasswordJobSeparateFromLatestResult",
            "testTrackedRunningJobSurvivesAdjacentRejectedInputLatestResult",
            "testCancelRunningJobDoesNotOverlapSlowRunnerWithNextJob",
        ],
        "queue state regression tests",
        errors,
    )
    require_text(
        "Upmarket/UpmarketTests/StorageAccessTests.swift",
        [
            "testUnsupportedInputHasProductLevelError",
            "testTooLargeInputHasProductLevelError",
            "testQuickActionSupportedInputAdapterMatchesAppPolicy",
            "testAppIntentSupportedTypeAdapterMatchesAppPolicy",
        ],
        "input policy regression tests",
        errors,
    )
    require_text(
        "Upmarket/Upmarket/Domain/ToolFormatCapabilityMatrix.swift",
        [
            "case markItDown",
            ".mp3, .m4a, .wav",
            "requiresAdvancedRuntime",
            "requiresAuthorisation",
        ],
        "tool-format capability matrix",
        errors,
    )
    require_text(
        "Upmarket/UpmarketTests/ToolFormatCapabilityMatrixTests.swift",
        [
            "testAudioFormatsExposeAllValidRoutes",
            "tools.contains(.speech)",
            "tools.contains(.markItDown)",
            "tools.contains(.avFoundation)",
        ],
        "tool-format capability matrix tests",
        errors,
    )
    require_text(
        "Upmarket/UpmarketTests/ModelManagerTests.swift",
        [
            "testCheckFailureIsVisibleInstallFailure",
            "testEmptyModelCheckIsReadyFastPathNotFailure",
            "testDownloadProgressUpdatesBeforeCompletion",
        ],
        "model setup regression tests",
        errors,
    )
    require_text(
        "Upmarket/UpmarketTests/SupportReporterTests.swift",
        [
            "testReportPreviewIncludesRedactedDiagnostics",
            "Correlation ID: job-123",
            "[redacted path]",
            "private.pdf",
            "localizedCaseInsensitiveContains(\"docling\")",
        ],
        "support reporting regression tests",
        errors,
    )
    require_text(
        "Upmarket/Upmarket/Services/ConversionQueue.swift",
        [
            "PaywallWindowController.shared.show()",
            "shouldShowTrialPaywallAfterConversion()",
        ],
        "post-conversion paywall trigger regression guard",
        errors,
    )
    require_text(
        "Upmarket/UpmarketTests/StoreAccountingServiceTests.swift",
        [
            "testInitialStateDiscardsLegacyLocalCredits",
            "testDoesNotConsumeEditableFreeTrialOrPackCreditState",
            "testVerifiedPackTransactionsDoNotGrantBetaConversionCredits",
            "testTrialPaywallPromptWhenUnpaidAndNoCreditsRemaining",
            "testTrialPaywallPromptSuppressedWhenFreeDocsOrPackCreditsRemain",
        ],
        "local conversion-credit authority regression tests",
        errors,
    )
    require_text(
        "docs/release/corpus_expected_status.json",
        [
            '"degraded_output": 23',
            '"password_required": 1',
            '"success": 161',
            '"documents": [',
        ],
        "corpus expected-status ledger",
        errors,
    )
    require_text(
        "scripts/ci/summarize_corpus_pathway_reports.py",
        [
            "Unexpected Failed",
            "Expected Blocked",
            "Env Blocked",
            "normalised_status",
            "is_expected_blocked_error",
        ],
        "corpus pathway comparison failure accounting",
        errors,
    )
    require_text(
        "docs/release/TEST_MATRIX.md",
        [
            "Philosophy remediation",
            "validate_release_regression_guards.py",
            "UpmarketUITests/UpmarketUITests.swift",
        ],
        "release test matrix",
        errors,
    )
    require_text(
        "docs/release/RELEASE_PIPELINE.md",
        [
            "Philosophy remediation regression guards pass.",
            "scripts/ci/validate_release_regression_guards.py",
        ],
        "release pipeline",
        errors,
    )

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("ok: release regression guards hold")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
