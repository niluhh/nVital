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
    private let keys = KeyboardTest.keys(hasTouchBar: false)

    private func requiredCodes(_ keys: [KeyDescriptor]) -> Set<UInt16> {
        return Set(keys.filter { $0.isRequired }.map { $0.keyCode })
    }

    func testAllRequiredKeysPass() {
        XCTAssertEqual(KeyboardTest.evaluate(pressed: requiredCodes(keys), keys: keys).status, .passed)
    }

    func testMissingKeyFailsAndIsListed() {
        var pressed = Set(keys.map { $0.keyCode })
        pressed.remove(0x00) // A
        let outcome = KeyboardTest.evaluate(pressed: pressed, keys: keys)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertTrue(outcome.measurements.contains { $0.value.contains("A") })
    }

    func testKeyCodesAreUnique() {
        let codes = keys.map { $0.keyCode }
        XCTAssertEqual(codes.count, Set(codes).count)
    }

    func testFunctionKeysAreRequiredUnlessTouchBar() {
        let f1: UInt16 = 0x7A
        XCTAssertTrue(KeyboardTest.keys(hasTouchBar: false).contains { $0.keyCode == f1 && $0.isRequired })
        XCTAssertTrue(KeyboardTest.keys(hasTouchBar: true).contains { $0.keyCode == f1 && !$0.isRequired })
        XCTAssertEqual(Set(KeyboardTest.keys(hasTouchBar: false).map { $0.keyCode }).intersection(KeyboardTest.functionKeyCodes),
                       KeyboardTest.functionKeyCodes)
    }

    func testMissingFunctionKeyWarnsOnlyWhenShortcutsWereNotBlocked() {
        var pressed = requiredCodes(keys)
        pressed.remove(0x67) // F11, Show Desktop by default
        XCTAssertEqual(KeyboardTest.evaluate(pressed: pressed, keys: keys, functionKeysReliable: false).status, .warning)
        XCTAssertEqual(KeyboardTest.evaluate(pressed: pressed, keys: keys, functionKeysReliable: true).status, .failed)

        pressed.remove(0x00) // A: a real failure either way
        XCTAssertEqual(KeyboardTest.evaluate(pressed: pressed, keys: keys, functionKeysReliable: false).status, .failed)
    }

    func testTouchBarModels() {
        func machine(_ model: String) -> MachineInfo {
            return MachineInfo(modelIdentifier: model, serialNumber: "", architecture: "", processor: "",
                               memoryBytes: 0, systemVersion: "", systemBuild: "", isPortable: true)
        }
        XCTAssertTrue(machine("MacBookPro15,2").hasTouchBar)
        XCTAssertTrue(machine("Mac14,7").hasTouchBar)
        XCTAssertFalse(machine("MacBookPro14,1").hasTouchBar)
        XCTAssertFalse(machine("MacBookPro18,3").hasTouchBar)
        XCTAssertFalse(machine("MacBookAir10,1").hasTouchBar)
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

final class FunctionKeyModeTests: XCTestCase {
    /// Read-only: changing the mode would alter the machine running the tests.
    func testCurrentModeIsReadable() {
        XCTAssertNotNil(FunctionKeyMode(rawValue: FunctionKeyMode.current.rawValue))
        XCTAssertNotNil(FunctionKeyMode(rawValue: FunctionKeyMode.preferred.rawValue))
    }
}
