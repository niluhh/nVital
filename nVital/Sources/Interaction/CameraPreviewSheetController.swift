import AppKit
import AVFoundation
import NVitalCore

/// Live preview of the session the camera test is running.
final class CameraPreviewSheetController: SheetController {
    private let previewView: NSView
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(request: CameraPreviewRequest) {
        let previewLayer = AVCaptureVideoPreviewLayer(session: request.session)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        let previewView = NSView()
        previewView.wantsLayer = true
        previewView.layer?.addSublayer(previewLayer)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.heightAnchor.constraint(equalToConstant: 360).isActive = true
        self.previewLayer = previewLayer
        self.previewView = previewView

        let yesButton = NSButton(title: "Se ve bien", target: nil, action: nil)
        yesButton.keyEquivalent = "\r"
        let noButton = NSButton(title: "Se ve mal", target: nil, action: nil)
        super.init(title: request.title, instructions: request.message,
                   content: previewView, size: NSSize(width: 560, height: 520), buttons: [noButton, yesButton])
        yesButton.target = self
        yesButton.action = #selector(looksGood(_:))
        noButton.target = self
        noButton.action = #selector(looksBad(_:))

        previewView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(previewResized(_:)),
                                               name: NSView.frameDidChangeNotification, object: previewView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func tearDown() {
        previewLayer.removeFromSuperlayer()
    }

    @objc private func previewResized(_ notification: Notification) {
        previewLayer.frame = previewView.bounds
    }

    @objc private func looksGood(_ sender: Any?) {
        finish(.confirmed(true))
    }

    @objc private func looksBad(_ sender: Any?) {
        finish(.confirmed(false))
    }
}
