import Darwin
import Foundation

/// Checks SMART status, free space, and does a write/read/verify pass
/// on the startup disk.
public final class StorageTest: DiagnosticTest {
    public let identifier = "storage"
    public let name = "Almacenamiento"
    public let summary = "Comprueba el estado SMART del disco interno y su velocidad de lectura y escritura."
    public let category = DiagnosticCategory.storage

    /// Size of the temporary file written to the startup disk.
    var testFileSize = 256 * 1024 * 1024
    let chunkSize = 4 * 1024 * 1024

    public init() {}

    public func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        var measurements: [DiagnosticMeasurement] = []
        var warnings: [String] = []

        // 1. SMART status of the internal disk.
        let smart = Self.smartStatus()
        if let smart = smart {
            measurements.append(DiagnosticMeasurement("Disco", smart.deviceName))
            measurements.append(DiagnosticMeasurement("Estado SMART", smart.status))
            if smart.status.lowercased().contains("fail") {
                completion(.failed("El disco interno informa de un fallo SMART. Haz una copia de seguridad y sustitúyelo.", measurements))
                return
            }
        } else {
            measurements.append(DiagnosticMeasurement("Estado SMART", "No disponible"))
        }

        // 2. Capacity of the startup volume.
        let root = URL(fileURLWithPath: "/")
        if let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity, total > 0 {
            measurements.append(DiagnosticMeasurement("Capacidad", Self.formatBytes(Int64(total))))
            measurements.append(DiagnosticMeasurement("Espacio libre", Self.formatBytes(Int64(available))))
            if Double(available) / Double(total) < 0.05 {
                warnings.append("Queda menos del 5 % de espacio libre.")
            }
            if available < testFileSize * 2 {
                completion(.warning("No hay espacio suficiente para la prueba de lectura y escritura.", measurements))
                return
            }
        }

        // 3. Write, read back and verify a temporary file.
        let benchmark: Benchmark
        do {
            benchmark = try runBenchmark(context: context)
        } catch BenchmarkError.cancelled {
            completion(.cancelled)
            return
        } catch BenchmarkError.corrupted {
            completion(.failed("Los datos leídos no coinciden con los escritos. El disco puede estar dañado.", measurements))
            return
        } catch {
            completion(.failed("Error de entrada/salida en el disco: \(error.localizedDescription)", measurements))
            return
        }

        measurements.append(DiagnosticMeasurement("Escritura", String(format: "%.0f MB/s", benchmark.writeMBps)))
        measurements.append(DiagnosticMeasurement("Lectura", String(format: "%.0f MB/s", benchmark.readMBps)))

        if !warnings.isEmpty {
            completion(.warning(warnings.joined(separator: " "), measurements))
        } else if smart == nil {
            completion(.warning("Lectura y escritura correctas, pero el disco no informa de su estado SMART.", measurements))
        } else {
            completion(.passed("El disco interno funciona correctamente.", measurements))
        }
    }

    // MARK: - SMART

    struct SMARTStatus {
        let deviceName: String
        let status: String
    }

    /// SMART status of the first internal physical disk with a known status.
    static func smartStatus() -> SMARTStatus? {
        for index in 0..<4 {
            guard let info = ShellCommand.propertyList("/usr/sbin/diskutil", ["info", "-plist", "disk\(index)"]),
                  info["Internal"] as? Bool ?? false,
                  let status = info["SMARTStatus"] as? String,
                  status != "Not Supported" else {
                continue
            }
            let name = info["MediaName"] as? String ?? "disk\(index)"
            return SMARTStatus(deviceName: name, status: status)
        }
        return nil
    }

    // MARK: - Benchmark

    struct Benchmark {
        let writeMBps: Double
        let readMBps: Double
    }

    enum BenchmarkError: Error {
        case cancelled
        case corrupted
    }

    private func runBenchmark(context: DiagnosticContext) throws -> Benchmark {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("nvital-\(UUID().uuidString).tmp")
        let descriptor = open(path, O_CREAT | O_RDWR | O_TRUNC, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer {
            close(descriptor)
            unlink(path)
        }
        // Bypass the unified buffer cache so we measure the disk, not RAM.
        _ = fcntl(descriptor, F_NOCACHE, 1)

        var pattern = [UInt8](repeating: 0, count: chunkSize)
        arc4random_buf(&pattern, chunkSize)
        let chunks = testFileSize / chunkSize

        let writeStart = Date()
        for _ in 0..<chunks {
            if context.isCancelled { throw BenchmarkError.cancelled }
            let written = pattern.withUnsafeBytes { write(descriptor, $0.baseAddress, chunkSize) }
            guard written == chunkSize else { throw posixError() }
        }
        guard fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0 else { throw posixError() }
        let writeTime = Date().timeIntervalSince(writeStart)

        guard lseek(descriptor, 0, SEEK_SET) == 0 else { throw posixError() }
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        let readStart = Date()
        for _ in 0..<chunks {
            if context.isCancelled { throw BenchmarkError.cancelled }
            let read = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, chunkSize) }
            guard read == chunkSize else { throw posixError() }
            guard buffer == pattern else { throw BenchmarkError.corrupted }
        }
        let readTime = Date().timeIntervalSince(readStart)

        let megabytes = Double(testFileSize) / 1_000_000
        return Benchmark(writeMBps: megabytes / max(writeTime, 0.001),
                         readMBps: megabytes / max(readTime, 0.001))
    }

    private func posixError() -> Error {
        return NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
