//
//  TCPSendStallAPITests.swift
//  SwiftMCP
//
//  `TCPBonjourTransport.sendStallTimeout` is there on every platform — on those
//  without the Network framework too, where the transport is a stub — so code
//  that sets it builds everywhere.
//

#if Server
import Foundation
import Testing
@testable import SwiftMCP

@Suite("TCP send stall API")
struct TCPSendStallAPITests {
    @Test("The stall timeout can be set on every platform")
    func stallTimeoutIsSettable() {
        let transport = TCPBonjourTransport(server: Calculator())
        #expect(transport.sendStallTimeout == nil)
        transport.sendStallTimeout = 1
        #expect(transport.sendStallTimeout == 1)
    }
}
#endif
