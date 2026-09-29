import SwiftUI

#if canImport(PassKit) && !os(watchOS) && !os(tvOS)
import PassKit
#endif
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
#if os(iOS) || os(macOS)
import UniformTypeIdentifiers
#endif

struct WalletPassLibraryRunView: View {
    @StateObject private var wallet = WalletPassLibraryService()
    @State private var isImporting = false

    var body: some View {
        HStack {
            Button("Read Pass Library", systemImage: "wallet.pass", action: wallet.refresh)
                .buttonStyle(.borderedProminent)
            #if os(iOS) || os(macOS)
            Button("Add .pkpass…", systemImage: "plus.rectangle.on.rectangle") { isImporting = true }
                .buttonStyle(.bordered)
            #endif
        }
        #if os(iOS) || os(macOS)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [UTType("com.apple.pkpass") ?? UTType(filenameExtension: "pkpass") ?? .data]) { result in
            switch result {
            case .success(let url): wallet.importPass(from: url)
            case .failure(let error): wallet.importFailed(error)
            }
        }
        #endif
        #if canImport(PassKit) && os(iOS)
        .sheet(isPresented: Binding(get: { wallet.passToAdd != nil }, set: { presented in
            if !presented, let pass = wallet.passToAdd { wallet.addSheetFinished(pass) }
        })) {
            if let pass = wallet.passToAdd {
                AddPassesSheet(pass: pass) { wallet.addSheetFinished(pass) }
            }
        }
        #endif
        OutputView(text: wallet.output, isError: wallet.isError)
        Section("Passes visible to this app (\(wallet.passes.count))") {
            if wallet.passes.isEmpty {
                Text(wallet.hasRead ? "PKPassLibrary returned no passes for this app." : "Read the library to list the passes PassKit returns for this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(wallet.passes) { pass in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pass.name).font(.headline)
                        Text("\(pass.organization) · \(pass.detail)").font(.caption)
                        Text("\(pass.kind) · \(pass.location)").font(.caption).foregroundStyle(.secondary)
                        Text("\(pass.passTypeIdentifier) · \(pass.serialNumber)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct ApplePayRunView: View {
    @StateObject private var pay = ApplePayService()

    var body: some View {
        LabeledContent("Merchant ID (placeholder)") {
            Text(ApplePayOptions.placeholderMerchantID).font(.caption.monospaced()).multilineTextAlignment(.trailing)
        }
        Text("This is not a registered Merchant ID. Apple Pay only completes payments for a Merchant ID listed in the app's Apple Pay entitlement, backed by a payment processing certificate, so the request below is expected to fail and is never charged.")
            .font(.caption)
            .foregroundStyle(.secondary)
        Picker("Country and currency", selection: $pay.region) {
            ForEach(ApplePayOptions.Region.allCases) { Text($0.rawValue).tag($0) }
        }
        Picker("Button type", selection: $pay.buttonType) {
            ForEach(ApplePayOptions.ButtonType.allCases) { Text($0.rawValue).tag($0) }
        }
        Picker("Button style", selection: $pay.buttonStyle) {
            ForEach(ApplePayOptions.ButtonStyle.allCases) { Text($0.rawValue).tag($0) }
        }
        #if canImport(PassKit) && (os(iOS) || os(macOS))
        PaymentButtonView(type: pay.buttonType.paymentButtonType, style: pay.buttonStyle.paymentButtonStyle, action: pay.pay)
            .id(pay.buttonType.rawValue + pay.buttonStyle.rawValue)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .disabled(pay.isPresenting)
        #endif
        Button("Check Payment Networks", systemImage: "creditcard", action: pay.checkNetworks)
            .buttonStyle(.bordered)
        OutputView(text: pay.output, isError: pay.isError)
        if !pay.networks.isEmpty {
            Section("canMakePayments(usingNetworks:)") {
                ForEach(pay.networks) { result in
                    LabeledContent(result.network.rawValue) {
                        Label(result.canMakePayments ? "Card available" : "No card", systemImage: result.canMakePayments ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(result.canMakePayments ? .green : .secondary)
                    }
                }
            }
        }
    }
}

#if canImport(PassKit) && os(iOS)
/// Hosts PKAddPassesViewController, which shows the pass and lets the person add it to Wallet.
private struct AddPassesSheet: UIViewControllerRepresentable {
    let pass: PKPass
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIViewController {
        guard let controller = PKAddPassesViewController(pass: pass) else {
            return UIHostingController(rootView: Text("PassKit could not create the add-pass sheet for this pass.").padding())
        }
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) { onFinish() }
    }
}

/// The system Apple Pay button; its type and style are fixed at creation, so the view is recreated when they change.
private struct PaymentButtonView: UIViewRepresentable {
    let type: PKPaymentButtonType
    let style: PKPaymentButtonStyle
    let action: () -> Void

    func makeCoordinator() -> PaymentButtonTarget { PaymentButtonTarget(action: action) }

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: type, paymentButtonStyle: style)
        button.addTarget(context.coordinator, action: #selector(PaymentButtonTarget.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: PKPaymentButton, context: Context) {
        context.coordinator.action = action
    }
}
#elseif canImport(PassKit) && os(macOS)
private struct PaymentButtonView: NSViewRepresentable {
    let type: PKPaymentButtonType
    let style: PKPaymentButtonStyle
    let action: () -> Void

    func makeCoordinator() -> PaymentButtonTarget { PaymentButtonTarget(action: action) }

    func makeNSView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: type, paymentButtonStyle: style)
        button.target = context.coordinator
        button.action = #selector(PaymentButtonTarget.tapped)
        return button
    }

    func updateNSView(_ button: PKPaymentButton, context: Context) {
        context.coordinator.action = action
    }
}
#endif

#if canImport(PassKit) && (os(iOS) || os(macOS))
final class PaymentButtonTarget: NSObject {
    var action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func tapped() { action() }
}
#endif
