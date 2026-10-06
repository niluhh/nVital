import AVFoundation
import Foundation

/// Implemented by the host app to show the UI a test asks for.
///
/// Both methods are called on the main queue. `completion` must be called
/// exactly once per request, from any queue.
public protocol DiagnosticInteractionHandler: AnyObject {
    func handle(_ request: InteractionRequest, completion: @escaping (InteractionResponse) -> Void)

    /// The run was cancelled: dismiss whatever is on screen. Calling the
    /// pending completion afterwards is allowed and ignored.
    func cancelPendingInteraction()
}

public enum InteractionRequest {
    /// Yes/no question. Answer with `.confirmed(_:)`.
    case confirmation(ConfirmationRequest)
    /// Information the user must read before the test continues. Answer with `.acknowledged`.
    case notice(NoticeRequest)
    /// Ask the user to press every key. Answer with `.keyboard(_:)`.
    case keyboard(KeyboardCaptureRequest)
    /// Ask the user to use the trackpad. Answer with `.trackpad(_:)`.
    case trackpad(TrackpadCaptureRequest)
    /// Show full-screen patterns. Answer with `.acknowledged` once they have all been shown.
    case displayPatterns(DisplayPatternRequest)
    /// Show a live camera preview and ask whether it looks right. Answer with `.confirmed(_:)`.
    case cameraPreview(CameraPreviewRequest)
}

public enum InteractionResponse {
    case confirmed(Bool)
    case acknowledged
    case keyboard(KeyboardCaptureResult)
    case trackpad(TrackpadCaptureResult)
    /// The user chose to skip this test.
    case skipped
    /// The run was cancelled while the request was on screen.
    case cancelled
    /// No interaction handler is available (e.g. headless run).
    case unavailable
}

// MARK: - Requests

public struct ConfirmationRequest {
    public let title: String
    public let message: String
    public let confirmTitle: String
    public let denyTitle: String

    public init(title: String, message: String, confirmTitle: String = "Sí", denyTitle: String = "No") {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.denyTitle = denyTitle
    }
}

public struct NoticeRequest {
    public let title: String
    public let message: String
    public let buttonTitle: String

    public init(title: String, message: String, buttonTitle: String = "Continuar") {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
    }
}

/// A physical key, identified by its layout-independent virtual key code
/// (the `kVK_*` constants of Carbon's Events.h, i.e. `NSEvent.keyCode`).
public struct KeyDescriptor: Equatable {
    public let keyCode: UInt16
    public let label: String
    /// Row on a Mac laptop keyboard, 0 = function row, 5 = space bar row.
    public let row: Int
    /// Width relative to a letter key.
    public let width: Double
    /// Optional keys are reported but do not make the test fail
    /// (e.g. Escape on Touch Bar models).
    public let isRequired: Bool

    public init(keyCode: UInt16, label: String, row: Int, width: Double = 1, isRequired: Bool = true) {
        self.keyCode = keyCode
        self.label = label
        self.row = row
        self.width = width
        self.isRequired = isRequired
    }
}

public struct KeyboardCaptureRequest {
    public let instructions: String
    public let keys: [KeyDescriptor]

    public init(instructions: String, keys: [KeyDescriptor]) {
        self.instructions = instructions
        self.keys = keys
    }
}

public struct KeyboardCaptureResult: Equatable {
    public let pressedKeyCodes: Set<UInt16>
    /// Whether the app kept macOS shortcuts (e.g. F11 Show Desktop, ⌘Tab)
    /// from swallowing key presses during the capture.
    public let systemShortcutsBlocked: Bool

    public init(pressedKeyCodes: Set<UInt16>, systemShortcutsBlocked: Bool = false) {
        self.pressedKeyCodes = pressedKeyCodes
        self.systemShortcutsBlocked = systemShortcutsBlocked
    }
}

public struct TrackpadCaptureRequest {
    public let instructions: String
    public let columns: Int
    public let rows: Int

    public init(instructions: String, columns: Int, rows: Int) {
        self.instructions = instructions
        self.columns = columns
        self.rows = rows
    }
}

public struct TrackpadCaptureResult: Equatable {
    /// Number of grid cells the pointer went through.
    public let visitedCells: Int
    public let totalCells: Int
    public let primaryClick: Bool
    public let secondaryClick: Bool
    public let scrolled: Bool
    public let pinched: Bool

    public init(visitedCells: Int, totalCells: Int, primaryClick: Bool, secondaryClick: Bool, scrolled: Bool, pinched: Bool) {
        self.visitedCells = visitedCells
        self.totalCells = totalCells
        self.primaryClick = primaryClick
        self.secondaryClick = secondaryClick
        self.scrolled = scrolled
        self.pinched = pinched
    }
}

public struct DisplayPattern: Equatable {
    public enum Kind: Equatable {
        /// Components in 0...1.
        case solid(red: Double, green: Double, blue: Double)
        /// Black to white, left to right.
        case horizontalGradient
        /// Black and white squares of `size` points.
        case checkerboard(size: Int)
    }

    public let name: String
    public let kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }
}

public struct DisplayPatternRequest {
    public let instructions: String
    public let patterns: [DisplayPattern]
    /// `CGDirectDisplayID` of the screen to use, or `nil` for the main screen.
    public let displayID: UInt32?

    public init(instructions: String, patterns: [DisplayPattern], displayID: UInt32?) {
        self.instructions = instructions
        self.patterns = patterns
        self.displayID = displayID
    }
}

public struct CameraPreviewRequest {
    public let title: String
    public let message: String
    /// Running session the app can attach an `AVCaptureVideoPreviewLayer` to.
    public let session: AVCaptureSession

    public init(title: String, message: String, session: AVCaptureSession) {
        self.title = title
        self.message = message
        self.session = session
    }
}
