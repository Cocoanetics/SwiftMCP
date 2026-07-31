#if Server
import Foundation
import Testing

@testable import SwiftMCP

@Suite("File response streaming")
struct FileResponseStreamingTests {

    private func makeTempFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmcp-file-response-\(UUID().uuidString).bin")
        var data = Data(capacity: bytes)
        var seed: UInt8 = 0
        for _ in 0..<bytes {
            data.append(seed)
            seed &+= 1
        }
        try data.write(to: url)
        return url
    }

    @Test("Streamed content matches the file byte-for-byte")
    func contentIntegrity() async throws {
        let url = try makeTempFile(bytes: 300_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let response = HTTPRouteResponse<AsyncStream<Data>>.file(
            url, contentType: "application/octet-stream", chunkSize: 4096)

        var received = Data()
        for await chunk in response.body {
            // Chunks must respect the requested size — the pull-based reader
            // never hands out more than one chunk per demand.
            #expect(chunk.count <= 4096)
            received.append(chunk)
        }
        #expect(received == (try Data(contentsOf: url)))
    }

    @Test("The file is opened lazily, on first demand")
    func lazyOpen() async throws {
        let url = try makeTempFile(bytes: 1024)

        let response = HTTPRouteResponse<AsyncStream<Data>>.file(
            url, contentType: "application/octet-stream")

        // Delete the file before any consumption. An eager producer would
        // already have opened (and begun reading) it; the pull-based reader
        // must come up empty instead of serving a half-read body.
        try FileManager.default.removeItem(at: url)

        var received = Data()
        for await chunk in response.body {
            received.append(chunk)
        }
        #expect(received.isEmpty)
    }
}
#endif
