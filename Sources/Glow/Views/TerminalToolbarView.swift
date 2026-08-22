import SwiftUI

/// Bottom toolbar for the terminal area — terminal-styled status line:
/// monospace, focused pane title + zsh-abbreviated cwd on the left, and
/// self-describing `[action ⌘shortcut]` buttons on the right so features
/// are discoverable without tooltips.
struct TerminalToolbarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared

    var body: some View {
        HStack(spacing: 12) {
            // Left: context — focused pane title / abbreviated cwd
            if let session = model.selectedSession {
                Text(session.title)
                    .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.8))
                    .lineLimit(1)
                    .help(session.cwd)
                Text(shortPath(session.cwd))
                    .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .help(session.cwd)
            } else {
                Text("no terminal")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 2) {
                toolbarButton("[attach ⇧⌘A]", help: "Attach File… (⇧⌘A) — inserts file paths") {
                    model.insertPickedFiles()
                }
                toolbarButton("[copy-out ⇧⌘C]", help: "Copy Last Output (⇧⌘C)") {
                    model.copyLastOutput()
                }
                toolbarButton("[clear ⌘K]", help: "Clear Scrollback (⌘K)") {
                    model.clearScrollback()
                }
            }
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: appModel.theme.chrome))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: appModel.theme.separator))
                .frame(height: 1)
        }
    }

    private func toolbarButton(_ label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.6))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .background(Rectangle().fill(Color.primary.opacity(0.001)))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help(help)
    }
}
