import SwiftUI

/// Shows progress while the library opens, the main window once it is ready, or an error if it can't open.
struct LaunchView: View {
    let model: AppLaunchModel

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("Opening library…")
            case .ready(let environment):
                RootView(environment: environment)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't open the library", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            }
        }
        .task { model.start() }
    }
}

#Preview {
    LaunchView(model: AppLaunchModel(makeEnvironment: { try AppEnvironment.inMemory() }))
}
