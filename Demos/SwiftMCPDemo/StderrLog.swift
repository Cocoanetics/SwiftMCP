import Foundation

/// Log a message to stderr.
///
/// Lives outside the `#if Server` transport command files because it is also
/// used by the always-built demo server sources (e.g. resource providers).
func logToStderr(_ message: String) {
	guard let data = (message + "\n").data(using: .utf8) else { return }
	try? FileHandle.standardError.write(contentsOf: data)
}
