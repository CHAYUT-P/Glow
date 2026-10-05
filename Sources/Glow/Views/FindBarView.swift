import SwiftUI

/// Find-in-scrollback bar, minimal style: a magnifying-glass field, a match
/// counter `n/m`, and small prev/next/case/close controls. All v1 behaviour
/// kept: Enter = next, Esc closes, case toggle re-runs the search.
struct FindBarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared
    var findFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Find", text: $model.findText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused(findFocused)
                    .onAppear { findFocused.wrappedValue = true }
                    .onSubmit { model.findNext() }
                    .onChange(of: model.findText) { _ in model.onFindTextChanged() }
                    .onChange(of: findFocused.wrappedValue) { focused in
                        model.findFieldFocused = focused
                    }
                    .onExitCommand { model.closeFind() }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
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
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.55))
                .frame(minWidth: 40, alignment: .trailing)

            findButton("chevron.up", help: "Previous match (⇧⌘G)") {
                model.findPrevious()
            }
            findButton("chevron.down", help: "Next match (⌘G / Enter)") {
                model.findNext()
            }

            Button {
                model.findCaseSensitive.toggle()
                model.onFindTextChanged()
            } label: {
                Text("Aa")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        model.findCaseSensitive
                            ? Color(nsColor: appModel.theme.accent)
                            : Color(nsColor: appModel.theme.foreground).opacity(0.6)
                    )
                    .frame(width: 26, height: 22)
                    .background(Rectangle().fill(
                        model.findCaseSensitive
                            ? Color(nsColor: appModel.theme.accent).opacity(0.18)
                            : Color.primary.opacity(0.001)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Case sensitive")

            findButton("xmark", help: "Close (Esc)") {
                model.closeFind()
            }
        }
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

    private func findButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.6))
                .frame(width: 24, height: 22)
                .background(Rectangle().fill(Color.primary.opacity(0.001)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
