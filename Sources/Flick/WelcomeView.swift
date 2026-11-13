import AppKit
import SwiftUI

struct WelcomeView: View {
    @ObservedObject var model: PermissionModel
    var onAccessibility: () -> Void
    var onScreenRecording: () -> Void
    var onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Flick")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Hold Option and press Tab. Release Option on the window you want.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Keycap(label: "⌥")
                Keycap(label: "⇥")
                Spacer()
                Button("Show windows", action: onPreview)
            }

            VStack(spacing: 8) {
                PermissionRow(
                    title: "Accessibility",
                    detail: accessibilityDetail,
                    isOn: model.accessibility
                ) {
                    Button("Allow", action: onAccessibility)
                }
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Previews of each window. Switching works without this.",
                    isOn: model.screenRecording
                ) {
                    Button("Allow", action: onScreenRecording)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Option-` cycles windows in the current app.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if model.altTabRunning {
                    Text("AltTab is still running, so it may take Option-Tab first. Quit AltTab when you want Flick to handle it.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(26)
        .frame(width: 440)
    }

    private var accessibilityDetail: String {
        if !model.accessibility { return "Required for the shortcut." }
        if !model.shortcutReady { return "On. If the shortcut does nothing, quit Flick and open it again." }
        return "On."
    }
}

private struct Keycap: View {
    var label: String

    var body: some View {
        Text(label)
            .font(.system(size: 18, weight: .medium))
            .frame(width: 46, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct PermissionRow<Action: View>: View {
    var title: String
    var detail: String
    var isOn: Bool
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if isOn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            } else {
                action()
                    .controlSize(.regular)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

final class PermissionModel: ObservableObject {
    @Published var accessibility = false
    @Published var screenRecording = false
    @Published var shortcutReady = false
    @Published var altTabRunning = false
    @Published var menuBarHidden = false
}
