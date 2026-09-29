import SwiftUI
import WidgetKit
import ActivityKit

/// Draws the Live Activities experiment's measurement run (ToolboxActivityAttributes) on the Lock Screen
/// and in the Dynamic Island.
struct ToolboxLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ToolboxActivityAttributes.self) { context in
            ToolboxActivityLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("\(context.state.sample)/\(context.state.totalSamples)").monospacedDigit()
                    } icon: {
                        Image(systemName: context.attributes.symbolName)
                    }
                    .font(.headline)
                    .foregroundStyle(.teal)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimerText(context: context)
                        .font(.headline)
                        .frame(maxWidth: 72, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.runName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: context.state.progress)
                            .tint(.teal)
                        Text(context.state.reading).font(.caption.weight(.medium))
                        Text(context.isStale ? "Stale: the app stopped updating" : context.state.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbolName)
                    .foregroundStyle(.teal)
            } compactTrailing: {
                ActivityTimerText(context: context)
                    .frame(maxWidth: 44)
            } minimal: {
                ProgressView(value: context.state.progress) {
                    Image(systemName: context.attributes.symbolName)
                }
                .progressViewStyle(.circular)
                .tint(.teal)
            }
            .keylineTint(.teal)
        }
    }
}

/// Elapsed time while measuring (rendered by the system without updates), the final state afterwards.
private struct ActivityTimerText: View {
    let context: ActivityViewContext<ToolboxActivityAttributes>

    var body: some View {
        if context.state.phase == .measuring {
            Text(timerInterval: context.attributes.startedAt...context.attributes.plannedEnd, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

private struct ToolboxActivityLockScreenView: View {
    let context: ActivityViewContext<ToolboxActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(context.attributes.runName, systemImage: context.attributes.symbolName)
                    .font(.headline)
                Spacer()
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.isStale ? .orange : .teal)
            }
            if context.state.phase == .measuring {
                ProgressView(timerInterval: context.attributes.startedAt...context.attributes.plannedEnd, countsDown: false) {
                    Text("Sample \(context.state.sample) of \(context.state.totalSamples)")
                        .font(.caption)
                } currentValueLabel: {
                    Text(timerInterval: context.attributes.startedAt...context.attributes.plannedEnd, countsDown: true)
                        .font(.caption.monospacedDigit())
                }
                .tint(.teal)
            } else {
                ProgressView(value: context.state.progress) {
                    Text("Finished after \(context.state.sample) samples").font(.caption)
                }
                .tint(.green)
            }
            Text(context.state.reading).font(.subheadline.weight(.medium))
            Text("\(context.state.detail) · updated \(context.state.updatedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var badge: String {
        if context.state.phase == .finished { return "Finished" }
        return context.isStale ? "Stale" : "Live"
    }
}
