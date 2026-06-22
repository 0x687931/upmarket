import Foundation
import Metal

/// Single source of truth for device capability checks.
/// All UI and service decisions about what to offer should read from here.
final class DeviceCapability {

    nonisolated static let shared = DeviceCapability()

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
        currentIsAppleSilicon() && currentHasMetalDevice()
    }

    private nonisolated static func currentIsAppleSilicon() -> Bool {
        if let override = testBoolOverride("UPMARKET_TEST_UPMARKET_AI_HARDWARE") {
            return override
        }
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
        if let override = testBoolOverride("UPMARKET_TEST_UPMARKET_AI_HARDWARE") {
            return override
        }
        return MTLCreateSystemDefaultDevice() != nil
    }

    private nonisolated static func testBoolOverride(_ name: String) -> Bool? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["UPMARKET_ENABLE_TEST_DOUBLES"] == "1",
              let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        if ["1", "true", "yes", "available", "supported"].contains(value) {
            return true
        }
        if ["0", "false", "no", "unavailable", "unsupported"].contains(value) {
            return false
        }
        return nil
    }

    /// Whether Upmarket AI (Pro tier) can run on this device.
    /// MLX is an Apple Silicon/Metal path, not a generic GPU path.
    nonisolated var supportsUpmarketAI: Bool { isAppleSilicon && hasMetalDevice }

    /// Whether the advanced native engines (Granite-Docling mlx-swift, Vision banding)
    /// can run on this device. They are an Apple Silicon + Metal path.
    nonisolated var supportsAdvancedRuntime: Bool {
        isAppleSilicon && hasMetalDevice
    }

    /// Why Upmarket AI is unavailable, for display in UI.
    nonisolated var graniteDoclingUnavailableReason: String {
        "Upmarket AI requires Apple Silicon with Metal support"
    }
}
