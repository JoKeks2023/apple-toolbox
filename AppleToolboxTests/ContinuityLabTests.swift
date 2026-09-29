import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct ContinuityLabTests {

    @Test func readsTheExperimentFromAHandoff() {
        #expect(ExperimentHandoff.experimentID(from: ExperimentHandoff.userInfo(for: "cryptokit")) == "cryptokit")
        #expect(ExperimentHandoff.experimentID(from: ["experimentID": ""]) == nil)
        #expect(ExperimentHandoff.experimentID(from: ["other": "cryptokit"]) == nil)
        #expect(ExperimentHandoff.experimentID(from: nil) == nil)
    }

    @Test func checksTheActivityTypeDeclaration() {
        #expect(ExperimentHandoff.isDeclared(in: ["NSUserActivityTypes": [ExperimentHandoff.activityType]]))
        #expect(!ExperimentHandoff.isDeclared(in: ["NSUserActivityTypes": ["com.example.other"]]))
        #expect(!ExperimentHandoff.isDeclared(in: [:]))
    }

    @Test func summarizesAnExperimentForSharing() throws {
        let experiment = try #require(ExperimentRegistry.descriptor(for: "cryptokit"))
        let text = ExperimentShareSummary.text(for: experiment, status: .available, platform: .iOS)
        #expect(text.hasPrefix("Apple Toolbox · \(experiment.name) (Security)"))
        #expect(text.contains("Status on iOS: Available"))
        #expect(text.contains(experiment.documentationURL.absoluteString))
        #expect(!text.contains("Hardware:"))
    }

    @Test func readsAppLinksFromTheEntitlement() {
        let domains = UniversalLinks.appLinkDomains(fromEntitlementValue: "webcredentials:example.com, applinks:example.com, applinks:dev.example.com?mode=developer")
        #expect(domains == [AppLinkDomain(host: "example.com", mode: nil), AppLinkDomain(host: "dev.example.com", mode: "developer")])
        #expect(UniversalLinks.appLinkDomains(fromEntitlementValue: "*").isEmpty)
    }

    @Test func normalizesTypedDomains() {
        #expect(UniversalLinks.normalizedHost(" https://Example.com/path?x=1 ") == "example.com")
        #expect(UniversalLinks.normalizedHost("applinks:links.example.com") == "links.example.com")
        #expect(UniversalLinks.normalizedHost("example.com:8443") == "example.com")
        #expect(UniversalLinks.normalizedHost("localhost") == nil)
        #expect(UniversalLinks.normalizedHost("exa mple.com") == nil)
        #expect(UniversalLinks.normalizedHost("*.example.com") == nil)
        #expect(UniversalLinks.url(for: "example.com", source: .domain)?.absoluteString == "https://example.com/.well-known/apple-app-site-association")
        #expect(UniversalLinks.url(for: "example.com", source: .appleCDN)?.absoluteString == "https://app-site-association.cdn-apple.com/a/v1/example.com")
    }

    @Test func parsesAnAppleAppSiteAssociationFile() throws {
        let json = """
        {"applinks": {"details": [
            {"appIDs": ["ABCDE12345.com.example.app"], "components": [{"/": "/buy/*"}, {"/": "/buy/secret", "exclude": true}, {"/": "/search", "?": {"q": "*"}}]},
            {"appID": "ABCDE12345.com.example.legacy", "paths": ["/old/*", "NOT /old/private/*"]}
        ]},
        "webcredentials": {"apps": ["ABCDE12345.com.example.app"]}}
        """
        let document = try AASADocument.parse(Data(json.utf8))
        #expect(document.appLinkDetails.count == 2)
        #expect(document.appLinkDetails[0].patterns == ["/buy/*", "NOT /buy/secret", "/search ?query"])
        #expect(document.appLinkDetails[1].appIDs == ["ABCDE12345.com.example.legacy"])
        #expect(document.linksApp("ABCDE12345.com.example.legacy"))
        #expect(!document.linksApp("ZZZZZ99999.com.example.app"))
        #expect(document.webCredentialApps == ["ABCDE12345.com.example.app"])
        #expect(throws: (any Error).self) { try AASADocument.parse(Data("[1, 2]".utf8)) }
    }

    @Test func reportsWhetherTheFileLinksThisApp() throws {
        let url = try #require(URL(string: "https://example.com/.well-known/apple-app-site-association"))
        let file = Data(#"{"applinks": {"details": [{"appIDs": ["T9CA6D7T8N.com.jorisconrad.AppleToolbox.ios"], "components": [{"/": "*"}]}]}}"#.utf8)
        let linked = UniversalLinks.report(requestedURL: url, finalURL: url, statusCode: 200, contentType: "application/json", data: file, appID: "T9CA6D7T8N.com.jorisconrad.AppleToolbox.ios")
        #expect(linked.linksThisApp == true)
        let other = UniversalLinks.report(requestedURL: url, finalURL: url, statusCode: 200, contentType: "application/json", data: file, appID: "T9CA6D7T8N.com.other")
        #expect(other.linksThisApp == false)
        let unknown = UniversalLinks.report(requestedURL: url, finalURL: url, statusCode: 200, contentType: nil, data: file, appID: nil)
        #expect(unknown.linksThisApp == nil)
        let missing = UniversalLinks.report(requestedURL: url, finalURL: url, statusCode: 404, contentType: "text/html", data: Data(), appID: "T9CA6D7T8N.com.other")
        #expect(missing.linksThisApp == false)
        let redirected = UniversalLinks.report(requestedURL: url, finalURL: URL(string: "https://www.example.com/.well-known/apple-app-site-association"), statusCode: 200, contentType: nil, data: file, appID: nil)
        #expect(redirected.text.contains("Redirected"))
    }

    @Test func continuityExperimentIsSeparateFromWatchConnectivity() throws {
        let continuity = try #require(ExperimentRegistry.descriptor(for: "ecosystem-continuity"))
        #expect(continuity.category == .connectivity)
        #expect(continuity.frameworks.contains("GroupActivities"))
        #expect(ExperimentRegistry.descriptor(for: "continuity")?.frameworks == ["WatchConnectivity"])
        #expect(CapabilityRegistry.descriptor(for: "group-activities")?.experimentID == "ecosystem-continuity")
    }
}
