@testable import NVitalCore
import XCTest

final class BatteryEvaluationTests: XCTestCase {
    private func reading(cycles: Int? = 200, design: Int? = 5000, full: Int? = 4800,
                         failure: Bool = false, condition: String? = nil) -> BatteryTest.Reading {
        return BatteryTest.Reading(cycleCount: cycles, designCapacity: design, fullChargeCapacity: full,
                                   chargePercent: 80, isCharging: false, permanentFailure: failure,
                                   healthCondition: condition)
    }

    func testHealthyBatteryPasses() {
        XCTAssertEqual(BatteryTest.evaluate(reading()).status, .passed)
    }

    func testWornBatteryWarns() {
        XCTAssertEqual(BatteryTest.evaluate(reading(full: 3800)).status, .warning)
    }

    func testDeadBatteryFails() {
        XCTAssertEqual(BatteryTest.evaluate(reading(full: 2500)).status, .failed)
    }

    func testPermanentFailureFails() {
        XCTAssertEqual(BatteryTest.evaluate(reading(failure: true)).status, .failed)
        XCTAssertEqual(BatteryTest.evaluate(reading(condition: "Permanent Battery Failure")).status, .failed)
    }

    func testServiceConditionWarns() {
        XCTAssertEqual(BatteryTest.evaluate(reading(condition: "Check Battery")).status, .warning)
    }

    func testHighCycleCountWarns() {
        XCTAssertEqual(BatteryTest.evaluate(reading(cycles: 1200)).status, .warning)
    }

    func testUnknownCapacityWarns() {
        XCTAssertEqual(BatteryTest.evaluate(reading(design: nil)).status, .warning)
    }
}

final class KeyboardEvaluationTests: XCTestCase {
    func testAllRequiredKeysPass() {
        let keys = KeyboardTest.laptopKeys
        let required = Set(keys.filter { $0.isRequired }.map { $0.keyCode })
        XCTAssertEqual(KeyboardTest.evaluate(pressed: required, keys: keys).status, .passed)
    }

    func testMissingKeyFailsAndIsListed() {
        let keys = KeyboardTest.laptopKeys
        var pressed = Set(keys.map { $0.keyCode })
        pressed.remove(0x00) // A
        let outcome = KeyboardTest.evaluate(pressed: pressed, keys: keys)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertTrue(outcome.measurements.contains { $0.value.contains("A") })
    }

    func testKeyCodesAreUnique() {
        let codes = KeyboardTest.laptopKeys.map { $0.keyCode }
        XCTAssertEqual(codes.count, Set(codes).count)
    }
}

final class TrackpadEvaluationTests: XCTestCase {
    func testFullUsePasses() {
        let result = TrackpadCaptureResult(visitedCells: 40, totalCells: 40, primaryClick: true,
                                           secondaryClick: true, scrolled: true, pinched: true)
        XCTAssertEqual(TrackpadTest.evaluate(result).status, .passed)
    }

    func testDeadZoneFails() {
        let result = TrackpadCaptureResult(visitedCells: 30, totalCells: 40, primaryClick: true,
                                           secondaryClick: true, scrolled: true, pinched: true)
        XCTAssertEqual(TrackpadTest.evaluate(result).status, .failed)
    }

    func testMissingGestureWarns() {
        let result = TrackpadCaptureResult(visitedCells: 40, totalCells: 40, primaryClick: true,
                                           secondaryClick: false, scrolled: true, pinched: true)
        XCTAssertEqual(TrackpadTest.evaluate(result).status, .warning)
    }
}

final class MicrophoneEvaluationTests: XCTestCase {
    func testLevels() {
        XCTAssertEqual(MicrophoneTest.evaluate(.init(peak: 0.0001, rms: 0.00001), channels: 1, sampleRate: 48000).status, .failed)
        XCTAssertEqual(MicrophoneTest.evaluate(.init(peak: 0.01, rms: 0.001), channels: 1, sampleRate: 48000).status, .warning)
        XCTAssertEqual(MicrophoneTest.evaluate(.init(peak: 0.5, rms: 0.05), channels: 1, sampleRate: 48000).status, .passed)
    }
}
