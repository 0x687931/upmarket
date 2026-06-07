# Upmarket AI Language Flag Policy

Last reviewed: 2026-06-05

Feature flags control Upmarket AI availability for the shipped macOS pipeline. They are not a mirror of every upstream model or OCR-engine capability.

## Evidence Sources

Use primary sources only:

- Granite Docling model card: `https://huggingface.co/ibm-granite/granite-docling-258M`
  - `Language(s): English (NLP)`
  - Japanese, Arabic, and Chinese support is listed as experimental.
  - Model license is Apache 2.0.
- IBM Granite Docling docs: `https://www.ibm.com/granite/docs/models/docling`
  - The model is optimized for Latin-script documents.
  - Japanese, Chinese, and Arabic are described as early support.
- Docling OCR FAQ: `https://docling-project.github.io/docling/faq/#which-ocr-languages-are-supported`
  - OCR language support depends on the selected OCR engine.
  - OCR language selection is configured with pipeline OCR options.
- Docling repository: `https://github.com/docling-project/docling`
  - Docling codebase is MIT licensed.
  - Individual model licenses still apply.

## Flag Tiers

`ai_supported_locales`

- Means Upmarket has validated the shipped app path for that locale.
- Requires language-specific fixtures, signed macOS release build testing, and acceptable output quality.
- Upstream claims alone are not enough.

`ai_experimental_locales`

- Means a primary upstream source makes an explicit early/experimental claim, but Upmarket has not validated beta quality yet.
- The UI may say Upmarket AI is coming soon for these locales.

Unlisted locales

- No credible shipped-app support claim.
- The UI should say Upmarket AI is not yet available.

## Initial Beta Flags

Use this for the CloudKit public record `FeatureFlags/global`:

```json
{
  "ai_supported_locales": ["en"],
  "ai_experimental_locales": ["ar", "ja", "zh"],
  "version": 1
}
```

Rationale:

- English is the only language explicitly listed as the Granite Docling NLP language.
- Arabic, Japanese, and Chinese are explicitly listed by Granite Docling as experimental or early support.
- Other Latin-script languages may be plausible because of the IBM Latin-script optimization statement or classic Docling OCR engines, but they are not Upmarket-supported until our shipped Granite Docling MLX path passes validation.

## Promotion Rule

Move a locale from `ai_experimental_locales` to `ai_supported_locales` only after:

1. Add or identify representative fixtures for that language.
2. Run the Upmarket AI path on Apple Silicon using the same pinned app/runtime/model versions intended for beta.
3. Confirm output quality for text, reading order, tables, and math/code where applicable.
4. Record the evidence in the release notes or validation report.
5. Update the CloudKit production record and bump `version`.

## Claim Rule

Upmarket may cite upstream capability claims in internal release docs, license/attribution material, and technical diagnostics. User-facing product copy must describe Upmarket's validated behavior, not upstream potential.
