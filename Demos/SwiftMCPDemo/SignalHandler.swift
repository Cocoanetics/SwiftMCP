import Foundation
import Dispatch
import SwiftMCP

/// Handles SIGINT signals for graceful shutdown of one or more transports.
public final class SignalHandler {
	/// Actor to manage signal handling state in a thread-safe way
	private actor State {
		private var sigintSource: DispatchSourceSignal?
		private var isShuttingDown = false
		private var transports: [any Transport]
		
		init(transports: [any Transport]) {
			self.transports = transports
		}
		
		func setupHandler(on queue: DispatchQueue) {
			// Create a dispatch source on the provided queue
			sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
			
			// Tell the system to ignore the default SIGINT handler
			signal(SIGINT, SIG_IGN)
			
			// Specify what to do when the signal is received
			sigintSource?.setEventHandler { [weak self] in
				Task { [weak self] in
					await self?.handleSignal()
				}
			}
			
			// Start listening for the signal
			sigintSource?.resume()
		}
		
		private func handleSignal() async {
			// Prevent multiple shutdown attempts
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
	
	// Instance state
	private let state: State
	
	/// Creates a new signal handler for a single transport.
	public init(transport: HTTPSSETransport) {
		self.state = State(transports: [transport])
	}

	/// Creates a new signal handler for multiple transports.
	public init(transports: [any Transport]) {
		self.state = State(transports: transports)
	}
	
	/// Sets up the SIGINT handler
	public func setup() async {
		// Create a dedicated dispatch queue for signal handling
		let signalQueue = DispatchQueue(label: "com.cocoanetics.signalQueue")
		await state.setupHandler(on: signalQueue)
	}
}
