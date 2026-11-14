// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// A model whose architecture the engine cannot tensor-split falls back to a layer split instead
/// of failing to load ("LLAMA_SPLIT_MODE_TENSOR not implemented for architecture 'lfm3'").
final class TensorSplitArchitectureTests: XCTestCase {
    private func writeGGUF(architecture: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xeon-arch-\(UUID().uuidString).gguf")
        var data = Data("GGUF".utf8)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func string(_ s: String) { u64(UInt64(s.utf8.count)); data.append(contentsOf: s.utf8) }
        u32(3); u64(0); u64(1)
        string("general.architecture"); u32(8); string(architecture)
        try data.write(to: url)
        return url
    }

    private func settings(model: String) -> ServerSettings {
        var s = ServerSettings(serverBinary: "/usr/bin/true", modelPath: model, port: 8080,
                               ngl: 99, ncmoe: 0, ctx: 8192, threads: 6, flashAttn: "auto",
                               noMmap: true, jinja: true,
                               vramReserveMB: 1024, gpuIndex: -1, extraArgs: "",
                               cacheTypeK: "f16", cacheTypeV: "f16", mlock: false)
        s.splitMode = "tensor"
        s.gpuList = [0, 1]
        return s
    }

    func testLFM3FallsBackToALayerSplit() throws {
        let model = try writeGGUF(architecture: "lfm3")
        defer { try? FileManager.default.removeItem(at: model) }
        XCTAssertEqual(ServerSettings.tensorSplitLimit(forModel: model.path), 1)
        let s = settings(model: model.path)
        XCTAssertEqual(s.effectiveSplitMode, "layer")
        XCTAssertTrue(s.tensorSplitDowngraded)
    }

    func testASupportedArchitectureKeepsTheTensorSplit() throws {
        let model = try writeGGUF(architecture: "qwen3")
        defer { try? FileManager.default.removeItem(at: model) }
        XCTAssertNil(ServerSettings.tensorSplitLimit(forModel: model.path))
        XCTAssertEqual(settings(model: model.path).effectiveSplitMode, "tensor")
    }
}
