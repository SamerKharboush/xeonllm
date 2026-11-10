// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// A host-placed model keeps its weights on the CPU, but its prompt can still be
/// computed on a card. The app names exactly one healthy card for it: the headless
/// one (card 1), the display card (card 0) only when the headless one is excluded.
final class PromptOffloadCardTests: XCTestCase {
    private let displayCard = GPUDevice(index: 0, name: "AMD Radeon Pro 580", vramMB: 8_180)
    private let headlessCard = GPUDevice(index: 1, name: "AMD Radeon Pro Vega II Duo", vramMB: 32_736)

    private var bothCards: [GPUDevice] { [displayCard, headlessCard] }

    private func makeSettings() -> ServerSettings {
        ServerSettings(serverBinary: "/usr/bin/true", modelPath: "/tmp/m.gguf", port: 8080,
                       ngl: 99, ncmoe: 24, ctx: 16384, threads: 6, flashAttn: "auto",
                       noMmap: true, jinja: true,
                       vramReserveMB: 1024, gpuIndex: -1, extraArgs: "",
                       cacheTypeK: "f16", cacheTypeV: "f16", mlock: false)
    }

    override func setUp() {
        super.setUp()
        ServerController.setGPUsForTesting(bothCards)
        CardHealth.setExcludedForTesting([])
    }

    override func tearDown() {
        CardHealth.setExcludedForTesting(nil)
        ServerController.setGPUsForTesting(nil)
        super.tearDown()
    }

    func testTwoHealthyCardsPickTheHeadlessOne() {
        let (card, reason) = ServerSettings.promptOffloadCard(placement: .host, isMoE: false,
                                                              gpus: bothCards, excluded: [])
        XCTAssertEqual(card, 1)
        XCTAssertEqual(reason, "card 1")
    }

    func testExcludedHeadlessCardFallsBackToTheDisplayCard() {
        let (card, reason) = ServerSettings.promptOffloadCard(placement: .host, isMoE: false,
                                                              gpus: bothCards, excluded: [1])
        XCTAssertEqual(card, 0)
        XCTAssertEqual(reason, "card 0")
    }

    func testBothCardsExcludedNameNoCard() {
        let (card, reason) = ServerSettings.promptOffloadCard(placement: .host, isMoE: false,
                                                              gpus: bothCards, excluded: [0, 1])
        XCTAssertNil(card)
        XCTAssertEqual(reason, "no healthy card")
    }

    /// An MoE host placement stays card-free until ticket 12 gates the offload.
    func testMoEHostPlacementNamesNoCard() {
        let (card, reason) = ServerSettings.promptOffloadCard(placement: .host, isMoE: true,
                                                              gpus: bothCards, excluded: [])
        XCTAssertNil(card)
        XCTAssertEqual(reason, "MoE prompt offload not validated (ticket 12)")
    }

    /// A model that runs on a card needs no prompt offload card.
    func testCardPlacementNamesNoCard() {
        let (card, _) = ServerSettings.promptOffloadCard(placement: .card, isMoE: false,
                                                        gpus: bothCards, excluded: [])
        XCTAssertNil(card)
    }

    /// The named card reaches the engine: the host placement leaves the cards out of
    /// the run, but the prompt offload names exactly one of them.
    func testHostPlacementNamesTheCardInTheEnvironment() {
        var s = makeSettings()
        s.placement = .host
        let env = s.environment
        XCTAssertEqual(env["GGML_METAL_DEVICE_INDEX"], "1")
        XCTAssertNil(env["GGML_METAL_DEVICES"])
        XCTAssertNil(env["GGML_METAL_DEVICE_LIST"])
    }

    /// An iGPU never takes the prompt: it is never auto-selected.
    func testIntegratedGPUIsNeverChosen() {
        let integrated = GPUDevice(index: 0, name: "Apple M3 Pro", vramMB: 8_192, isIntegrated: true)
        let (card, _) = ServerSettings.promptOffloadCard(placement: .host, isMoE: false,
                                                        gpus: [integrated, headlessCard], excluded: [])
        XCTAssertEqual(card, 1)

        let (onlyIntegrated, reason) = ServerSettings.promptOffloadCard(placement: .host, isMoE: false,
                                                                         gpus: [integrated], excluded: [])
        XCTAssertNil(onlyIntegrated)
        XCTAssertEqual(reason, "no healthy card")
    }
}
