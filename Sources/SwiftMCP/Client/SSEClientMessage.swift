import Foundation

struct SSEClientMessage {
    let event: String
    let data: String
    let id: String?
    let retry: Int?
}
