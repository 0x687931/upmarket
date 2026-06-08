import Metal
import XCTest
@testable import Upmarket

final class DeviceCapabilityTests: XCTestCase {

    func testUpmarketAIAvailabilityRequiresAppleSiliconAndMetalDevice() {
        let machine = currentMachineIdentifier()
        let isAppleSilicon = machine.hasPrefix("arm64")
        let metalDevice = MTLCreateSystemDefaultDevice()
        let expected = isAppleSilicon && metalDevice != nil

        XCTAssertEqual(DeviceCapability.shared.supportsUpmarketAI, expected)
        XCTAssertEqual(DeviceCapability.currentSupportsUpmarketAI, expected)
        XCTAssertEqual(DeviceCapability.currentHasMetalDevice(), metalDevice != nil)

        if isAppleSilicon {
            XCTAssertNotNil(metalDevice, "Apple Silicon Upmarket AI availability requires a visible Metal device.")
        }
    }

    func testUpmarketAITestDoubleCanSimulateMetalAndNonMetalHosts() {
        setenv("UPMARKET_ENABLE_TEST_DOUBLES", "1", 1)
        defer {
            unsetenv("UPMARKET_ENABLE_TEST_DOUBLES")
            unsetenv("UPMARKET_TEST_UPMARKET_AI_HARDWARE")
        }

        setenv("UPMARKET_TEST_UPMARKET_AI_HARDWARE", "available", 1)
        XCTAssertTrue(DeviceCapability.currentSupportsUpmarketAI)
        XCTAssertTrue(DeviceCapability.currentHasMetalDevice())

        setenv("UPMARKET_TEST_UPMARKET_AI_HARDWARE", "unavailable", 1)
        XCTAssertFalse(DeviceCapability.currentSupportsUpmarketAI)
        XCTAssertFalse(DeviceCapability.currentHasMetalDevice())
    }

    private func currentMachineIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) {
            $0.bindMemory(to: CChar.self).baseAddress
                .map { String(cString: $0) } ?? ""
        }
    }
}
