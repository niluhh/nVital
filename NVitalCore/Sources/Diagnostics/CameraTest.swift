import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Opens the camera, checks it delivers frames that are not black, then asks
/// the user to confirm the live image looks right.
public final class CameraTest: DiagnosticTest {
    public let identifier = "camera"
    public let name = "Cámara"
    public let summary = "Comprueba que la cámara entrega imagen y que se ve correctamente."
    public let category = DiagnosticCategory.media
    public let requiresInteraction = true

    /// Frames to drop while auto-exposure settles.
    let warmUpFrames = 15
    let frameTimeout: TimeInterval = 10

    private var session: AVCaptureSession?
    private var grabber: FrameGrabber?

    public init() {}

    public func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        guard let device = AVCaptureDevice.default(for: .video) else {
            if context.machine.hasBuiltInMedia {
                completion(.failed("No se ha detectado ninguna cámara."))
            } else {
                completion(.skipped("No se ha detectado cámara (normal en Mac mini, Mac Studio y Mac Pro sin cámara externa)."))
            }
            return
        }

        SystemPermissions.request(.camera) { status in
            guard status == .granted else {
                completion(.error(Permission.camera.deniedMessage))
                return
            }
            // The permission callback arrives on the main queue; capturing blocks.
            DispatchQueue.global(qos: .userInitiated).async {
                self.capture(from: device, context: context, completion: completion)
            }
        }
    }

    public func cancel() {
        stopSession()
    }

    private func capture(from device: AVCaptureDevice, context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        var measurements = [DiagnosticMeasurement("Dispositivo", device.localizedName)]

        let session = AVCaptureSession()
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(output) else {
                completion(.failed("No se ha podido abrir la cámara.", measurements))
                return
            }
            session.addInput(input)
            session.addOutput(output)
        } catch {
            completion(.failed("No se ha podido abrir la cámara: \(error.localizedDescription)", measurements))
            return
        }

        let grabber = FrameGrabber(warmUpFrames: warmUpFrames)
        output.setSampleBufferDelegate(grabber, queue: grabber.queue)
        self.session = session
        self.grabber = grabber
        session.startRunning()

        guard let frame = grabber.waitForFrame(timeout: frameTimeout) else {
            stopSession()
            completion(context.isCancelled ? .cancelled : .failed("La cámara no entrega imagen.", measurements))
            return
        }

        measurements.append(DiagnosticMeasurement("Resolución", "\(frame.width) × \(frame.height)"))
        measurements.append(DiagnosticMeasurement("Brillo medio", String(format: "%.0f %%", frame.luminance * 100)))
        let isBlack = frame.luminance < 0.03

        let request = CameraPreviewRequest(
            title: "Comprueba la imagen de la cámara",
            message: isBlack
                ? "La imagen parece completamente negra. Comprueba que nada tape la cámara. ¿Se ve la imagen correctamente?"
                : "¿Se ve la imagen nítida, con colores normales y sin manchas ni líneas?",
            session: session)

        context.request(.cameraPreview(request)) { response in
            self.stopSession()
            switch response {
            case .confirmed(true):
                completion(.passed("La cámara funciona correctamente.", measurements))
            case .confirmed(false):
                completion(.failed("El usuario indica que la imagen de la cámara no es correcta.", measurements))
            case .unavailable:
                completion(isBlack
                    ? .failed("La cámara entrega una imagen negra.", measurements)
                    : .passed("La cámara entrega imagen (sin revisión visual).", measurements))
            case .cancelled:
                completion(.cancelled)
            default:
                completion(.skippedByUser)
            }
        }
    }

    private func stopSession() {
        session?.stopRunning()
        session = nil
        grabber = nil
    }
}

/// Collects one frame after a warm-up period and measures its brightness.
private final class FrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Frame {
        let width: Int
        let height: Int
        /// Mean luminance in 0...1.
        let luminance: Double
    }

    let queue = DispatchQueue(label: "com.nil.nvital.core.camera")
    private let warmUpFrames: Int
    private var receivedFrames = 0
    private var frame: Frame?
    private let semaphore = DispatchSemaphore(value: 0)

    init(warmUpFrames: Int) {
        self.warmUpFrames = warmUpFrames
    }

    func waitForFrame(timeout: TimeInterval) -> Frame? {
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return queue.sync { frame }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard frame == nil else { return }
        receivedFrames += 1
        guard receivedFrames > warmUpFrames, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frame = Self.measure(pixelBuffer)
        semaphore.signal()
    }

    private static func measure(_ pixelBuffer: CVPixelBuffer) -> Frame {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return Frame(width: width, height: height, luminance: 0)
        }

        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let step = 8
        var total = 0.0
        var count = 0
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let pixel = pixels + y * bytesPerRow + x * 4 // BGRA
                total += 0.0722 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.2126 * Double(pixel[2])
                count += 1
            }
        }
        return Frame(width: width, height: height, luminance: count > 0 ? total / Double(count) / 255 : 0)
    }
}
