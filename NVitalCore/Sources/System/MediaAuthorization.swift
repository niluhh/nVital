import AVFoundation

/// Camera and microphone permission (only enforced from macOS 10.14).
enum MediaAuthorization {
    static func request(_ mediaType: AVMediaType, completion: @escaping (Bool) -> Void) {
        guard #available(macOS 10.14, *) else {
            completion(true)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: mediaType, completionHandler: completion)
        default:
            completion(false)
        }
    }

    static let cameraDeniedMessage = "Permiso de cámara denegado. Actívalo en Preferencias del Sistema > Seguridad y privacidad > Privacidad > Cámara y repite la prueba."
    static let microphoneDeniedMessage = "Permiso de micrófono denegado. Actívalo en Preferencias del Sistema > Seguridad y privacidad > Privacidad > Micrófono y repite la prueba."
}
