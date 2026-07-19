import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 340)
        } detail: {
            ZStack {
                MineralCanvas()
                detail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $appModel.isImportSheetPresented) {
            ImportModelSheet()
                .environmentObject(appModel)
        }
        .alert(item: $appModel.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appModel.destination {
        case .conversation:
            ChatView()
                .id(appModel.selectedConversation?.id)
        case .models:
            ModelLibraryView()
        case .settings:
            SettingsView()
        case nil:
            ContentUnavailableView(
                "Welcome to Basalt",
                systemImage: "cube.transparent",
                description: Text("Choose a conversation or import a model.")
            )
        }
    }
}

