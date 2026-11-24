// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// Ticket 08: the benchmark screen must show the workload (pp/tg/depth, real vs
/// llama-bench) and engine identity (sha16, ub, split, device, FA, threads) per
/// result, and warn when two runs are not like for like. These tests cover the
/// model layer: old-format decode, new-format decode, label text, and the
/// not-like-for-like comparison.
final class BenchResultWorkloadTests: XCTestCase {

    // MARK: - Codable backward compatibility

    /// An old-format BenchResult JSON (no engineSha16 / ubatch / batch / splitMode /
    /// device / threads fields) must still decode with the new fields set to nil.
    func testOldFormatBenchResultDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","date":700000000,"model":"MiniCPM5.gguf","ncmoe":0,"pp":48.67,"tg":359.46,"engine":"bundled","gpu":"AMD Radeon Pro D700"}
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(BenchResult.self, from: data)
        XCTAssertNil(result.engineSha16)
        XCTAssertNil(result.ubatch)
        XCTAssertNil(result.batch)
        XCTAssertNil(result.splitMode)
        XCTAssertNil(result.device)
        XCTAssertNil(result.threads)
        XCTAssertEqual(result.pp, 48.67)
        XCTAssertEqual(result.tg, 359.46)
    }

    /// A new-format BenchResult JSON with the engine-identity fields set decodes them.
    func testNewFormatBenchResultDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","date":700000000,"model":"MiniCPM5.gguf","ncmoe":0,"pp":370.15,"tg":53.62,"engine":"bundled","gpu":"AMD Radeon Pro D700","ppN":512,"tgN":128,"depth":0,"kind":"real","engineSha16":"0123456789abcdef","ubatch":512,"batch":512,"splitMode":"layer","device":"1","threads":6,"appVersion":"0.2"}
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(BenchResult.self, from: data)
        XCTAssertEqual(result.engineSha16, "0123456789abcdef")
        XCTAssertEqual(result.ubatch, 512)
        XCTAssertEqual(result.batch, 512)
        XCTAssertEqual(result.splitMode, "layer")
        XCTAssertEqual(result.device, "1")
        XCTAssertEqual(result.threads, 6)
        XCTAssertEqual(result.ppN, 512)
        XCTAssertEqual(result.tgN, 128)
        XCTAssertEqual(result.kind, "real")
    }

    // MARK: - Workload display line

    func testWorkloadLineAlwaysShowsPPandTG() {
        let result = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 100, tg: 50,
                                 ppN: 512, tgN: 128, depth: 0,
                                 engineSha16: "abcdef0123456789",
                                 appVersion: "0.2")
        let line = result.workloadDisplayLine
        XCTAssertTrue(line.contains("pp512"), "expected pp512 in: \(line)")
        XCTAssertTrue(line.contains("tg128"), "expected tg128 in: \(line)")
        XCTAssertTrue(line.contains("llama-bench"), "expected llama-bench badge in: \(line)")
    }

    func testWorkloadLineShowsDepthWhenNonZero() {
        let result = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 100, tg: 50,
                                 ppN: 256, tgN: 64, depth: 128,
                                 engineSha16: "abcdef0123456789",
                                 appVersion: "0.2")
        XCTAssertTrue(result.workloadDisplayLine.contains("d128"))
    }

    func testWorkloadLineShowsRealBadgeForRealGeneration() {
        let result = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 48, tg: 359,
                                 ppN: nil, tgN: 128, depth: nil, kind: "real",
                                 engineSha16: "abcdef0123456789",
                                 appVersion: "0.2")
        let line = result.workloadDisplayLine
        XCTAssertTrue(line.contains("real"), "expected real badge in: \(line)")
        XCTAssertTrue(line.hasPrefix("fixed prompt/tg128 · real"), "real run line: \(line)")
    }

    func testOldRawResultShowsTheDocumentedDefaultWorkload() {
        // The old on-disk format left ppN/tgN/depth nil and was always pp512/tg128/d0.
        let result = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 359, tg: 48,
                                 appVersion: nil)
        XCTAssertEqual(result.workloadDisplayLine, "pp512/tg128 · d0 · llama-bench")
        XCTAssertEqual(result.engineIdentityLine, "")
    }

    func testOldRawResultIsLikeForLikeWithAnExplicitDefaultRun() {
        let old = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 359, tg: 48, appVersion: nil)
        let new = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 360, tg: 49,
                              ppN: 512, tgN: 128, depth: 0, engineSha16: "abcdef0123456789",
                              ubatch: 128, appVersion: "0.2")
        XCTAssertNil(old.notLikeForLikeReason(vs: new))
    }

    func testNonDefaultWorkloadShowsInLabel() {
        // ppN/tgN different from default 512/128 must still appear.
        let result = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 100, tg: 50,
                                 ppN: 256, tgN: 64, depth: 0,
                                 engineSha16: "abcdef0123456789",
                                 appVersion: "0.2")
        let line = result.workloadDisplayLine
        XCTAssertTrue(line.contains("pp256"), "expected pp256 in: \(line)")
        XCTAssertTrue(line.contains("tg64"), "expected tg64 in: \(line)")
    }

    // MARK: - Engine identity line

    func testEngineIdentityLineShowsVersionShaAndUbatch() {
        let result = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 100, tg: 50,
                                 ppN: 512, tgN: 128, depth: 0,
                                 engineSha16: "0123456789abcdef", ubatch: 512,
                                 appVersion: "0.2")
        let line = result.engineIdentityLine
        XCTAssertTrue(line.contains("v0.2"), "expected v0.2 in: \(line)")
        XCTAssertTrue(line.contains("sha:0123456789abcdef"), "expected sha: in: \(line)")
        XCTAssertTrue(line.contains("ub:512"), "expected ub:512 in: \(line)")
    }

    func testOldResultHasEmptyIdentityLine() {
        // Pre-0.2: decoded from old JSON, appVersion is nil so identity line is empty.
        let result = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 48, tg: 359,
                                 appVersion: nil)
        XCTAssertTrue(result.engineIdentityLine.isEmpty,
                      "old result should have empty identity line, got: \(result.engineIdentityLine)")
    }

    // MARK: - Not like for like

    func testMatchingResultsAreLikeForLike() {
        let a = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 100, tg: 50,
                            ppN: 512, tgN: 128, depth: 0, kind: nil,
                            engineSha16: "abcdef0123456789", ubatch: 512, batch: 512,
                            splitMode: "layer", device: "1", threads: 6,
                            appVersion: "0.2")
        let b = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 90, tg: 45,
                            ppN: 512, tgN: 128, depth: 0, kind: nil,
                            engineSha16: "abcdef0123456789", ubatch: 512, batch: 512,
                            splitMode: "layer", device: "1", threads: 6,
                            appVersion: "0.2")
        XCTAssertNil(a.notLikeForLikeReason(vs: b))
    }

    func testDifferentUbatchIsNotLikeForLike() {
        let a = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 100, tg: 50,
                            ppN: 512, tgN: 128, depth: 0, kind: nil,
                            engineSha16: "abcdef0123456789", ubatch: 512, batch: 512,
                            appVersion: "0.2")
        let b = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 90, tg: 45,
                            ppN: 512, tgN: 128, depth: 0, kind: nil,
                            engineSha16: "abcdef0123456789", ubatch: 128, batch: 128,
                            appVersion: "0.2")
        let reason = a.notLikeForLikeReason(vs: b)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("ub 512 vs 128"), "expected ub mismatch, got: \(reason!)")
    }

    func testDifferentWorkloadIsNotLikeForLike() {
        let a = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 100, tg: 50,
                            ppN: 512, tgN: 128, depth: 0, kind: nil,
                            engineSha16: "abcdef0123456789", ubatch: 512, batch: 512,
                            appVersion: "0.2")
        let b = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 90, tg: 45,
                            ppN: 256, tgN: 64, depth: 0, kind: nil,
                            engineSha16: "abcdef0123456789", ubatch: 512, batch: 512,
                            appVersion: "0.2")
        let reason = a.notLikeForLikeReason(vs: b)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("workload"), "expected workload mismatch, got: \(reason!)")
        XCTAssertTrue(reason!.contains("512"), "expected 512 in reason, got: \(reason!)")
        XCTAssertTrue(reason!.contains("256"), "expected 256 in reason, got: \(reason!)")
    }

    func testDifferentEngineShaIsNotLikeForLike() {
        let a = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 100, tg: 50,
                            ppN: 512, tgN: 128, depth: 0, kind: nil,
                            engineSha16: "abcdef0123456789", ubatch: 512, batch: 512,
                            appVersion: "0.2")
        let b = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 90, tg: 45,
                            ppN: 512, tgN: 128, depth: 0, kind: nil,
                            engineSha16: "fedcba9876543210", ubatch: 512, batch: 512,
                            appVersion: "0.2")
        let reason = a.notLikeForLikeReason(vs: b)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("engine sha"), "expected engine sha mismatch, got: \(reason!)")
    }

    func testRealVsLlamaBenchIsNotLikeForLike() {
        let a = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 100, tg: 50,
                            ppN: 512, tgN: 128, depth: 0, kind: nil,
                            engineSha16: "abcdef0123456789", ubatch: 512, batch: 512,
                            appVersion: "0.2")
        let b = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 48, tg: 359,
                            ppN: nil, tgN: 128, depth: nil, kind: "real",
                            engineSha16: "abcdef0123456789", ubatch: 512, batch: 512,
                            appVersion: "0.2")
        let reason = a.notLikeForLikeReason(vs: b)
        XCTAssertNotNil(reason)
        XCTAssertEqual(reason, "kind llama-bench vs real")
    }

    // MARK: - Engine sha16 helper

    func testEngineSha16OfTempFile() throws {
        // Write a known small file and check the helper returns a 16-hex prefix.
        let content = Data("hello benchmark engine".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bench-engine-\(UUID().uuidString).bin")
        try content.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let sha16 = BenchEngineIdentity.sha16(of: url)
        XCTAssertNotNil(sha16)
        XCTAssertEqual(sha16!.count, 16, "sha16 must be 16 hex chars, got: \(sha16!)")
        XCTAssertTrue(sha16!.allSatisfy { $0.isHexDigit }, "sha16 must be hex, got: \(sha16!)")
    }

    func testEngineSha16OfMissingFileIsNil() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-engine-\(UUID().uuidString).bin")
        XCTAssertNil(BenchEngineIdentity.sha16(of: url))
    }

    // MARK: - BenchResult memberwise init with new fields

    func testNewFieldsHaveNilDefaultInMemberwiseInit() throws {
        // Constructing without the new fields must leave them nil (Codable nil).
        let result = BenchResult(date: .now, model: "m.gguf", ncmoe: 0, pp: 100, tg: 50)
        XCTAssertNil(result.engineSha16)
        XCTAssertNil(result.ubatch)
        XCTAssertNil(result.batch)
        XCTAssertNil(result.splitMode)
        XCTAssertNil(result.device)
        XCTAssertNil(result.threads)
        // appVersion has a default of AppInfo.version.
        XCTAssertNotNil(result.appVersion)
    }
}