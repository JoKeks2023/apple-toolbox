import Testing
import Foundation
@testable import AppleToolbox

struct DomainStateChangeTests {
    private let earlier = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func comparesStoredAndCurrentHashes() {
        let stored = StoredDomainState(stateHash: Data([1, 2, 3]), date: earlier)
        #expect(DomainStateChange.compare(stored: nil, current: nil) == .noState)
        #expect(DomainStateChange.compare(stored: nil, current: Data([1])) == .firstCheck)
        #expect(DomainStateChange.compare(stored: stored, current: Data([1, 2, 3])) == .unchanged(since: earlier))
        #expect(DomainStateChange.compare(stored: stored, current: Data([1, 2, 4])) == .changed(since: earlier))
        #expect(DomainStateChange.compare(stored: stored, current: nil) == .removed(since: earlier))
    }

    @Test func onlyChangesAndRemovalsCountAsEnrolmentChanges() {
        #expect(DomainStateChange.changed(since: earlier).isChange)
        #expect(DomainStateChange.removed(since: earlier).isChange)
        #expect(!DomainStateChange.unchanged(since: earlier).isChange)
        #expect(!DomainStateChange.firstCheck.isChange)
        #expect(DomainStateChange.changed(since: earlier).summary.hasPrefix("CHANGED"))
    }

    @Test func storeRemembersTheLastSeenStateAcrossChecks() throws {
        let suite = "DomainStateChangeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = DomainStateStore(suiteName: suite)
        let first = Date(timeIntervalSince1970: 1_800_000_000), second = first.addingTimeInterval(60)

        #expect(store.check("biometry", current: Data([1]), now: first) == .firstCheck)
        #expect(store.check("biometry", current: Data([1]), now: second) == .unchanged(since: first))
        #expect(store.check("biometry", current: Data([2]), now: second) == .changed(since: first))
        #expect(store.check("biometry", current: Data([2]), now: second.addingTimeInterval(1)) == .unchanged(since: second))
        #expect(store.check("biometry", current: nil, now: second) == .removed(since: second))
        #expect(store.load("biometry") == nil)
        #expect(store.check("companion", current: nil) == .noState)
    }
}

struct LocalAuthenticationChoiceTests {

    @Test func errorCodesHaveTheirLAErrorNames() {
        #expect(LocalAuthenticationErrorName.name(for: -2) == "userCancel")
        #expect(LocalAuthenticationErrorName.name(for: -5) == "passcodeNotSet")
        #expect(LocalAuthenticationErrorName.name(for: -7) == "biometryNotEnrolled")
        #expect(LocalAuthenticationErrorName.name(for: -11) == "companionNotAvailable")
        #expect(LocalAuthenticationErrorName.name(for: -1004) == "notInteractive")
        let error = NSError(domain: "com.apple.LocalAuthentication", code: -8, userInfo: [NSLocalizedDescriptionKey: "Locked"])
        #expect(LocalAuthenticationErrorName.describe(error) == "LAError -8 (biometryLockout): Locked")
    }

    @Test func policiesAndReuseWindowsMatchTheSDK() {
        let names = LocalAuthenticationPolicyOption.allCases.map(\.apiName)
        #expect(Set(names).count == names.count)
        #expect(LocalAuthenticationReuseDuration.allCases.allSatisfy { $0.rawValue >= 0 && $0.rawValue <= 300 })
        #expect(LocalAuthenticationReuseDuration.maximum.rawValue == 300)
    }
}
