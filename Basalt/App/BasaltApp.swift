import SwiftUI

@main
struct BasaltApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(appModel.webSearchSettings)
                .onOpenURL(perform: appModel.handleOpenURL)
        }
    }
}
