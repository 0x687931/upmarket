import Foundation
import Metal

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

    private let hasMetalDevice: Bool

    private init() {
        isAppleSilicon = Self.currentIsAppleSilicon()
        hasMetalDevice = Self.currentHasMetalDevice()

        if #available(macOS 26, *) {
            isTahoe = true
        } else {
            isTahoe = false
        }

        chipDescription = isAppleSilicon ? "Apple Silicon" : "Intel"
    }

    nonisolated static var currentSupportsAdvancedRuntime: Bool {
        currentIsAppleSilicon()
    }

    private nonisolated static func currentIsAppleSilicon() -> Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) {
            $0.bindMemory(to: CChar.self).baseAddress
                .map { String(cString: $0) } ?? ""
        }
        return machine.hasPrefix("arm64")
    }

    nonisolated static var currentSupportsUpmarketAI: Bool {
        currentIsAppleSilicon() && currentHasMetalDevice()
    }

    nonisolated static func currentHasMetalDevice() -> Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    /// Whether Upmarket AI (Pro tier) can run on this device.
    /// MLX is an Apple Silicon/Metal path, not a generic GPU path.
    nonisolated var supportsUpmarketAI: Bool { isAppleSilicon && hasMetalDevice }

    /// Whether bundled advanced conversion should run on this device.
    /// v1.0 keeps Intel Macs on native-only Basic conversion until physical
    /// Intel validation proves the packaged runtime is reliable there.
    nonisolated var supportsAdvancedRuntime: Bool { isAppleSilicon }

    /// Why Upmarket AI is unavailable, for display in UI.
    nonisolated var upmarketAIUnavailableReason: String {
        "Upmarket AI requires Apple Silicon with Metal support"
    }
}
