#if Server
import Foundation

extension SessionManager {
    internal func parseEventID(_ value: String) throws -> (streamID: UUID, sequence: Int) {
        guard let separatorIndex = value.lastIndex(of: ":") else {
            throw StreamResumeError.malformedEventID
        }

        let streamPart = String(value[..<separatorIndex])
        let sequencePart = String(value[value.index(after: separatorIndex)...])

        guard let streamID = UUID(uuidString: streamPart),
              let sequence = Int(sequencePart),
              sequence >= 1 else {
            throw StreamResumeError.malformedEventID
        }

        return (streamID, sequence)
    }

    internal func makeEventID(streamID: UUID, sequence: Int) -> String {
        "\(streamID.uuidString):\(sequence)"
    }
}
#endif
