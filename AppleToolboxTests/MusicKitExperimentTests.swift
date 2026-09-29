import Testing
import Foundation
import MusicKit
@testable import AppleToolbox

struct MusicKitExperimentTests {

    @Test func missingAppServiceExplainsTheDeveloperTokenFailure() {
        let text = MusicExperimentService.describe(MusicTokenRequestError.developerTokenRequestFailed)
        #expect(text.hasPrefix("MusicTokenRequestError.developerTokenRequestFailed"))
        #expect(text.contains("MusicKit App Service"))
    }

    @Test func everyTokenErrorGetsAHint() {
        let errors: [MusicTokenRequestError] = [.unknown, .permissionDenied, .userTokenRevoked, .userNotSignedIn, .privacyAcknowledgementRequired, .developerTokenRequestFailed, .userTokenRequestFailed]
        for error in errors {
            let lines = MusicExperimentService.describe(error).split(separator: "\n")
            #expect(lines.count >= 2, "\(error)")
        }
    }

    @Test func subscriptionAndOtherErrorsKeepTheirIdentity() {
        #expect(MusicExperimentService.describe(MusicSubscription.Error.privacyAcknowledgementRequired).hasPrefix("MusicSubscription.Error.privacyAcknowledgementRequired"))
        let other = MusicExperimentService.describe(NSError(domain: "MPErrorDomain", code: 2))
        #expect(other.contains("Domain: MPErrorDomain · Code: 2"))
    }

    @Test func pickerOptionsAreDistinct() {
        #expect(Set(MusicItemKind.allCases.map(\.rawValue)).count == 4)
        #expect(Set(MusicSource.allCases.map(\.rawValue)).count == 2)
    }
}
