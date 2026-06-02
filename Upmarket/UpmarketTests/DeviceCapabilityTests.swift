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

    private func currentMachineIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) {
            $0.bindMemory(to: CChar.self).baseAddress
                .map { String(cString: $0) } ?? ""
        }
    }
}
