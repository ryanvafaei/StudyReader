import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("ExternalURLRouter")
struct ExternalURLRouterTests {
    /// Records every batch the router delivers.
    @MainActor
    final class Recorder {
        private(set) var batches: [[URL]] = []

        func handler() -> @MainActor ([URL]) -> Void {
            { [self] urls in
                batches.append(urls)
            }
        }
    }

    private let first = URL(filePath: "/tmp/a.pdf")
    private let second = URL(filePath: "/tmp/b.md")
    private let third = URL(filePath: "/tmp/c.pdf")

    @Test("URLs received before a handler is attached are buffered in order")
    func buffersBeforeAttach() {
        let router = ExternalURLRouter()
        router.receive([first])
        router.receive([second, third])

        #expect(router.pendingURLs == [first, second, third])
    }

    @Test("attach delivers the buffered URLs once and clears the buffer")
    func attachFlushesBuffer() {
        let router = ExternalURLRouter()
        let recorder = Recorder()
        router.receive([first, second])

        router.attach(recorder.handler())

        #expect(recorder.batches == [[first, second]])
        #expect(router.pendingURLs.isEmpty)
    }

    @Test("attach with an empty buffer delivers nothing")
    func attachWithoutBufferDeliversNothing() {
        let router = ExternalURLRouter()
        let recorder = Recorder()

        router.attach(recorder.handler())

        #expect(recorder.batches.isEmpty)
    }

    @Test("URLs received after attach go straight to the handler and are not buffered")
    func directDeliveryAfterAttach() {
        let router = ExternalURLRouter()
        let recorder = Recorder()
        router.attach(recorder.handler())

        router.receive([first])

        #expect(recorder.batches == [[first]])
        #expect(router.pendingURLs.isEmpty)
    }

    @Test("A second attach does not deliver the same URLs again")
    func reattachDoesNotRedeliver() {
        let router = ExternalURLRouter()
        let firstRecorder = Recorder()
        let secondRecorder = Recorder()
        router.receive([first])
        router.attach(firstRecorder.handler())

        router.attach(secondRecorder.handler())

        #expect(firstRecorder.batches == [[first]])
        #expect(secondRecorder.batches.isEmpty)
    }

    @Test("Later URLs go to the most recently attached handler")
    func reattachReplacesHandler() {
        let router = ExternalURLRouter()
        let oldRecorder = Recorder()
        let newRecorder = Recorder()
        router.attach(oldRecorder.handler())

        router.attach(newRecorder.handler())
        router.receive([second])

        #expect(oldRecorder.batches.isEmpty)
        #expect(newRecorder.batches == [[second]])
    }

    @Test("An empty batch is ignored and does not reach the handler")
    func emptyBatchIgnored() {
        let router = ExternalURLRouter()
        let recorder = Recorder()
        router.attach(recorder.handler())

        router.receive([])

        #expect(recorder.batches.isEmpty)
        #expect(router.pendingURLs.isEmpty)
    }
}
