import XCTest
@testable import FloatingPhoto

final class FloatingPhotoConfigurationTests: XCTestCase {
    func testConfigurationClampsUnsafeValues() {
        let configuration = FloatingPhotoConfiguration(
            intensity: -1,
            maximumTilt: 0,
            backgroundBlur: -2,
            backgroundScale: 0,
            foregroundDepth: -1,
            backgroundDepth: -1
        )

        XCTAssertEqual(configuration.intensity, 0)
        XCTAssertGreaterThan(configuration.maximumTilt, 0)
        XCTAssertEqual(configuration.backgroundBlur, 0)
        XCTAssertGreaterThanOrEqual(configuration.backgroundScale, 1)
        XCTAssertEqual(configuration.foregroundDepth, 0)
        XCTAssertEqual(configuration.backgroundDepth, 0)
    }
}
