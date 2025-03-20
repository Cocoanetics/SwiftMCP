import Foundation
import Dispatch
import SwiftMCP

/// Handles SIGINT signals for graceful shutdown of the HTTP SSE transport
public final class SignalHandler {
	/// Actor to manage signal handling state in a thread-safe way
	private actor State {
		private var sigintSource: DispatchSourceSignal?
		private var isShuttingDown = false
		private weak var transport: HTTPSSETransport?
		
		init(transport: HTTPSSETransport) {
			self.transport = transport
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
			
			guard let transport = transport else {
				print("Transport no longer available")
				Foundation.exit(1)
				return
			}
			
			do {
				try await transport.stop()
				Foundation.exit(0)
			} catch {
				print("Error during shutdown: \(error)")
				Foundation.exit(1)
			}
		}
	}
	
	// Instance state
	private let state: State
	
	/// Creates a new signal handler for the given transport
	public init(transport: HTTPSSETransport) {
		self.state = State(transport: transport)
	}
	
	/// Sets up the SIGINT handler
	public func setup() async {
		// Create a dedicated dispatch queue for signal handling
		let signalQueue = DispatchQueue(label: "com.cocoanetics.signalQueue")
		await state.setupHandler(on: signalQueue)
	}
}
