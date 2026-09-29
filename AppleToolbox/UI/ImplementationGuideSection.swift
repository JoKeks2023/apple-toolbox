import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// "How to implement": the minimal code and project setup to build the experiment's feature in your own app.
struct ImplementationGuideSection: View {
    let guide: ImplementationGuide

    var body: some View {
        Section {
            CodeBlock(title: "Swift", code: guide.snippet)
            if !guide.infoPlist.isEmpty {
                CodeBlock(title: "Info.plist", code: guide.infoPlistXML)
            }
            if !guide.entitlements.isEmpty {
                CodeBlock(title: "Entitlements", code: guide.entitlements.joined(separator: "\n"))
            }
            if !guide.capabilities.isEmpty {
                LabeledContent("Signing & Capabilities", value: guide.capabilities.joined(separator: ", "))
            }
            ForEach(guide.notes, id: \.self) { note in
                Label(note, systemImage: "lightbulb").font(.callout)
            }
        } header: {
            Text("How to implement")
        } footer: {
            Text("Minimal code for your own app. It typechecks against the \(guide.platform.rawValue) SDK in Swift 6.")
        }
    }
}

private struct CodeBlock: View {
    let title: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                #if !os(tvOS)
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    Clipboard.copy(code)
                    copied = true
                }
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .buttonStyle(.borderless)
                #endif
            }
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    #if !os(tvOS)
                    .textSelection(.enabled)
                    #endif
            }
        }
        .padding(.vertical, 4)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
