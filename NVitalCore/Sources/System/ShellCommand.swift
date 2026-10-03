import Foundation

/// Runs a system tool and captures its standard output.
enum ShellCommand {
    struct Output {
        let status: Int32
        let data: Data
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) -> Output? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let watchdog = DispatchWorkItem { [weak process] in
            if let process = process, process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Read before waiting so a full pipe cannot dead-lock the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return Output(status: process.terminationStatus, data: data)
    }

    /// Runs a tool that prints a property list (e.g. `diskutil info -plist`).
    static func propertyList(_ executable: String, _ arguments: [String]) -> [String: Any]? {
        guard let output = run(executable, arguments), output.status == 0 else { return nil }
        return (try? PropertyListSerialization.propertyList(from: output.data, options: [], format: nil)) as? [String: Any]
    }
}
