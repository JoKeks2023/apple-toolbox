import Testing
@testable import AppleToolbox

struct MultipeerPeerNameTests {
    @Test func keepsShortNames() {
        #expect(MultipeerPeerName.sanitized("iPhone") == "iPhone")
        #expect(MultipeerPeerName.sanitized("  Studio Mac \n") == "Studio Mac")
    }

    @Test func fallsBackForEmptyNames() {
        #expect(MultipeerPeerName.sanitized("") == "Apple Toolbox")
        #expect(MultipeerPeerName.sanitized("   ", fallback: "Mac") == "Mac")
    }

    @Test func cutsLongNamesAtACharacterBoundary() {
        let long = String(repeating: "MacBook Pro ", count: 10)
        #expect(MultipeerPeerName.sanitized(long).utf8.count <= MultipeerPeerName.maxUTF8Bytes)
        // "é" is two UTF-8 bytes: 40 of them are 80 bytes, so the result keeps 31 whole characters (62 bytes).
        let accented = String(repeating: "é", count: 40)
        #expect(MultipeerPeerName.sanitized(accented) == String(repeating: "é", count: 31))
        let emoji = String(repeating: "🧰", count: 20) // four bytes each
        #expect(MultipeerPeerName.sanitized(emoji) == String(repeating: "🧰", count: 15))
    }
}
