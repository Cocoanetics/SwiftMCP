#if Server
import Foundation
import Testing

@testable import SwiftMCP

@Suite("Inbound body buffer")
struct InboundBodyBufferTests {

    private final class WatermarkRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _pauses = 0
        private var _resumes = 0

        var pauses: Int {
            lock.lock()
            defer { lock.unlock() }
            return _pauses
        }
        var resumes: Int {
            lock.lock()
            defer { lock.unlock() }
            return _resumes
        }
        func pause() {
            lock.lock()
            _pauses += 1
            lock.unlock()
        }
        func resume() {
            lock.lock()
            _resumes += 1
            lock.unlock()
        }
    }

    private func makeBuffer(recorder: WatermarkRecorder) -> InboundBodyBuffer {
        InboundBodyBuffer(
            pauseReads: { recorder.pause() },
            resumeReads: { recorder.resume() }
        )
    }

    @Test("Chunks flow through in order and the stream ends on finish")
    func chunksFlowInOrder() async {
        let buffer = makeBuffer(recorder: WatermarkRecorder())
        let chunks = [Data([1, 2]), Data([3]), Data([4, 5, 6])]
        for chunk in chunks {
            buffer.append(chunk)
        }
        buffer.finish()

        var received: [Data] = []
        for await chunk in buffer.stream {
            received.append(chunk)
        }
        #expect(received == chunks)
    }

    @Test("A parked consumer is resumed by the next append")
    func parkedConsumerResumes() async {
        let buffer = makeBuffer(recorder: WatermarkRecorder())

        let consumer = Task { () -> Data? in
            var iterator = buffer.stream.makeAsyncIterator()
            return await iterator.next()
        }
        // Give the consumer a moment to park on the empty buffer.
        try? await Task.sleep(for: .milliseconds(50))
        buffer.append(Data([9]))

        let received = await consumer.value
        #expect(received == Data([9]))
    }

    @Test("Exceeding the high watermark pauses reads; draining resumes them")
    func watermarksPauseAndResumeReads() async {
        let recorder = WatermarkRecorder()
        let buffer = makeBuffer(recorder: recorder)

        // Fill past the high watermark without a consumer.
        let chunk = Data(repeating: 0, count: 256 << 10)
        for _ in 0..<5 {  // 5 × 256 KiB = 1.25 MiB > 1 MiB high watermark
            buffer.append(chunk)
        }
        #expect(recorder.pauses == 1)
        #expect(recorder.resumes == 0)

        // Drain below the low watermark (256 KiB): after consuming all five
        // chunks the buffer is empty, which is below any watermark.
        var iterator = buffer.stream.makeAsyncIterator()
        for _ in 0..<5 {
            _ = await iterator.next()
        }
        #expect(recorder.resumes == 1)
        // No repeated pause/resume churn for a single crossing.
        #expect(recorder.pauses == 1)
    }

    @Test("Abort ends the stream immediately for a parked consumer")
    func abortUnparksConsumer() async {
        let buffer = makeBuffer(recorder: WatermarkRecorder())

        let consumer = Task { () -> Data? in
            var iterator = buffer.stream.makeAsyncIterator()
            return await iterator.next()
        }
        try? await Task.sleep(for: .milliseconds(50))
        buffer.abort()

        let received = await consumer.value
        #expect(received == nil)
    }

    @Test("Abort discards buffered chunks")
    func abortDiscardsBuffered() async {
        let buffer = makeBuffer(recorder: WatermarkRecorder())
        buffer.append(Data([1]))
        buffer.append(Data([2]))
        buffer.abort()

        var iterator = buffer.stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == nil)
        #expect(buffer.bufferedByteCount == 0)
    }

    @Test("Appends after finish are ignored")
    func appendAfterFinishIgnored() async {
        let buffer = makeBuffer(recorder: WatermarkRecorder())
        buffer.append(Data([1]))
        buffer.finish()
        buffer.append(Data([2]))

        var received: [Data] = []
        for await chunk in buffer.stream {
            received.append(chunk)
        }
        #expect(received == [Data([1])])
    }
}
#endif
