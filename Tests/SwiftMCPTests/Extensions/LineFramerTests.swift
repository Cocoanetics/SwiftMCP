//
//  LineFramerTests.swift
//  SwiftMCP
//
//  The synchronous line assembler the TCP server transport runs on the
//  connection's serial queue (#171 §4c). Ordering is what it exists for: a
//  JSON-RPC line routinely spans receive callbacks, and assembling across
//  racing tasks reordered bytes and dropped the final unterminated line.
//

import Testing
import Foundation
@testable import SwiftMCP

@Suite("LineFramer")
struct LineFramerTests {

    @Test("A line split across appends is reassembled in order")
    func splitLine() {
        let framer = LineFramer()
        framer.append(Data("{\"a\":".utf8))
        #expect(framer.extractLines().isEmpty)
        framer.append(Data("1}\n".utf8))
        #expect(framer.extractLines() == ["{\"a\":1}"])
    }

    @Test("Multiple lines in one chunk come out separately")
    func multipleLines() {
        let framer = LineFramer()
        framer.append(Data("one\ntwo\nthr".utf8))
        #expect(framer.extractLines() == ["one", "two"])
        framer.append(Data("ee\n".utf8))
        #expect(framer.extractLines() == ["three"])
    }

    @Test("The final unterminated line is returned by remainder()")
    func remainder() {
        let framer = LineFramer()
        framer.append(Data("last line without newline".utf8))
        #expect(framer.extractLines().isEmpty)
        #expect(framer.remainder() == "last line without newline")
        #expect(framer.remainder() == nil)
    }

    @Test("An empty framer has no lines and no remainder")
    func empty() {
        let framer = LineFramer()
        #expect(framer.extractLines().isEmpty)
        #expect(framer.remainder() == nil)
    }

    @Test("Behavior matches the LineBuffer actor for the same byte stream")
    func matchesLineBuffer() async {
        let chunks = ["{\"jsonrpc\"", ":\"2.0\"}\n{\"id\":1", "}\ntail"]

        let framer = LineFramer()
        var framedLines: [String] = []
        for chunk in chunks {
            framer.append(Data(chunk.utf8))
            framedLines.append(contentsOf: framer.extractLines())
        }
        let framedRemainder = framer.remainder()

        let buffer = LineBuffer()
        var bufferedLines: [String] = []
        for chunk in chunks {
            await buffer.append(Data(chunk.utf8))
            bufferedLines.append(contentsOf: await buffer.processLines())
        }
        let bufferedRemainder = await buffer.getRemaining()

        #expect(framedLines == bufferedLines)
        #expect(framedRemainder == bufferedRemainder)
    }
}
