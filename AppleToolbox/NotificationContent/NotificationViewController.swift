import UIKit
import SwiftUI
import Combine
import UserNotifications
import UserNotificationsUI

/// Draws the expanded UI of `toolbox.report` notifications (ToolboxNotificationCategory.report): the device report
/// the app put into the notification's userInfo. The Acknowledge action is handled here without opening the app;
/// every other action is forwarded to the app's notification delegate.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let model = ReportNotificationModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ReportNotificationView(model: model) { [weak self] in
            self?.extensionContext?.performNotificationDefaultAction()
        })
        host.sizingOptions = .preferredContentSize
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        preferredContentSize = container.preferredContentSize
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        model.title = content.title
        model.report = ToolboxNotificationReport(userInfo: content.userInfo)
        model.deliveredAt = notification.date
        model.attachmentCount = content.attachments.count
    }

    // Called on the extension's callback queue; the decision only needs the action identifier.
    nonisolated func didReceive(_ response: UNNotificationResponse, completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        guard response.actionIdentifier == ToolboxNotificationAction.acknowledge else {
            completion(.dismissAndForwardAction)
            return
        }
        completion(.doNotDismiss)
        Task { @MainActor [weak self] in self?.acknowledge() }
    }

    private func acknowledge() {
        model.acknowledgedAt = Date()
        // Actions can be replaced while the notification is expanded.
        extensionContext?.notificationActions = [
            UNNotificationAction(identifier: ToolboxNotificationAction.open, title: "Open Experiment", options: [.foreground],
                                 icon: UNNotificationActionIcon(systemImageName: "arrow.up.forward.app")),
        ]
    }
}

final class ReportNotificationModel: ObservableObject {
    @Published var title = ""
    @Published var report: ToolboxNotificationReport?
    @Published var deliveredAt: Date?
    @Published var attachmentCount = 0
    @Published var acknowledgedAt: Date?
}

private struct ReportNotificationView: View {
    @ObservedObject var model: ReportNotificationModel
    let openApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Drawn by the notification content extension", systemImage: "puzzlepiece.extension")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let report = model.report {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(report.available)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("of \(report.total) experiments available on \(report.platform)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(report.available), total: Double(max(report.total, 1)))
                    .tint(.green)
                ForEach(report.buckets.prefix(5), id: \.title) { bucket in
                    HStack {
                        Text(bucket.title).font(.caption)
                        Spacer()
                        Text("\(bucket.count)").font(.caption.monospacedDigit().weight(.semibold))
                    }
                }
                Text("Measured \(report.measuredAt.formatted(date: .omitted, time: .standard)) · \(model.attachmentCount) attachment(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("“\(model.title)” carries no Apple Toolbox report in its userInfo, so there is nothing to draw.")
                    .font(.subheadline)
            }
            if let acknowledgedAt = model.acknowledgedAt {
                Label("Acknowledged inside the extension at \(acknowledgedAt.formatted(date: .omitted, time: .standard)); the app was not opened.",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Button("Open Apple Toolbox", systemImage: "arrow.up.forward.app", action: openApp)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
