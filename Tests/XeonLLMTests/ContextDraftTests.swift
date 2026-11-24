// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// Draft-model-free n-gram speculation is opt-in per model. These tests build the launch
/// arguments (and the router INI) and check the `--spec-type ngram-simple` branch: absent
/// unless the model opted in, capped at size-m 7 only when experts run on the host, and
/// never reached when DFlash or MTP already claimed `--spec-type`. The opt-in is read
/// through `contextDraftEnabledOverride`, so no test writes UserDefaults.
final class ContextDraftTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xeon-ctxdraft-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        ServerSettings.contextDraftEnabledOverride = nil
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func settings(modelPath: String) -> ServerSettings {
        ServerSettings(serverBinary: "/usr/bin/true", modelPath: modelPath, port: 8080,
                       ngl: 99, ncmoe: 0, ctx: 8192, threads: 6, flashAttn: "auto",
                       noMmap: true, jinja: true, vramReserveMB: 1024, gpuIndex: -1,
                       extraArgs: "", cacheTypeK: "f16", cacheTypeV: "f16", mlock: false)
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// A model file with no MTP head or DFlash draft beside it, so the n-gram branch is
    /// the one that fires. The bytes are not a real GGUF; the launch reads only names.
    private func plainModel() throws -> String {
        let url = dir.appendingPathComponent("Qwen3-4B.gguf")
        try Data("not a gguf".utf8).write(to: url)
        return url.path
    }

    func testOptedOutModelPassesNoNgramArgs() throws {
        ServerSettings.contextDraftEnabledOverride = { _ in false }
        var s = settings(modelPath: try plainModel())
        s.placement = .card
        XCTAssertFalse(s.arguments.contains("ngram-simple"))
        XCTAssertFalse(s.arguments.contains("--spec-ngram-simple-size-m"))
    }

    func testOptedInDenseFullGPUModelPassesNgramWithoutSizeCap() throws {
        ServerSettings.contextDraftEnabledOverride = { _ in true }
        var s = settings(modelPath: try plainModel())
        s.placement = .card   // dense, no auto plan
        XCTAssertEqual(value(after: "--spec-type", in: s.arguments), "ngram-simple")
        XCTAssertFalse(s.arguments.contains("--spec-ngram-simple-size-m"),
                       "a full-GPU dense model keeps the engine's draft width")
    }

    func testOptedInNonFullGPUAutoPlanCapsDraftAt7() throws {
        ServerSettings.contextDraftEnabledOverride = { _ in true }
        var s = settings(modelPath: try plainModel())
        s.placement = .expertTier   // auto plan that keeps experts on the host
        XCTAssertTrue(s.usesAutoPlan)
        XCTAssertEqual(value(after: "--spec-type", in: s.arguments), "ngram-simple")
        XCTAssertEqual(value(after: "--spec-ngram-simple-size-m", in: s.arguments), "7")
    }

    func testFullGPUPlanLeavesDraftWidthUncapped() throws {
        ServerSettings.contextDraftEnabledOverride = { _ in true }
        var s = settings(modelPath: try plainModel())
        s.placement = .expertTier
        s.plannedMode = "full_gpu"
        XCTAssertEqual(value(after: "--spec-type", in: s.arguments), "ngram-simple")
        XCTAssertFalse(s.arguments.contains("--spec-ngram-simple-size-m"),
                       "a full_gpu plan is not the host decode path")
    }

    func testMTPChosenSkipsNgramArgs() throws {
        ServerSettings.contextDraftEnabledOverride = { _ in true }
        let model = try plainModel()
        // A sibling head whose name ties it to the model; an unreadable header is accepted.
        try Data("not a gguf".utf8).write(to: dir.appendingPathComponent("Qwen3-4B.mtp.gguf"))
        var s = settings(modelPath: model)
        s.placement = .card
        XCTAssertEqual(value(after: "--spec-type", in: s.arguments), "draft-mtp")
        XCTAssertFalse(s.arguments.contains("ngram-simple"),
                       "MTP owns --spec-type, so the n-gram branch is not reached")
    }

    func testRouterINIEmitsNgramAndCapsWithExpertOffload() throws {
        ServerSettings.contextDraftEnabledOverride = { _ in true }
        let model = try plainModel()

        var dense = settings(modelPath: model)
        dense.routerMode = true
        let denseINI = dense.routerPresetINI(modelPaths: [model], ncmoeByPath: [model: 0])
        XCTAssertTrue(denseINI.contains("spec-type = ngram-simple"))
        XCTAssertFalse(denseINI.contains("spec-ngram-simple-size-m"))

        var offloaded = settings(modelPath: model)
        offloaded.routerMode = true
        let offINI = offloaded.routerPresetINI(modelPaths: [model], ncmoeByPath: [model: 4])
        XCTAssertTrue(offINI.contains("spec-type = ngram-simple"))
        XCTAssertTrue(offINI.contains("spec-ngram-simple-size-m = 7"),
                      "n-cpu-moe > 0 is the INI's not-full-GPU signal")
    }
}