import SwiftUI

/// Find-in-scrollback bar, styled as a terminal search prompt: a `/` prefix
/// inside the field, monospace match counter `n/m`, bracketed controls.
/// All v1 behaviour kept: Enter = next, Esc closes, case toggle re-runs.
struct FindBarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared
    var findFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("/")
                    .foregroundStyle(Color(nsColor: appModel.theme.accent))
                    .padding(.leading, 7)
                TextField("find in scrollback", text: $model.findText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 5)
                    .focused(findFocused)
                    .onAppear { findFocused.wrappedValue = true }
                    .onSubmit { model.findNext() }
                    .onChange(of: model.findText) { _ in model.onFindTextChanged() }
                    .onExitCommand { model.closeFind() }
            }
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .frame(maxWidth: 320)
            .background(
                Rectangle()
                    .fill(Color(nsColor: appModel.theme.background))
                    .overlay(
                        Rectangle()
                            .stroke(Color(nsColor: appModel.theme.separator), lineWidth: 1)
                    )
            )

            Text(matchSummary)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.55))
                .frame(minWidth: 48, alignment: .trailing)

            findButton((), label: "[↑]", help: "Previous match (⇧⌘G)") {
                model.findPrevious()
            }
            findButton((), label: "[↓]", help: "Next match (⌘G / Enter)") {
                model.findNext()
            }

            Button {
                model.findCaseSensitive.toggle()
                model.onFindTextChanged()
            } label: {
                Text("[Aa]")
                    .foregroundStyle(
                        model.findCaseSensitive
                            ? Color(nsColor: appModel.theme.accent)
                            : Color(nsColor: appModel.theme.foreground).opacity(0.6)
                    )
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Rectangle().fill(
                        model.findCaseSensitive
                            ? Color(nsColor: appModel.theme.accent).opacity(0.18)
                            : Color.primary.opacity(0.001)))
            }
            .buttonStyle(.plain)
            .help("Case sensitive")

            findButton((), label: "[×]", help: "Close (Esc)") {
                model.closeFind()
            }
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: appModel.theme.chrome))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: appModel.theme.separator))
                .frame(height: 1)
        }
    }

    private var matchSummary: String {
        model.findMatchTotal == 0 && model.findText.isEmpty ? "" : "\(model.findMatchIndex)/\(model.findMatchTotal)"
    }

    /// Bracketed monospace button with hover highlight.
    private func findButton(_: Void, label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.6))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Rectangle().fill(Color.primary.opacity(0.001)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
