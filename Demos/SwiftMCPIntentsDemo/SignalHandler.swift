import Foundation
import Dispatch
import SwiftMCP

/// Handles SIGINT signals for graceful shutdown of one or more transports.
public final class SignalHandler {
    private actor State {
        private var sigintSource: DispatchSourceSignal?
        private var isShuttingDown = false
        private var transports: [any Transport]
        
        init(transports: [any Transport]) {
            self.transports = transports
        }
        
        func setupHandler(on queue: DispatchQueue) {
            sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
            signal(SIGINT, SIG_IGN)
            sigintSource?.setEventHandler { [weak self] in
                Task { [weak self] in
                    await self?.handleSignal()
                }
            }
            sigintSource?.resume()
        }
        
        private func handleSignal() async {
            guard !isShuttingDown else { return }
            isShuttingDown = true
            
            print("\nShutting down...")
            
            guard !transports.isEmpty else {
                print("No transports available")
                Foundation.exit(1)
            }
            
            var errors: [Error] = []
            for transport in transports {
                do {
                    try await transport.stop()
                } catch {
                    errors.append(error)
                }
            }
            
            if errors.isEmpty {
                Foundation.exit(0)
            } else {
                print("Error during shutdown: \(errors)")
                Foundation.exit(1)
            }
        }
    }
    
    private let state: State
    
    public init(transport: HTTPSSETransport) {
        self.state = State(transports: [transport])
    }

    public init(transports: [any Transport]) {
        self.state = State(transports: transports)
    }
    
    public func setup() async {
        let signalQueue = DispatchQueue(label: "com.cocoanetics.signalQueue")
        await state.setupHandler(on: signalQueue)
    }
}

