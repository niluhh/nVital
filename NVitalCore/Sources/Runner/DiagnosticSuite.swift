import Foundation

public enum DiagnosticSuite {
    /// Every built-in diagnostic, in the order they are run.
    /// Automatic tests go first so the user only has to be present at the end.
    public static func standardTests() -> [DiagnosticTest] {
        return [
            WiFiTest(),
            BluetoothTest(),
            BatteryTest(),
            StorageTest(),
            CameraTest(),
            SpeakerTest(),
            MicrophoneTest(),
            KeyboardTest(),
            TrackpadTest(),
            DisplayTest(),
        ]
    }
}
