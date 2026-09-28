import Foundation
import Combine

#if canImport(MusicKit)
import MusicKit
#endif
#if canImport(ShazamKit)
import ShazamKit
#endif

@MainActor
final class MusicExperimentService: ObservableObject {
    @Published private(set) var output = "MusicKit authorization is ready."

    func requestAuthorization() {
        #if canImport(MusicKit)
        Task {
            let status = await MusicAuthorization.request()
            PermissionCenter.shared.invalidate()
            output = switch status {
            case .authorized: "MusicKit authorized. Catalog and library requests may now be attempted."
            case .denied: "MusicKit authorization denied."
            case .restricted: "MusicKit authorization restricted on this device or account."
            case .notDetermined: "MusicKit authorization remains undetermined."
            @unknown default: "MusicKit returned an unknown authorization state."
            }
        }
        #else
        output = "MusicKit is not supported on this platform."
        #endif
    }
}

enum ShazamExperimentService {
    static func statusText() -> String {
        #if canImport(ShazamKit)
        let session = SHSession()
        _ = session
        return "ShazamKit session can be created. Real matching requires microphone audio and a live SHSession match flow."
        #else
        return "ShazamKit is not supported on this platform."
        #endif
    }
}
