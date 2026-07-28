#if Server
import Foundation

/**
 Errors that can occur during transport operations in SwiftMCP.
 
 This enum provides specific error types and localized descriptions for various
 transport-related failures, such as binding failures when starting a server.
 */
public enum TransportError: LocalizedError {
    /**
     Indicates that the transport failed to bind to a specific address and port.
	 
     - Parameter message: A human-readable description of the binding failure,
       including details about the specific cause (e.g., port in use, permission denied).
     */
    case bindingFailed(String)

    /**
     Indicates that the transport hit a process-level resource limit it cannot
     recover from — today, file-descriptor exhaustion (`EMFILE`/`ENFILE`).

     Terminal by design: a process out of descriptors accepts nothing while its
     listener still looks healthy from the outside, so the transport fails its
     `run()` loudly rather than serving nothing forever.

     - Parameter message: A human-readable description of the exhausted resource.
     */
    case resourceExhausted(String)

    /**
     Provides a localized description of the error.
	 
     - Returns: A human-readable string describing the error.
     */
    public var errorDescription: String? {
        switch self {
        case .bindingFailed(let message):
            return message
        case .resourceExhausted(let message):
            return message
        }
    }
}
#endif
