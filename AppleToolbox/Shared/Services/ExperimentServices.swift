import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

enum ExperimentServiceError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        if case .unavailable(let message) = self { return message }
        return nil
    }
}

struct CryptoService {
    /// Lowercase hex SHA-256 digest of the UTF-8 bytes, or nil where CryptoKit is missing.
    static func sha256Hex(_ message: String) -> String? {
        #if canImport(CryptoKit)
        SHA256.hash(data: Data(message.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        nil
        #endif
    }
}
