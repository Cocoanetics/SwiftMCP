import Foundation
import Testing
@testable import SwiftMCP

@Suite("Parameter Format Round-Trip Tests")
struct ParameterFormatRoundTripTests {
    @Test("UUID parameters accept encoded string values")
    func uuidParameterFromEncodedString() throws {
        let uuid = UUID()
        let params: JSONDictionary = ["uuid": .string(MCPToolArgumentEncoder.encode(uuid))]
        let extracted: UUID = try params.extractParameter(named: "uuid")
        #expect(extracted == uuid)
    }

    @Test("UUID parameters accept native UUID values")
    func uuidParameterFromNativeValue() throws {
        let uuid = UUID()
        let params: JSONDictionary = ["uuid": try JSONValue(encoding: uuid)]
        let extracted: UUID = try params.extractParameter(named: "uuid")
        #expect(extracted == uuid)
    }

    @Test("Data parameters accept base64-encoded string values")
    func dataParameterFromEncodedString() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let params: JSONDictionary = ["data": .string(MCPToolArgumentEncoder.encode(data))]
        let extracted: Data = try params.extractParameter(named: "data")
        #expect(extracted == data)
    }

    @Test("Data parameters accept JSONValue-encoded Data values")
    func dataParameterFromJSONValueEncoding() throws {
        let data = Data([0x0A, 0x0B, 0x0C])
        let params: JSONDictionary = ["data": try MCPClientArgumentEncoder.encode(data)]
        let extracted: Data = try params.extractParameter(named: "data")
        #expect(extracted == data)
    }

    @Test("Client result decoder handles UUID strings")
    func decodeUUIDFromText() throws {
        let uuid = UUID()
        let decoded = try MCPClientResultDecoder.decode(UUID.self, from: uuid.uuidString)
        #expect(decoded == uuid)
    }

    @Test("Client result decoder handles base64 data strings")
    func decodeDataFromText() throws {
        let data = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let decoded = try MCPClientResultDecoder.decode(Data.self, from: data.base64EncodedString())
        #expect(decoded == data)
    }
}
