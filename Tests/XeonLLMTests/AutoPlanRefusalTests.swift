// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs (fork of ToshLLM)
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

private final class RecordingSessionLog: SessionLogWriter {
    private(set) var starts = 0
    private(set) var closes = 0
    private(set) var text = ""
    var fileURL: URL { URL(fileURLWithPath: "/tmp/recording-server.log") }
    var directory: URL { URL(fileURLWithPath: "/tmp") }
    func startSession() { starts += 1 }
    func append(_ text: String) { self.text += text }
    func closeSession() { closes += 1 }
}

final class AutoPlanRefusalTests: XCTestCase {
    private func refusalPlan() throws -> AutoMemoryPlan {
        let json = #"""
        {"plan_schema_version": 1,
         "product": {"mode": "PLAN_UNSUPPORTED", "mode_label_key": "plan.mode.unsupported",
           "reason": "HOST_MEMORY_PRESSURE_HIGH", "warnings": [], "limits": ["HOST_RAM"],
           "limiting_resource": "HOST_RAM",
           "memory": {"physical_bytes": 68719476736, "reclaimable_bytes": 11272192000,
             "projected_rss_bytes": 25933225984, "projected_vram_bytes": 1000000000},
           "dmoe": {"expert_bank_bytes": 26424115200, "hot_bytes": 4475125056, "warm_bytes": 0,
             "coverage": 0, "coverage_state": "NONE"},
           "runtime": {"context": 32768, "kv_type": "f16", "kv_bytes": 400000000,
             "ubatch": 512, "ncmoe_layers": 0},
           "unsupported": {"required_host_bytes": 25933225984, "available_host_bytes": 910420378,
             "required_vram_bytes": 5000000000, "available_vram_bytes": 12000000000}},
         "host": {"pressure": "ELEVATED", "swap_growing": true, "full_host": "HOST_MEMORY_PRESSURE_HIGH",
           "dynamic_cap_mib": 868, "effective_mib": 868, "static_reserve_mib": 13107},
         "state": "UNSUPPORTED", "mode": "none", "reason": "no configuration fits the requested context with the minimum reserve",
         "fallback": "", "kv": "f16", "n_ctx": 32768, "ubatch": 512, "ncmoe": 0,
         "reserve_mib": 768, "arena_mib": 0, "min_arena_mib": 0, "projected_free_mib": 0,
         "host_required_mib": 24739, "vram_total_mib": 5805, "bank_mib": 25200, "mlock": "required",
         "dispersion": "normal", "candidates": []}
        """#
        return try XCTUnwrap(AutoMemoryPlan.decode(Data(json.utf8)))
    }

    private func settings() -> ServerSettings {
        ServerSettings(serverBinary: "/usr/bin/true", modelPath: "/models/ornith-1.0-35b-Q6_K.gguf",
                       port: 18099, ngl: 99, ncmoe: 0, ctx: 32768, threads: 6, flashAttn: "auto",
                       noMmap: true, jinja: true, vramReserveMB: 1024, gpuIndex: -1, extraArgs: "",
                       cacheTypeK: "f16", cacheTypeV: "f16", mlock: false)
    }

    func testRefusalTextNamesModelVerdictBudgetAndPressure() throws {
        let text = AutoMemoryText.refusalLog(model: settings().modelPath, plan: try refusalPlan())
        XCTAssertTrue(text.contains("ornith-1.0-35b-Q6_K.gguf"), text)
        XCTAssertTrue(text.contains("server refused: no engine started"), text)
        XCTAssertTrue(text.contains("UNSUPPORTED"), text)
        XCTAssertTrue(text.contains("no configuration fits the requested context with the minimum reserve"), text)
        XCTAssertTrue(text.contains("required 25933225984 B"), text)
        XCTAssertTrue(text.contains("available 910420378 B"), text)
        for field in ["pressure ELEVATED", "swap_growing true", "full_host HOST_MEMORY_PRESSURE_HIGH",
                      "dynamic_cap_mib 868", "effective_mib 868", "static_reserve_mib 13107"] {
            XCTAssertTrue(text.contains(field), "\(field) missing from \(text)")
        }
    }

    @MainActor func testRefusalPathOpensWritesAndClosesSessionLog() throws {
        let writer = RecordingSessionLog()
        let server = ServerController(fileLog: writer)
        server.state = .starting

        server.failAutoPlan(try refusalPlan(), settings: settings())

        XCTAssertEqual(writer.starts, 1)
        XCTAssertEqual(writer.closes, 1)
        XCTAssertTrue(writer.text.contains("server refused: no engine started"), writer.text)
        XCTAssertTrue(server.log.contains("ornith-1.0-35b-Q6_K.gguf"), server.log)
        if case .failed = server.state {} else { XCTFail("expected failed state, got \(server.state)") }
    }
}
