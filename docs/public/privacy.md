# Privacy Policy

**Upmarket**
Effective date: 1 June 2026

---

## The short version

Upmarket processes your documents entirely on your Mac. Nothing you convert, paste, or drop is ever transmitted to a server. The app has no analytics, no crash reporting service, no advertising identifiers, and no account system.

---

## What Upmarket does not collect

- Document contents
- Extracted or converted text
- File names or file paths
- Passwords entered to unlock documents
- Usage events, session data, or behavioural analytics
- Advertising identifiers (IDFA or equivalent)
- Location data
- Contact information

---

## What Upmarket stores locally

Upmarket stores the following data on your Mac only:

| Data | Location | Purpose |
|---|---|---|
| Tour completion flag | `UserDefaults` | Prevents first-launch tour from repeating |
| Shelf anchor position | `UserDefaults` | Remembers shelf corner between launches |
| Free conversions remaining | `UserDefaults` | Tracks trial usage |
| Pack credit ledger | `~/Library/Application Support/Upmarket/PackCreditLedger.json` | Verifiable record of purchased and consumed document pack credits |
| Downloaded AI models | `~/Library/Application Support/Upmarket/models/` | On-device AI for complex document conversion |

None of this data leaves your device.

---

## Network access

Upmarket requests network access for three purposes only:

1. **AI model download.** When you choose to download optional AI models, the app fetches model files from their published source. No document data is included in this request.
2. **App Store and StoreKit.** Purchase verification, transaction history, and IAP restore use Apple's standard StoreKit 2 APIs. Upmarket does not operate its own payment server.
3. **Feature flags.** The app fetches a small public JSON file from GitHub Pages to check which features are enabled for your locale. The request contains no user data — it is a plain HTTP GET with no identifiers or parameters.

Conversion itself is always offline. The embedded AI runs entirely on your Mac and never makes network requests during document processing.

---

## Crash and diagnostic reports

Upmarket does not integrate any third-party crash reporting or analytics SDK (no Sentry, Crashlytics, or equivalent).

If your Mac is configured to share diagnostics with developers, Apple may collect crash reports on your behalf and make them available to the developer through Xcode Organizer. This is a standard macOS/TestFlight/App Store mechanism controlled by your system privacy settings and is subject to [Apple's privacy policy](https://www.apple.com/legal/privacy/). Upmarket does not receive document contents, file paths, or any conversion data through this channel.

If you use **Help > Report a Problem**, the app creates a local diagnostic bundle containing: app version, build number, macOS version, hardware class, locale, last conversion stage, error code, correlation identifier, and internal health check results for the app's configuration and model manifest. It does not include document contents, extracted text, passwords, or file paths. You review and approve the bundle before it is sent, and you choose whether to send it by email or not at all.

---

## Children

Upmarket is rated 4+ and is not directed at children. It does not knowingly collect any information from anyone.

---

## Changes to this policy

If this policy changes materially, the updated version will be posted at this URL with a revised effective date. Because Upmarket collects no data, changes are unlikely to affect you.

---

## Contact

Questions about this policy:
**ajmcardle@gmail.com**
