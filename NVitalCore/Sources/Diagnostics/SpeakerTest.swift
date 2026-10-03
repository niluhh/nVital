import AVFoundation
import Foundation

/// Plays a tone on the left channel and then on the right one, and asks the
/// user whether both were heard.
public final class SpeakerTest: DiagnosticTest {
    public let identifier = "speakers"
    public let name = "Altavoces"
    public let summary = "Reproduce un tono por cada canal para comprobar los altavoces."
    public let category = DiagnosticCategory.media
    public let requiresInteraction = true

    let toneFrequency = 880.0
    let toneDuration = 1.0
    let gapDuration = 0.5

    private var engine: AVAudioEngine?

    public init() {}

    public func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        let notice = NoticeRequest(
            title: "Prueba de altavoces",
            message: "Sube el volumen y desconecta los auriculares. Se reproducirá un tono por el altavoz izquierdo y después por el derecho.",
            buttonTitle: "Reproducir")

        context.request(.notice(notice)) { response in
            switch response {
            case .acknowledged, .unavailable:
                self.playTones(context: context, completion: completion)
            case .cancelled:
                completion(.cancelled)
            default:
                completion(.skippedByUser)
            }
        }
    }

    public func cancel() {
        stopEngine()
    }

    private func playTones(context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: hardwareFormat.sampleRate, channels: 2) else {
            completion(.failed("No se ha encontrado ningún dispositivo de salida de audio."))
            return
        }

        var measurements = [
            DiagnosticMeasurement("Canales de salida", "\(hardwareFormat.channelCount)"),
            DiagnosticMeasurement("Frecuencia de muestreo", String(format: "%.0f Hz", hardwareFormat.sampleRate)),
        ]

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        do {
            try engine.start()
        } catch {
            completion(.failed("No se ha podido iniciar el audio: \(error.localizedDescription)", measurements))
            return
        }
        self.engine = engine

        for buffer in [makeTone(format: format, left: true, right: false),
                       makeSilence(format: format),
                       makeTone(format: format, left: false, right: true)] {
            player.scheduleBuffer(buffer, completionHandler: nil)
        }
        player.play()

        if hardwareFormat.channelCount < 2 {
            measurements.append(DiagnosticMeasurement("Nota", "Salida mono: ambos tonos suenan por el mismo altavoz."))
        }

        let total = toneDuration * 2 + gapDuration + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            self.stopEngine()
            guard !context.isCancelled else {
                completion(.cancelled)
                return
            }
            let question = ConfirmationRequest(
                title: "¿Has oído los dos tonos?",
                message: "El primero debía sonar por la izquierda y el segundo por la derecha, limpios y sin distorsión.",
                confirmTitle: "Sí, ambos",
                denyTitle: "No")
            context.request(.confirmation(question)) { response in
                switch response {
                case .confirmed(true):
                    completion(.passed("Los altavoces funcionan correctamente.", measurements))
                case .confirmed(false):
                    completion(.failed("El usuario no ha oído correctamente alguno de los tonos.", measurements))
                case .unavailable:
                    completion(.skipped("Los tonos se han reproducido, pero nadie ha confirmado que se oyeran.", measurements))
                case .cancelled:
                    completion(.cancelled)
                default:
                    completion(.skippedByUser)
                }
            }
        }
    }

    private func stopEngine() {
        engine?.stop()
        engine = nil
    }

    private func makeTone(format: AVAudioFormat, left: Bool, right: Bool) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * toneDuration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let fade = Int(sampleRate * 0.02)
        let total = Int(frameCount)
        let channels = buffer.floatChannelData!

        for frame in 0..<total {
            // Short fade in/out avoids clicks.
            let envelope = Float(min(1, Double(min(frame, total - frame)) / Double(max(fade, 1))))
            let sample = Float(sin(2 * Double.pi * toneFrequency * Double(frame) / sampleRate)) * 0.5 * envelope
            channels[0][frame] = left ? sample : 0
            channels[1][frame] = right ? sample : 0
        }
        return buffer
    }

    private func makeSilence(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(format.sampleRate * gapDuration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channels = buffer.floatChannelData!
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(frameCount) {
                channels[channel][frame] = 0
            }
        }
        return buffer
    }
}
