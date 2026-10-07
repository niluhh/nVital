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
    private let keys = KeyboardTest.keys(shape: .ansi, hasTouchBar: false)

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

    func testKeyCodesAreUniqueInEveryShape() {
        for shape in [KeyboardLayout.Shape.ansi, .iso, .jis] {
            let codes = KeyboardTest.keys(shape: shape, hasTouchBar: false).map { $0.keyCode }
            XCTAssertEqual(codes.count, Set(codes).count, "\(shape)")
        }
    }

    func testEachShapeHasItsOwnKeys() {
        func codes(_ shape: KeyboardLayout.Shape) -> Set<UInt16> {
            return Set(KeyboardTest.keys(shape: shape, hasTouchBar: false).map { $0.keyCode })
        }
        let section: UInt16 = 0x0A, grave: UInt16 = 0x32
        XCTAssertTrue(codes(.ansi).contains(grave))
        XCTAssertFalse(codes(.ansi).contains(section))
        XCTAssertTrue(codes(.iso).isSuperset(of: [section, grave]))
        XCTAssertTrue(codes(.jis).isSuperset(of: [0x5D, 0x5E, 0x66, 0x68]))
        XCTAssertTrue(codes(.jis).isDisjoint(with: [section, grave]))
    }

    /// Every row must be as wide as the others once the space a tall key
    /// takes from the row below is counted, or the drawing breaks.
    func testRowsLineUp() {
        for shape in [KeyboardLayout.Shape.ansi, .iso, .jis] {
            let keys = KeyboardTest.keys(shape: shape, hasTouchBar: false)
            for row in 0...5 {
                let width = keys.filter { row >= $0.row && row < $0.row + $0.height }.reduce(0) { $0 + $1.width }
                XCTAssertEqual(width, 15, accuracy: 0.001, "\(shape) row \(row)")
            }
        }
    }

    func testCharacterKeysUseTheLayoutLabels() {
        let spanish: [UInt16: String] = [0x29: "Ñ", 0x2A: "Ç", 0x32: "<", 0x24: "should be ignored"]
        let keys = KeyboardTest.keys(shape: .iso, hasTouchBar: false, label: { spanish[$0] })
        func label(_ code: UInt16) -> String? {
            return keys.first { $0.keyCode == code }?.label
        }
        XCTAssertEqual(label(0x29), "Ñ")
        XCTAssertEqual(label(0x2A), "Ç")
        XCTAssertEqual(label(0x32), "<")
        XCTAssertEqual(label(0x24), "↩") // Return keeps its symbol
        XCTAssertEqual(label(0x00), "A") // falls back to the US keycap
    }

    func testPhysicalTypeCodes() {
        XCTAssertEqual(KeyboardLayout.Shape(physicalType: 0x4953_4F20), .iso)
        XCTAssertEqual(KeyboardLayout.Shape(physicalType: 0x4A49_5320), .jis)
        XCTAssertEqual(KeyboardLayout.Shape(physicalType: 0x414E_5349), .ansi)
    }

    func testFunctionKeysAreRequiredUnlessTouchBar() {
        let f1: UInt16 = 0x7A
        XCTAssertTrue(KeyboardTest.keys(shape: .ansi, hasTouchBar: false).contains { $0.keyCode == f1 && $0.isRequired })
        XCTAssertTrue(KeyboardTest.keys(shape: .ansi, hasTouchBar: true).contains { $0.keyCode == f1 && !$0.isRequired })
        XCTAssertEqual(Set(keys.map { $0.keyCode }).intersection(KeyboardTest.functionKeyCodes),
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

final class WiFiEvaluationTests: XCTestCase {
    func testNoNetworksWarns() {
        XCTAssertEqual(WiFiTest.evaluate(rssiValues: [], measurements: []).status, .warning)
    }

    func testOnlyWeakNetworksWarn() {
        XCTAssertEqual(WiFiTest.evaluate(rssiValues: [-88, -84], measurements: []).status, .warning)
    }

    func testGoodSignalPassesWhetherConnectedOrNot() {
        let notConnected = [DiagnosticMeasurement("Conectado a una red", "No (no afecta al resultado)")]
        let outcome = WiFiTest.evaluate(rssiValues: [-84, -52], measurements: notConnected)
        XCTAssertEqual(outcome.status, .passed)
        XCTAssertTrue(outcome.measurements.contains(DiagnosticMeasurement("Señal más fuerte", "-52 dBm")))
        XCTAssertTrue(outcome.measurements.contains(DiagnosticMeasurement("Redes detectadas", "2")))
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

final class PermissionTests: XCTestCase {
    func testEveryPermissionOpensItsPrivacyPane() {
        for permission in Permission.allCases {
            XCTAssertEqual(permission.settingsURL.scheme, "x-apple.systempreferences")
            XCTAssertTrue(permission.settingsURL.absoluteString.hasSuffix("Privacy_\(permission.rawValue.capitalized)"))
            XCTAssertTrue(permission.deniedMessage.contains(permission.displayName))
        }
    }
}
