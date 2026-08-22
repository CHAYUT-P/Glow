import SwiftUI

struct SettingsView: View {
    @ObservedObject private var appModel = AppModel.shared

    var body: some View {
        Form {
            Picker("Font", selection: $appModel.settings.fontName) {
                ForEach(GlowTheme.fontChoices, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            HStack {
                Text("Font Size")
                Slider(value: $appModel.settings.fontSize, in: 8...24, step: 1)
                Text("\(Int(appModel.settings.fontSize))")
                    .font(.system(size: 12).monospacedDigit())
                    .frame(width: 24, alignment: .trailing)
            }
            Picker("Theme", selection: $appModel.settings.themeName) {
                ForEach(GlowTheme.all, id: \.name) { theme in
                    Text(theme.displayName).tag(theme.name)
                }
            }
            Divider()
            Toggle("Open last layout on launch", isOn: $appModel.settings.openLastLayoutOnLaunch)
            Toggle("Notify when a command finishes in the background", isOn: $appModel.settings.notifyOnCommandDone)
            Toggle("Global hotkey (Ctrl+`) to show/hide Glow", isOn: $appModel.settings.globalHotkeyEnabled)
            Divider()
            Toggle("Confirm before closing a tab with a running process", isOn: $appModel.settings.confirmBeforeClosingRunningProcess)
        }
        .padding(24)
        .frame(width: 460)
        .tint(Color(nsColor: appModel.theme.accent))
    }
}
