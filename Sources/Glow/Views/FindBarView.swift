import SwiftUI

struct FindBarView: View {
    @ObservedObject var model: WindowModel
    var findFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find in scrollback", text: $model.findText)
                .textFieldStyle(.roundedBorder)
                .focused(findFocused)
                .onAppear { findFocused.wrappedValue = true }
                .onSubmit { model.findNext() }
                .onChange(of: model.findText) { _ in model.onFindTextChanged() }
                .onExitCommand { model.closeFind() }
            Text(model.findMatchTotal == 0 ? "" : "\(model.findMatchIndex)/\(model.findMatchTotal)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
            Button {
                model.findPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Previous match")
            Button {
                model.findNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Next match (Enter)")
            Toggle("Aa", isOn: $model.findCaseSensitive)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("Case sensitive")
                .onChange(of: model.findCaseSensitive) { _ in model.onFindTextChanged() }
            Button {
                model.closeFind()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
