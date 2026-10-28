import SwiftUI

extension View {
    /// Routes every link click inside this view through `LinkPolicy`: openable → `.systemAction`, else `.discarded`.
    func studyReaderLinkPolicy() -> some View {
        environment(\.openURL, OpenURLAction { url in
            LinkPolicy.isOpenable(url) ? .systemAction : .discarded
        })
    }
}
