import AVFoundation
import Foundation

/// Records a few seconds while the user speaks and checks the input level.
public final class MicrophoneTest: DiagnosticTest {
    public let identifier = "microphone"
    public let name = "Micrófono"
    public let summary = "Graba unos segundos y comprueba que el micrófono capta sonido."
    public let category = DiagnosticCategory.media
    public let requiresInteraction = true

    let recordingDuration = 4.0

    private var engine: AVAudioEngine?
    private let levelQueue = DispatchQueue(label: "com.nil.nvital.core.microphone")
    private var peak: Float = 0
    private var sumOfSquares: Double = 0
    private var sampleCount = 0

    public init() {}

    public func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        SystemPermissions.request(.microphone) { status in
            guard status == .granted else {
                completion(.error(Permission.microphone.deniedMessage))
                return
            }
            let notice = NoticeRequest(
                title: "Prueba de micrófono",
                message: "Al pulsar «Grabar», habla en voz alta o da palmadas cerca del Mac durante \(Int(self.recordingDuration)) segundos.",
                buttonTitle: "Grabar")
            context.request(.notice(notice)) { response in
                switch response {
                case .acknowledged, .unavailable:
                    self.record(context: context, completion: completion)
                case .cancelled:
                    completion(.cancelled)
                default:
                    completion(.skippedByUser)
                }
            }
        }
    }

    public func cancel() {
        stopEngine()
    }

    private func record(context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            completion(context.machine.hasBuiltInMedia
                ? .failed("No se ha encontrado ningún micrófono.")
                : .skipped("No se ha encontrado ningún micrófono (normal en equipos de sobremesa sin micrófono externo)."))
            return
        }

        levelQueue.sync {
            peak = 0
            sumOfSquares = 0
            sampleCount = 0
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.accumulate(buffer)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            completion(.failed("No se ha podido iniciar la grabación: \(error.localizedDescription)"))
            return
        }
        self.engine = engine

        DispatchQueue.main.asyncAfter(deadline: .now() + recordingDuration) {
            self.stopEngine()
            guard !context.isCancelled else {
                completion(.cancelled)
                return
            }
            let level = self.levelQueue.sync { () -> Level in
                let rms = self.sampleCount > 0 ? sqrt(self.sumOfSquares / Double(self.sampleCount)) : 0
                return Level(peak: Double(self.peak), rms: rms)
            }
            completion(Self.evaluate(level, channels: Int(format.channelCount), sampleRate: format.sampleRate))
        }
    }

    private func accumulate(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let samples = data[0]
        let count = Int(buffer.frameLength)
        var localPeak: Float = 0
        var localSum = 0.0
        for index in 0..<count {
            let value = abs(samples[index])
            localPeak = max(localPeak, value)
            localSum += Double(value * value)
        }
        levelQueue.async {
            self.peak = max(self.peak, localPeak)
            self.sumOfSquares += localSum
            self.sampleCount += count
        }
    }

    private func stopEngine() {
        guard let engine = engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    // MARK: - Evaluation

    struct Level: Equatable {
        /// Linear amplitudes in 0...1.
        let peak: Double
        let rms: Double
    }

    static func decibels(_ amplitude: Double) -> Double {
        return amplitude > 0 ? 20 * log10(amplitude) : -160
    }

    static func evaluate(_ level: Level, channels: Int, sampleRate: Double) -> DiagnosticOutcome {
        let peakDB = decibels(level.peak)
        let measurements = [
            DiagnosticMeasurement("Canales de entrada", "\(channels)"),
            DiagnosticMeasurement("Frecuencia de muestreo", String(format: "%.0f Hz", sampleRate)),
            DiagnosticMeasurement("Pico", String(format: "%.1f dBFS", peakDB)),
            DiagnosticMeasurement("Nivel medio", String(format: "%.1f dBFS", decibels(level.rms))),
        ]
        if peakDB < -50 {
            return .failed("El micrófono no ha captado sonido.", measurements)
        }
        if peakDB < -30 {
            return .warning("El micrófono capta muy poco sonido. Repite la prueba hablando más cerca.", measurements)
        }
        return .passed("El micrófono capta sonido correctamente.", measurements)
    }
}
