# Upmarket

**Convert any document to Markdown — fully offline, on-device AI.**

Upmarket is a macOS app that converts PDFs, Word documents, PowerPoints, and more into clean Markdown using on-device AI. No cloud, no subscriptions, no API keys. Your documents never leave your Mac.

## The Name

A triple pun: Markdown was invented as the opposite of HTML *markup* (mark**down** vs mark**up**). Upmarket takes that further — converting *up* from raw formats into the clean Markdown standard, while aiming to be an *upmarket* (premium) product.

## Architecture

```
SwiftUI (UI layer)
    ↓
Embedded CPython via BeeWare Python-Apple-support
    ↓
Docling + MLX + PyTorch/MPS
    ↓
ML models cached locally (downloaded on first use)
    ↓
Runs 100% offline on Apple Silicon via Metal
```

## Supported Formats

- PDF (programmatic + scanned via OCR)
- DOCX / Word
- PPTX / PowerPoint
- XLSX / Excel
- HTML
- Images (PNG, JPG)

## ML Models

| Model | Purpose | Size | Backend |
|---|---|---|---|
| Heron (RT-DETRv2) | Layout detection | ~200MB | PyTorch/MPS |
| TableFormer | Table structure | ~100MB | PyTorch/MPS |
| SmolDocling (optional) | VLM document understanding | ~500MB | MLX |

Models are downloaded on first use and cached in `~/Library/Application Support/Upmarket/models/`.

## Requirements

- macOS Ventura 13.3+
- Apple Silicon (M1 or later) recommended
- Intel Mac supported (CPU inference only)

## Development

See [IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for the full technical plan and [USER_FLOW.md](docs/USER_FLOW.md) for the app journey.

### Project Structure

```
Upmarket/Upmarket.xcodeproj/ # Xcode project
Upmarket/Upmarket/       # SwiftUI app source
  Views/                 # SwiftUI views
  Services/              # App services, window controllers, Python bridge
  Intents/               # App Intents
  Resources/             # App resources and localized strings
Upmarket/UpmarketTests/  # Xcode-managed unit tests
Upmarket/UpmarketUITests/# Xcode-managed UI tests
Upmarket/Python/         # Bundled CPython runtime support
UpmarketPython/         # Python layer
  docling_bridge/       # Python wrapper around Docling
  models/               # Model download utilities
scripts/                # Build and setup scripts
docs/                   # Documentation
```

## License

MIT
