import Foundation
import Dispatch
import SwiftMCP

// Keep a reference to the signal source so it isn't deallocated
fileprivate var sigintSource: DispatchSourceSignal?

/// Sets up a modern Swift signal handler for SIGINT.
func setupSignalHandler(transport: HTTPSSETransport) {
	// Create a dedicated dispatch queue for signal handling.
	let signalQueue = DispatchQueue(label: "com.cocoanetics.signalQueue")
	// Create a dispatch source on that queue.
	sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)

	// Tell the system to ignore the default SIGINT handler.
	signal(SIGINT, SIG_IGN)

	// Specify what to do when the signal is received.
	sigintSource?.setEventHandler {
		print("\nShutting down...")

		try? transport.stop()
		Foundation.exit(0)
	}

	// Start listening for the signal.
	sigintSource?.resume()
}
