import Testing
@testable import AppleToolbox

struct ToolboxIdentifiersTests {
    @Test func derivesTheBaseFromEveryTargetsBundleID() {
        #expect(ToolboxIdentifiers.baseIdentifier(for: "com.example.AppleToolbox.ios") == "com.example.AppleToolbox")
        #expect(ToolboxIdentifiers.baseIdentifier(for: "io.github.someone.AppleToolbox.ios.watchkitapp.widget") == "io.github.someone.AppleToolbox")
        #expect(ToolboxIdentifiers.baseIdentifier(for: "com.example.AppleToolbox.macos") == "com.example.AppleToolbox")
    }

    @Test func fallsBackToThePlaceholder() {
        #expect(ToolboxIdentifiers.baseIdentifier(for: nil) == ToolboxIdentifiers.placeholderBase)
        #expect(ToolboxIdentifiers.baseIdentifier(for: "com.example.AppleToolboxTests") == ToolboxIdentifiers.placeholderBase)
        #expect(ToolboxIdentifiers.baseIdentifier(for: "AppleToolbox.ios") == ToolboxIdentifiers.placeholderBase)
    }

    @Test func buildsTheAppGroupFromTheBase() {
        #expect(ToolboxIdentifiers.appGroup == "group.\(ToolboxIdentifiers.base)")
        #expect(ExperimentHandoff.activityType.hasPrefix(ToolboxIdentifiers.base))
    }
}
