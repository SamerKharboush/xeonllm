// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

final class ExpertTierDevicesTests: XCTestCase {
    private let cards = [
        GPUDevice(index: 0, name: "AMD Radeon HD - FirePro D700", vramMB: 6_144),
        GPUDevice(index: 1, name: "AMD Radeon HD - FirePro D700", vramMB: 6_144),
    ]

    override func setUp() {
        super.setUp()
        ServerController.setGPUsForTesting(cards)
        CardHealth.setExcludedForTesting([])
    }

    override func tearDown() {
        CardHealth.setExcludedForTesting(nil)
        ServerController.setGPUsForTesting(nil)
        super.tearDown()
    }

    private func settings(gpuIndex: Int = -1) -> ServerSettings {
        var s = ServerSettings(serverBinary: "/usr/bin/true", modelPath: "/tmp/moe-not-a-model.gguf", port: 8080,
                               ngl: 99, ncmoe: 0, ctx: 16384, threads: 6, flashAttn: "auto",
                               noMmap: true, jinja: true,
                               vramReserveMB: 1024, gpuIndex: gpuIndex, extraArgs: "",
                               cacheTypeK: "f16", cacheTypeV: "f16", mlock: false)
        s.placement = .expertTier
        return s
    }

    /// The two-card expert-tier launch was withdrawn: 0097 keeps the wide graph on one card
    /// (75.9/13.3 t/s vs 64.0/11.4 on two), so the app must not force a card list.
    func testUnpinnedExpertTierDoesNotNameBothCards() {
        let env = settings().environment
        XCTAssertNil(env["GGML_METAL_DEVICE_LIST"])
        XCTAssertNil(env["GGML_METAL_DEVICES"])
    }

    func testPinnedCardKeepsItsSingleSelection() {
        let env = settings(gpuIndex: 1).environment
        XCTAssertEqual(env["GGML_METAL_DEVICE_INDEX"], "1")
        XCTAssertNil(env["GGML_METAL_DEVICE_LIST"])
    }

    func testExcludedCardLeavesTheHealthyOne() {
        CardHealth.setExcludedForTesting([0])
        let env = settings().environment
        XCTAssertEqual(env["GGML_METAL_DEVICE_INDEX"], "1")
        XCTAssertNil(env["GGML_METAL_DEVICE_LIST"])
    }
}