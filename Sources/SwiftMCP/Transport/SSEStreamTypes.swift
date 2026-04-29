import Foundation

enum SSEStreamKind: Sendable {
    case legacyGeneral
    case general
    case request

    var isGeneral: Bool {
        switch self {
        case .legacyGeneral, .general:
            return true
        case .request:
            return false
        }
    }
}

struct OutboundStreamContext: Sendable {
    let streamID: UUID
    let kind: SSEStreamKind
}

struct StreamRouteResponseInfo: Sendable {
    let sessionID: UUID
    let streamID: UUID
}
