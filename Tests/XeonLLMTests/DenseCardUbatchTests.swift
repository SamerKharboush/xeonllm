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

    func testDenseCardLaunchUsesModelSizedUbatch() throws {
        let model = try denseModel(fileType: 18, bytes: Int64(3.07 * 1_073_741_824))
        defer { try? FileManager.default.removeItem(at: model) }

        var s = makeSettings()
        s.modelPath = model.path
        s.ctx = 4096
        s.placement = .card
        XCTAssertEqual(s.effectiveUbatch, 256)
        XCTAssertEqual(value(after: "--ubatch-size", in: s.arguments), "256")
        XCTAssertEqual(value(after: "--batch-size", in: s.arguments), "256")
    }

    func testDenseCardLaunchUses512ForSmallModels() throws {
        for type in [UInt32(7), UInt32(18)] {
            let model = try denseModel(fileType: type, bytes: Int64(1.07 * 1_073_741_824))
            defer { try? FileManager.default.removeItem(at: model) }

            var s = makeSettings()
            s.modelPath = model.path
            s.ctx = 4096
            s.placement = .card
            XCTAssertEqual(s.effectiveUbatch, 512, "file type \(type)")
            XCTAssertEqual(value(after: "--ubatch-size", in: s.arguments), "512")
        }
    }

    func testDenseCardLaunchUses512ForF16Under4GB() throws {
        let model = try denseModel(fileType: 1, bytes: Int64(3.2 * 1_073_741_824))
        defer { try? FileManager.default.removeItem(at: model) }
        var s = makeSettings()
        s.modelPath = model.path
        s.ctx = 4096
        s.placement = .card
        XCTAssertEqual(s.effectiveUbatch, 512)
        XCTAssertEqual(value(after: "--ubatch-size", in: s.arguments), "512")
    }

    func testDenseCardLaunchUses256AtTheUpperLimit() throws {
        for spec in [(UInt32(18), 3.5), (UInt32(7), 3.5)] {
            let model = try denseModel(fileType: spec.0, bytes: Int64(spec.1 * 1_073_741_824))
            defer { try? FileManager.default.removeItem(at: model) }
            var s = makeSettings()
            s.modelPath = model.path
            s.ctx = 4096
            s.placement = .card
            XCTAssertEqual(s.effectiveUbatch, 256, "file type \(spec.0)")
            XCTAssertEqual(value(after: "--ubatch-size", in: s.arguments), "256")
        }
    }

    func testDenseCardLaunchUses128ForLargeOrF16Over4GB() throws {
        for spec in [(UInt32(18), 3.6), (UInt32(7), 3.6), (UInt32(1), 4.1)] {
            let model = try denseModel(fileType: spec.0, bytes: Int64(spec.1 * 1_073_741_824))
            defer { try? FileManager.default.removeItem(at: model) }
            var s = makeSettings()
            s.modelPath = model.path
            s.ctx = 4096
            s.placement = .card
            XCTAssertEqual(s.effectiveUbatch, 128, "file type \(spec.0) at \(spec.1) GiB")
            XCTAssertEqual(value(after: "--ubatch-size", in: s.arguments), "128")
        }
    }

    /// The band holds at a shallow context but halves per doubling past 4096; the 128 floor
    /// is the beta 8 panic-safe value (ticket 18), and the app's 16k default lands there.
    func testDenseCardUbatchShrinksWithContext() throws {
        let model = try denseModel(fileType: 18, bytes: Int64(1.07 * 1_073_741_824))
        defer { try? FileManager.default.removeItem(at: model) }
        for (ctx, want) in [(4096, 512), (8192, 128), (16384, 128), (32768, 128), (65536, 128)] {
            XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: model.path, ctx: ctx), want, "ctx \(ctx)")
        }
    }

    func testDenseCardUbatch256BandOnlyAt4K() throws {
        let model = try denseModel(fileType: 18, bytes: Int64(3.07 * 1_073_741_824))
        defer { try? FileManager.default.removeItem(at: model) }
        for (ctx, want) in [(4096, 256), (8192, 128), (16384, 128), (32768, 128)] {
            XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: model.path, ctx: ctx), want, "ctx \(ctx)")
        }
    }

    func testDenseCardUbatchUnknownModelStaysAt128() {
        for ctx in [4096, 8192, 16384, 32768] {
            XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: "/tmp/no-such-model.gguf", ctx: ctx), 128)
        }
    }

    func testDenseCardLaunchUsesContextScaledUbatch() throws {
        let model = try denseModel(fileType: 18, bytes: Int64(1.07 * 1_073_741_824))
        defer { try? FileManager.default.removeItem(at: model) }
        var s = makeSettings()
        s.modelPath = model.path
        s.ctx = 8192
        s.placement = .card
        XCTAssertEqual(s.effectiveUbatch, 128)
        s.ctx = 4096
        XCTAssertEqual(s.effectiveUbatch, 512)
        XCTAssertEqual(value(after: "--ubatch-size", in: s.arguments), "512")
        XCTAssertEqual(value(after: "--batch-size", in: s.arguments), "512")
    }

    /// A dense GGUF header with the file type the app reads; the size stands in for weights.
    private func denseModel(fileType: UInt32, bytes: Int64) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xeon-dense-ub-\(UUID().uuidString).gguf")
        var data = Data("GGUF".utf8)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func string(_ s: String) { u64(UInt64(s.utf8.count)); data.append(contentsOf: s.utf8) }
        let values: [(String, UInt32)] = [
            ("general.file_type", fileType),
            ("llama.block_count", 24),
        ]
        u32(3); u64(0); u64(UInt64(values.count))
        for (key, value) in values {
            string(key); u32(4); u32(value)
        }
        try data.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(bytes))
        try handle.close()
        return url
    }
}
