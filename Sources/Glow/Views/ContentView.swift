import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared
    @FocusState private var findFocused: Bool

    init(request: GlowWindowRequest) {
        _model = StateObject(wrappedValue: WindowModel(request: request))
    }

    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarVisible {
                FolderSidebarView(model: model)
                    .frame(width: 210)
                Divider()
            }
            VStack(spacing: 0) {
                TabBarView(model: model)
                ZStack {
                    ForEach(model.tabs) { session in
                        TerminalHostView(
                            session: session,
                            isActive: session.id == model.selectedTabID,
                            suppressFocus: model.findVisible
                        )
                        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: appModel.theme.background))
                if model.findVisible {
                    FindBarView(model: model, findFocused: $findFocused)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .preferredColorScheme(appModel.theme.colorScheme)
        .focusedSceneValue(\.windowModel, model)
        .environmentObject(model)
        .onChange(of: model.findFocusRequest) { _ in
            findFocused = true
        }
    }
}
