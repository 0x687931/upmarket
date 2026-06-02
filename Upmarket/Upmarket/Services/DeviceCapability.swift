import Foundation

/// Single source of truth for device capability checks.
/// All UI and service decisions about what to offer should read from here.
final class DeviceCapability {

    static let shared = DeviceCapability()

    /// True if running on Apple Silicon (M1 or later).
    /// Upmarket AI (Pro) requires Apple Silicon for on-device MLX inference.
    let isAppleSilicon: Bool

    /// True if macOS 26 (Tahoe) or later — enables GlassEffect APIs.
    let isTahoe: Bool

    /// Human-readable chip description for UI display.
    let chipDescription: String

    private init() {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) {
            $0.bindMemory(to: CChar.self).baseAddress
                .map { String(cString: $0) } ?? ""
        }
        isAppleSilicon = machine.hasPrefix("arm64")

        if #available(macOS 26, *) {
            isTahoe = true
        } else {
            isTahoe = false
        }

        chipDescription = isAppleSilicon ? "Apple Silicon" : "Intel"
    }

    /// Whether Upmarket AI (Pro tier) can run on this device.
    /// MLX is an Apple Silicon/Metal path, not a generic GPU path.
    var supportsUpmarketAI: Bool { isAppleSilicon }

    /// Why Upmarket AI is unavailable, for display in UI.
    var upmarketAIUnavailableReason: String {
        "Upmarket AI requires Apple Silicon with Metal support"
    }
}
