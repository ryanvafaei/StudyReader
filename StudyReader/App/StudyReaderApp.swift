import SwiftUI

@main
struct StudyReaderApp: App {
    @State private var launchModel = AppLaunchModel()

    var body: some Scene {
        Window("StudyReader", id: "main") {
            LaunchView(model: launchModel)
        }
        .defaultSize(width: 1100, height: 720)
    }
}
