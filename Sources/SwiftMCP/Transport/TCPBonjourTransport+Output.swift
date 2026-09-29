//
//  TCPBonjourTransport+Output.swift
//  SwiftMCP
//
//  What the server sends one client, and — with a stall timeout — whether the
//  client takes it.
//

#if Server
import Foundation

#if canImport(Network)
import Network

/// A client connection's output.
///
/// Without a stall timeout, each message goes to the network stack whole, and a
/// send waits as long as the client leaves it unread. With one, a message goes in
/// pieces of ``pieceBytes``. Each piece the stack takes counts as progress, and so
/// does anything the client sends, as Node counts a socket's reads and writes alike.
/// When pieces are pending and nothing has moved for the timeout, the client has
/// stopped reading, and `onStall` is called once to close its connection. The
/// pending sends then end with the connection's error.
final class ConnectionOutput: @unchecked Sendable {
    /// How much of a message goes to the network stack at once under a stall timeout.
    static let pieceBytes = 64 * 1024

    private let stallTimeout: TimeInterval?
    private let queue: DispatchQueue
    private let onStall: @Sendable () -> Void
    private let lock = NSLock()
    /// Pieces handed to the stack that it has not taken yet.
    private var pending = 0
    /// When a piece was last taken, something last received, or output last began to wait.
    private var lastProgress = DispatchTime.now()
    private var timer: DispatchSourceTimer?
    /// Stalled or stopped: the timer is not armed again.
    private var finished = false

    init(stallTimeout: TimeInterval?, queue: DispatchQueue, onStall: @escaping @Sendable () -> Void) {
        self.stallTimeout = stallTimeout
        self.queue = queue
        self.onStall = onStall
    }

    /// Send `data` on `connection`: done once the network stack has taken all of it.
    func send(_ data: Data, on connection: NWConnection) async throws {
        guard let stallTimeout else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
            return
        }
        let pieces = stride(from: 0, to: data.count, by: Self.pieceBytes).map { offset in
            data.subdata(in: data.startIndex + offset..<data.startIndex + min(offset + Self.pieceBytes, data.count))
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let outcome = PiecesOutcome(count: pieces.count, continuation)
            lock.withLock {
                // All of a message's pieces are handed over together, so that no other
                // send's come between them.
                for piece in pieces {
                    if pending == 0 { lastProgress = .now() }
                    pending += 1
                    connection.send(content: piece, completion: .contentProcessed { [self] error in
                        pieceTaken()
                        outcome.piece(error)
                    })
                }
                watch(stallTimeout)
            }
        }
    }

    /// Something came from the client: the connection moves.
    func noteProgress() {
        lock.withLock { lastProgress = .now() }
    }

    /// The connection is gone: nothing more is watched.
    func stop() {
        lock.withLock {
            finished = true
            timer?.cancel()
            timer = nil
        }
    }

    private func pieceTaken() {
        lock.withLock {
            pending -= 1
            lastProgress = .now()
        }
    }

    /// Arm the stall timer, unless it is armed (the lock held).
    private func watch(_ timeout: TimeInterval) {
        guard timer == nil, !finished else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.check(timeout) }
        timer.schedule(deadline: lastProgress + timeout)
        self.timer = timer
        timer.resume()
    }

    /// At the timer: stalled once pending pieces have not moved for `timeout`; else
    /// watched again until then, or no longer once nothing is pending.
    private func check(_ timeout: TimeInterval) {
        let stalled: Bool = lock.withLock {
            guard !finished else { return false }
            guard pending > 0 else {
                timer?.cancel()
                timer = nil
                return false
            }
            let deadline = lastProgress + timeout
            guard DispatchTime.now() >= deadline else {
                timer?.schedule(deadline: deadline)
                return false
            }
            finished = true
            timer?.cancel()
            timer = nil
            return true
        }
        if stalled { onStall() }
    }
}

/// One message's pieces: the send ends at the first piece that fails, or once all are taken.
private final class PiecesOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var continuation: CheckedContinuation<Void, Error>?

    init(count: Int, _ continuation: CheckedContinuation<Void, Error>) {
        remaining = count
        self.continuation = continuation
    }

    func piece(_ error: NWError?) {
        let ending: (CheckedContinuation<Void, Error>, NWError?)? = lock.withLock {
            remaining -= 1
            guard let continuation, error != nil || remaining == 0 else { return nil }
            self.continuation = nil
            return (continuation, error)
        }
        guard let (continuation, error) = ending else { return }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
#endif
#endif
