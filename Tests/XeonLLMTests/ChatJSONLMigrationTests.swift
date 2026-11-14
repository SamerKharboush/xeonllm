// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs (fork of ToshLLM)
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// The conversation header renamed its own fields from `tosh*` to `xeon*`. A file saved by
/// beta 8 keeps every one of them: the new name is read first, the old one is the fallback,
/// and only the new name is written back.
final class ChatJSONLMigrationTests: XCTestCase {
    private let beta8Header = """
    {"type":"session","harness":"llama.app","id":"11111111-1111-1111-1111-111111111111",\
    "name":"Beta 8","lastModified":1700000000000,"currNode":"m1","pinned":true,\
    "toshCreated":1699999000000,"toshSystemPrompt":"Be brief","toshSummary":"A summary",\
    "toshSummarizedCount":3,\
    "toshArchived":[{"id":"11111111-2222-3333-4444-555555555555","from":0,"to":1,"note":"already answered","date":721691800.0}],\
    "toshEnabledToolNames":["read_file"]}
    {"type":"message","message":{"id":"m1","convId":"11111111-1111-1111-1111-111111111111",\
    "type":"text","timestamp":1699999500000,"role":"assistant","content":"Hello",\
    "parent":"root","children":[]}}
    """

    func testABeta8FileKeepsEveryField() throws {
        let decoded = try XCTUnwrap(ChatJSONL.decode(Data(beta8Header.utf8)).first)
        XCTAssertEqual(decoded.title, "Beta 8")
        XCTAssertEqual(decoded.created, Date(timeIntervalSince1970: 1699999000))
        XCTAssertEqual(decoded.updated, Date(timeIntervalSince1970: 1700000000))
        XCTAssertEqual(decoded.systemPrompt, "Be brief")
        XCTAssertEqual(decoded.summary, "A summary")
        XCTAssertEqual(decoded.summarizedCount, 3)
        XCTAssertEqual(decoded.enabledToolNames, ["read_file"])
        XCTAssertEqual(decoded.pinned, true)
        XCTAssertEqual(decoded.archived?.map(\.note), ["already answered"])
        XCTAssertEqual(decoded.messages.map(\.parts.body), ["Hello"])
    }

    func testReEncodingWritesOnlyTheXeonNames() throws {
        let decoded = try XCTUnwrap(ChatJSONL.decode(Data(beta8Header.utf8)).first)
        let text = try XCTUnwrap(String(data: try ChatJSONL.encode([decoded]), encoding: .utf8))
        for key in ["xeonCreated", "xeonSystemPrompt", "xeonSummary", "xeonSummarizedCount",
                    "xeonArchived", "xeonEnabledToolNames"] {
            XCTAssertTrue(text.contains("\"\(key)\""), key)
        }
        XCTAssertFalse(text.contains("tosh"), text)
    }

    func testANewFileRoundTripsAndTheOldNamesStillRead() throws {
        let original = Conversation(title: "Both names",
                                    messages: [ChatMessage(role: "assistant", content: "Hi")],
                                    summary: "s", summarizedCount: 2,
                                    systemPrompt: "p", enabledToolNames: ["read_file"])
        let data = try ChatJSONL.encode([original])
        XCTAssertFalse(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("tosh"))
        let decoded = try XCTUnwrap(ChatJSONL.decode(data).first)
        XCTAssertEqual(decoded.summary, "s")
        XCTAssertEqual(decoded.summarizedCount, 2)
        XCTAssertEqual(decoded.systemPrompt, "p")
        XCTAssertEqual(decoded.enabledToolNames, ["read_file"])
        XCTAssertEqual(decoded.created.timeIntervalSince1970,
                       original.created.timeIntervalSince1970, accuracy: 0.001)
    }
}