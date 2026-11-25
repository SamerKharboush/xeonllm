// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// Repeatable temperature-0 answers under Dynamic MoE are opt-in per model. The launch sets
/// `XEON_DMOE_REPEATABLE=1` only for a model the user turned on AND a launch that runs
/// Dynamic MoE (auto plan, not full_gpu); router mode never sets it, and a user value in the
/// model's extra arguments wins. The opt-in is read through `repeatableAnswersEnabledOverride`,
/// so no test writes UserDefaults.
final class RepeatableAnswersTests: XCTestCase {

    override func tearDown() {
        ServerSettings.repeatableAnswersEnabledOverride = nil
        super.tearDown()
    }

    private func env(enabled: Bool, usesAutoPlan: Bool, plannedMode: String?,
                     routerMode: Bool = false, userEnv: [String: String] = [:]) -> String? {
        ServerSettings.repeatableAnswersEnabledOverride = { _ in enabled }
        return ServerSettings.repeatableAnswersEnv(forModel: "/models/ornith-1.0-35b-Q6_K.gguf",
                                                   usesAutoPlan: usesAutoPlan, plannedMode: plannedMode,
                                                   routerMode: routerMode, userEnv: userEnv)
    }

    func testOffByDefaultLeavesEnvUnset() {
        XCTAssertNil(env(enabled: false, usesAutoPlan: true, plannedMode: "host_dmoe"))
    }

    func testOnWithDynamicMoESetsOne() {
        XCTAssertEqual(env(enabled: true, usesAutoPlan: true, plannedMode: "host_dmoe"), "1")
    }

    func testWarmupWantedOnlyWhenEnvIsOne() {
        func wanted(enabled: Bool, usesAutoPlan: Bool, plannedMode: String?,
                    routerMode: Bool = false, userEnv: [String: String] = [:]) -> Bool {
            ServerSettings.repeatableAnswersEnabledOverride = { _ in enabled }
            return ServerSettings.repeatableWarmupWanted(
                forModel: "/models/ornith-1.0-35b-Q6_K.gguf", usesAutoPlan: usesAutoPlan,
                plannedMode: plannedMode, routerMode: routerMode, userEnv: userEnv)
        }
        XCTAssertTrue(wanted(enabled: true, usesAutoPlan: true, plannedMode: "host_dmoe"),
                      "on + Dynamic MoE launch -> warm-up")
        XCTAssertFalse(wanted(enabled: false, usesAutoPlan: true, plannedMode: "host_dmoe"))
        XCTAssertFalse(wanted(enabled: true, usesAutoPlan: true, plannedMode: "host_dmoe", routerMode: true))
        XCTAssertFalse(wanted(enabled: true, usesAutoPlan: false, plannedMode: nil))
        XCTAssertFalse(wanted(enabled: true, usesAutoPlan: true, plannedMode: "full_gpu"))
        XCTAssertFalse(wanted(enabled: true, usesAutoPlan: true, plannedMode: "host_dmoe",
                              userEnv: ["XEON_DMOE_REPEATABLE": "0"]),
                       "a user value other than 1 means no throwaway")
    }

    func testWarmupBodyIsExact() {
        XCTAssertEqual(ServerSettings.repeatableWarmupBody,
                       #"{"prompt":"Hello","n_predict":32,"temperature":0,"top_k":1,"seed":1,"cache_prompt":false}"#)
    }

    func testOnWithFullGPUPlanLeavesEnvUnset() {
        XCTAssertNil(env(enabled: true, usesAutoPlan: true, plannedMode: "full_gpu"),
                     "a full_gpu plan keeps every expert on the card, so there is no arena to pin")
    }

    func testOnWithoutAutoPlanLeavesEnvUnset() {
        XCTAssertNil(env(enabled: true, usesAutoPlan: false, plannedMode: nil),
                     "a dense or hand-placed model does not run Dynamic MoE")
    }

    func testOnInRouterModeLeavesEnvUnset() {
        XCTAssertNil(env(enabled: true, usesAutoPlan: true, plannedMode: "host_dmoe", routerMode: true),
                     "router mode serves several models in one process; the variable is per process")
    }

    func testUserExtraArgOverrideWins() {
        // The user can force it on even without the setting, or off even with it: their
        // extra-argument value is merged after the app's, so it wins.
        XCTAssertEqual(env(enabled: true, usesAutoPlan: true, plannedMode: "host_dmoe",
                           userEnv: ["XEON_DMOE_REPEATABLE": "0"]), "0")
        XCTAssertEqual(env(enabled: false, usesAutoPlan: true, plannedMode: "host_dmoe",
                           userEnv: ["XEON_DMOE_REPEATABLE": "1"]), "1")
    }

    /// A user `KEY=VALUE` token in the model's extra arguments parses into the env the launch
    /// merges, which is what makes the override above reachable.
    func testExtraArgTokenParsesIntoEnv() {
        var s = ServerSettings(serverBinary: "/usr/bin/true", modelPath: "/models/ornith-1.0-35b-Q6_K.gguf",
                               port: 8080, ngl: 99, ncmoe: 0, ctx: 8192, threads: 6, flashAttn: "auto",
                               noMmap: true, jinja: true, vramReserveMB: 1024, gpuIndex: -1,
                               extraArgs: "XEON_DMOE_REPEATABLE=0", cacheTypeK: "f16", cacheTypeV: "f16",
                               mlock: false)
        s.placement = .expertTier
        XCTAssertEqual(s.extraArgTokens.env["XEON_DMOE_REPEATABLE"], "0")
    }
}