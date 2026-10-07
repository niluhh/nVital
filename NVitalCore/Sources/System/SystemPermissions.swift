import ApplicationServices
import AVFoundation
import CoreBluetooth
import Foundation

/// Privacy permissions the diagnostics need.
public enum Permission: String, CaseIterable {
    case camera
    case microphone
    case bluetooth
    /// Optional: lets the keyboard test block system shortcuts.
    case accessibility

    public var displayName: String {
        switch self {
        case .camera: return "Cámara"
        case .microphone: return "Micrófono"
        case .bluetooth: return "Bluetooth"
        case .accessibility: return "Accesibilidad"
        }
    }

    /// Result message for a test that could not run without it.
    public var deniedMessage: String {
        switch self {
        case .camera:
            return "Permiso de cámara denegado. Actívalo en Ajustes del Sistema › Privacidad y seguridad › Cámara y repite la prueba."
        case .microphone:
            return "Permiso de micrófono denegado. Actívalo en Ajustes del Sistema › Privacidad y seguridad › Micrófono y repite la prueba."
        case .bluetooth:
            return "Permiso de Bluetooth denegado. Actívalo en Ajustes del Sistema › Privacidad y seguridad › Bluetooth y repite la prueba."
        case .accessibility:
            return "Permiso de accesibilidad no concedido. Actívalo en Ajustes del Sistema › Privacidad y seguridad › Accesibilidad."
        }
    }

    /// Its pane in System Settings › Privacy & Security.
    public var settingsURL: URL {
        let anchor: String
        switch self {
        case .camera: anchor = "Privacy_Camera"
        case .microphone: anchor = "Privacy_Microphone"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        case .accessibility: anchor = "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

public enum PermissionStatus {
    case granted
    case denied
    /// Never asked. For Accessibility, simply not granted: macOS does not
    /// tell apps whether the user refused it.
    case notDetermined
}

public enum SystemPermissions {
    public static func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .camera: return mediaStatus(.video)
        case .microphone: return mediaStatus(.audio)
        case .bluetooth: return bluetoothStatus()
        case .accessibility: return AXIsProcessTrusted() ? .granted : .notDetermined
        }
    }

    /// Shows macOS' prompt for a permission that was never asked.
    /// `completion` runs on the main queue once the user has answered.
    public static func request(_ permission: Permission, completion: @escaping (PermissionStatus) -> Void) {
        let current = status(of: permission)
        guard current == .notDetermined else {
            DispatchQueue.main.async { completion(current) }
            return
        }
        switch permission {
        case .camera, .microphone:
            guard #available(macOS 10.14, *) else {
                DispatchQueue.main.async { completion(.granted) }
                return
            }
            AVCaptureDevice.requestAccess(for: permission == .camera ? .video : .audio) { granted in
                DispatchQueue.main.async { completion(granted ? .granted : .denied) }
            }
        case .bluetooth:
            DispatchQueue.main.async { BluetoothAuthorizationRequest.start(completion: completion) }
        case .accessibility:
            DispatchQueue.main.async {
                // macOS' prompt sends the user to Privacy & Security, where it
                // is granted later, so there is no answer to wait for.
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                completion(status(of: .accessibility))
            }
        }
    }

    /// Asks for each permission in turn, waiting for every answer, so the
    /// prompts come one after another instead of in the middle of the tests.
    public static func requestAll(_ permissions: [Permission], completion: @escaping ([Permission: PermissionStatus]) -> Void) {
        var results: [Permission: PermissionStatus] = [:]
        func requestNext(_ remaining: ArraySlice<Permission>) {
            guard let permission = remaining.first else {
                completion(results)
                return
            }
            request(permission) { status in
                results[permission] = status
                requestNext(remaining.dropFirst())
            }
        }
        requestNext(ArraySlice(permissions))
    }

    // MARK: - Private

    private static func mediaStatus(_ mediaType: AVMediaType) -> PermissionStatus {
        guard #available(macOS 10.14, *) else { return .granted }
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private static func bluetoothStatus() -> PermissionStatus {
        guard #available(macOS 10.15, *) else { return .granted }
        switch CBManager.authorization {
        case .allowedAlways: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}

/// Creating a Bluetooth manager makes macOS ask for access; its delegate
/// hears back once the user has answered.
private final class BluetoothAuthorizationRequest: NSObject, CBCentralManagerDelegate {
    private static var pending: [BluetoothAuthorizationRequest] = []
    private let completion: (PermissionStatus) -> Void
    private var manager: CBCentralManager?
    private var finished = false

    static func start(completion: @escaping (PermissionStatus) -> Void) {
        let request = BluetoothAuthorizationRequest(completion: completion)
        pending.append(request)
        request.manager = CBCentralManager(delegate: request, queue: .main,
                                           options: [CBCentralManagerOptionShowPowerAlertKey: false])
        // Move on if the prompt is left unanswered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            request.finish()
        }
    }

    private init(completion: @escaping (PermissionStatus) -> Void) {
        self.completion = completion
        super.init()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if SystemPermissions.status(of: .bluetooth) != .notDetermined {
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        manager?.delegate = nil
        manager = nil
        BluetoothAuthorizationRequest.pending.removeAll { $0 === self }
        completion(SystemPermissions.status(of: .bluetooth))
    }
}
