// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// A dense model on a card prefills in short batches so no command buffer runs long enough
/// to starve the display (beta 8 ticket 18); host and MoE launches keep their own rules.
final class DenseCardUbatchTests: XCTestCase {
    private func makeSettings() -> ServerSettings {
        ServerSettings(serverBinary: "/usr/bin/true", modelPath: "/tmp/dense-not-a-model.gguf", port: 8080,
                       ngl: 99, ncmoe: 0, ctx: 16384, threads: 6, flashAttn: "auto",
                       noMmap: true, jinja: true,
                       vramReserveMB: 1024, gpuIndex: -1, extraArgs: "",
                       cacheTypeK: "f16", cacheTypeV: "f16", mlock: false)
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    func testDenseCardLaunchUsesTheShortUbatch() {
        var s = makeSettings()
        s.placement = .card
        XCTAssertEqual(s.effectiveUbatch, ServerSettings.denseCardUbatch)
        XCTAssertEqual(value(after: "--ubatch-size", in: s.arguments), "128")
        XCTAssertEqual(value(after: "--batch-size", in: s.arguments), "128")
    }

    func testDenseHostLaunchPassesNoUbatch() {
        var s = makeSettings()
        s.placement = .host
        XCTAssertNil(s.effectiveUbatch)
        XCTAssertFalse(s.arguments.contains("--ubatch-size"))
    }
}
