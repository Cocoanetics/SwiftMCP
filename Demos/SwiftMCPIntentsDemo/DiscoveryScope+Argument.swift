#if Server
import ArgumentParser
import SwiftMCP

/// Lets `--scope` take `local-user`, `local-machine`, or `local-network`.
///
/// The conformance lives in the demo rather than in SwiftMCP so the library does
/// not take an ArgumentParser dependency for a CLI convenience.
extension DiscoveryScope: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "local-user", "localuser", "user": self = .localUser
        case "local-machine", "localmachine", "machine": self = .localMachine
        case "local-network", "localnetwork", "network", "lan": self = .localNetwork
        default: return nil
        }
    }

    public var defaultValueDescription: String {
        switch self {
        case .localUser: return "local-user"
        case .localMachine: return "local-machine"
        case .localNetwork: return "local-network"
        }
    }

    public static var allValueStrings: [String] {
        ["local-user", "local-machine", "local-network"]
    }
}
#endif
