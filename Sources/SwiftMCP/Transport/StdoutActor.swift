import Foundation

#if canImport(Glibc)
@preconcurrency import Glibc
#endif

/// Actor to handle stdout access safely.
actor StdoutActor {
	static let shared = StdoutActor()
	
	/// Prints the given text and flushes stdout.
	func printAndFlush(_ text: String) {
		Swift.print(text)
		fflush(stdout)
	}
	
	/// Flushes stdout.
	func flush() {
		fflush(stdout)
	}
}
