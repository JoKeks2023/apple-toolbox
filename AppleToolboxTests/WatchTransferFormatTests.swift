import Testing
import Foundation
@testable import AppleToolbox

struct WatchTransferFormatTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13:20 UTC

    @Test func summarizesPayloadsSortedByKey() {
        let payload: [String: Any] = ["kind": "user-info", "counter": 3, "sentAt": date, "blob": Data(count: 4)]
        #expect(WatchTransferFormat.summary(payload) == "blob=4 bytes · counter=3 · kind=user-info · sentAt=2026-09-21T14:13:20Z")
    }

    @Test func emptyAndMissingPayloadsReadAsEmpty() {
        #expect(WatchTransferFormat.summary([:]) == "empty")
        #expect(WatchTransferFormat.summary(nil) == "empty")
    }

    @Test func nestedValuesAreSummarized() {
        #expect(WatchTransferFormat.value(["b": 1, "a": "x"] as [String: Any]) == "{a=x · b=1}")
        #expect(WatchTransferFormat.value([1, 2, 3]) == "[3 items]")
    }

    @Test func fileNamesAreSafeAndTimestampedInUTC() {
        #expect(WatchTransferFormat.fileName(from: "Anna's Watch", date: date) == "toolbox-Anna-s-Watch-20260921-141320.txt")
    }

    @Test func fileContentsNameTheSenderAndCounter() {
        let text = WatchTransferFormat.fileContents(from: "iPhone", date: date, counter: 7)
        #expect(text.contains("#7"))
        #expect(text.contains("From: iPhone"))
    }

    @Test func previewTruncatesTextAndDescribesBinaryData() {
        #expect(WatchTransferFormat.preview(Data("abcdef".utf8), limit: 3) == "abc…")
        #expect(WatchTransferFormat.preview(Data([0xFF, 0xFE, 0xFD])) == "3 bytes of binary data")
    }

    @Test func messageKindsAreDistinct() {
        let kinds = [WatchLinkMessage.ping, WatchLinkMessage.nearbyToken, WatchLinkMessage.nearbyStop, WatchLinkMessage.context,
                     WatchLinkMessage.userInfo, WatchLinkMessage.complication, WatchLinkMessage.file]
        #expect(Set(kinds).count == kinds.count)
    }
}
