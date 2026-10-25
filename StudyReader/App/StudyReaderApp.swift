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

        Settings {
            SettingsRootView(launchModel: launchModel)
        }
    }
}
