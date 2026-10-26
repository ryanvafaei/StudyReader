import SwiftUI

@main
struct StudyReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var launchModel = AppLaunchModel()

    init() {
        // Read the test-host signals before anything can open a library (ADR-0011).
        _ = AppEnvironment.launchTestHostSignals
    }

    var body: some Scene {
        Window("StudyReader", id: "main") {
            LaunchView(model: launchModel)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            AppCommands()
            #if DEBUG
            DebugCommands(launchModel: launchModel)
            #endif
        }

        // One window per open document; each joins the main window's tab group (ADR-0017, T52).
        WindowGroup(id: ReaderRouter.windowId, for: String.self) { $documentId in
            ReaderWindowRoot(documentId: documentId, launchModel: launchModel)
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsRootView(launchModel: launchModel)
        }
    }
}
