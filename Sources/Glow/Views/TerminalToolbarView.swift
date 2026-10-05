import SwiftUI

/// Bottom bar for the terminal area — minimal status line: the focused
/// pane's title + abbreviated cwd on the left, and a row of icon buttons on
/// the right (attach files, copy last output, clear scrollback).
struct TerminalToolbarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared

    /// Git branch of the focused pane's cwd. Re-read on cwd change and on a
    /// slow tick, so a `git checkout` shows up without leaving the folder.
    @State private var branch: String?
    private let branchTick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            // Left: context — focused pane title / abbreviated cwd
            if let session = model.selectedSession {
                Text(session.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.8))
                    .lineLimit(1)
                    .help(session.cwd)
                Text(shortPath(session.cwd))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .help(session.cwd)
                if let branch {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9, weight: .medium))
                        Text(branch)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.55))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(
                        Rectangle()
                            .stroke(Color(nsColor: appModel.theme.separator), lineWidth: 1)
                    )
                    .help("Git branch: \(branch)")
                    .transition(.opacity)
                }
            } else {
                Text("No terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 2) {
                toolbarButton("paperclip", help: "Attach Files… (⇧⌘A) — inserts file paths into the terminal") {
                    model.insertPickedFiles()
                }
                toolbarButton("doc.on.doc", help: "Copy Last Output (⇧⌘C)") {
                    model.copyLastOutput()
                }
                toolbarButton("eraser", help: "Clear Scrollback (⌘K)") {
                    model.clearScrollback()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.15), value: branch)
        .onAppear(perform: refreshBranch)
        .onChange(of: model.selectedSession?.cwd) { _ in refreshBranch() }
        .onReceive(branchTick) { _ in refreshBranch() }
        .background(Color(nsColor: appModel.theme.chrome))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: appModel.theme.separator))
                .frame(height: 1)
        }
    }

    private func refreshBranch() {
        let next = model.selectedSession.flatMap { GitBranch.current(at: $0.cwd) }
        if next != branch { branch = next }
    }

    private func toolbarButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.6))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .background(Rectangle().fill(Color.primary.opacity(0.001)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
