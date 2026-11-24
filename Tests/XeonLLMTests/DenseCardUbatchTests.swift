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

    /// The band holds at a shallow context; past 4096 the 0090 KQ bound decides (heads 16
    /// keeps 128 through 65536), so the beta 8 value is not a floor.
    func testDenseCardUbatchShrinksWithContext() throws {
        let model = try denseModel(fileType: 18, bytes: Int64(1.07 * 1_073_741_824), headCount: 16)
        defer { try? FileManager.default.removeItem(at: model) }
        for (ctx, want) in [(4096, 512), (8192, 128), (16384, 128), (32768, 128), (65536, 128)] {
            XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: model.path, ctx: ctx), want, "ctx \(ctx)")
        }
    }

    func testDenseCardUbatch256BandOnlyAt4K() throws {
        let model = try denseModel(fileType: 18, bytes: Int64(3.07 * 1_073_741_824), headCount: 16)
        defer { try? FileManager.default.removeItem(at: model) }
        for (ctx, want) in [(4096, 256), (8192, 128), (16384, 128), (32768, 128)] {
            XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: model.path, ctx: ctx), want, "ctx \(ctx)")
        }
    }

    /// An unreadable model assumes 64 heads: 128 KQ still fits at 16384, halves at 32768.
    func testDenseCardUbatchUnknownModelStaysAt128() {
        for (ctx, want) in [(4096, 128), (8192, 128), (16384, 128), (32768, 64)] {
            XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: "/tmp/no-such-model.gguf", ctx: ctx), want, "ctx \(ctx)")
        }
    }

    /// The engine's 0090 KQ cap (512 MiB) is reached at ub128 x 65536 x 16 heads; 128 still
    /// fits at that exact depth, but one extra padded block pushes it down to 64.
    func testDeepContextBoundAt16Heads() throws {
        let model = try denseModel(fileType: 7, bytes: Int64(1.07 * 1_073_741_824), headCount: 16)
        defer { try? FileManager.default.removeItem(at: model) }
        for (ctx, want) in [(32768, 128), (65536, 128), (65792, 64)] {
            XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: model.path, ctx: ctx), want, "ctx \(ctx)")
        }
    }

    /// At 32 heads the KQ cap is reached at half the depth; at 1M it floors at 16.
    func testDeepContextBoundAt32Heads() throws {
        let model = try denseModel(fileType: 7, bytes: Int64(1.07 * 1_073_741_824), headCount: 32)
        defer { try? FileManager.default.removeItem(at: model) }
        for (ctx, want) in [(16384, 128), (32768, 128), (131072, 32), (1048576, 16)] {
            XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: model.path, ctx: ctx), want, "ctx \(ctx)")
        }
    }

    /// A per-layer head_count array uses the widest layer, not the first one.
    func testDeepContextBoundUsesMaxOfPerLayerHeadCounts() throws {
        let model = try denseModel(fileType: 7, bytes: Int64(1.07 * 1_073_741_824),
                                   headCounts: [16, 40, 32])
        defer { try? FileManager.default.removeItem(at: model) }
        // 128 x 65536 x 40 x 4 = 1.25 GiB; 64 x 65536 x 40 x 4 = 625 MiB; 32 fits.
        XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: model.path, ctx: 65536), 32)
    }

    func testDeepContextBoundFloorsAt16For40HeadsAt1M() throws {
        let model = try denseModel(fileType: 7, bytes: Int64(1.07 * 1_073_741_824), headCount: 40)
        defer { try? FileManager.default.removeItem(at: model) }
        XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: model.path, ctx: 1048576), 16)
    }

    /// No head_count in the header: assume 64 heads, so 128 KQ bytes exceed 512 MiB at 32k.
    func testDeepContextBoundAssumes64HeadsWhenUnknown() throws {
        let model = try denseModel(fileType: 7, bytes: Int64(1.07 * 1_073_741_824))
        defer { try? FileManager.default.removeItem(at: model) }
        XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: model.path, ctx: 32768), 64)
    }

    /// Shallow size/quant bands are untouched; a model whose band is below the deep bound
    /// keeps its smaller value at a deeper context.
    func testDeepContextBoundKeepsShallowBandsAndSmallerModels() throws {
        let small = try denseModel(fileType: 7, bytes: Int64(1.07 * 1_073_741_824), headCount: 16)
        defer { try? FileManager.default.removeItem(at: small) }
        XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: small.path, ctx: 4096), 512)
        let mid = try denseModel(fileType: 18, bytes: Int64(3.07 * 1_073_741_824), headCount: 16)
        defer { try? FileManager.default.removeItem(at: mid) }
        XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: mid.path, ctx: 4096), 256)
        XCTAssertEqual(ServerSettings.denseCardUbatchForModel(at: mid.path, ctx: 16384), 128)
    }

    func testDeepContextBoundReachesBenchAndServerArguments() throws {
        let model = try denseModel(fileType: 7, bytes: Int64(1.07 * 1_073_741_824), headCount: 32)
        defer { try? FileManager.default.removeItem(at: model) }
        var s = makeSettings()
        s.modelPath = model.path
        s.ctx = 65536
        s.placement = .card
        XCTAssertEqual(s.effectiveUbatch, 64)
        XCTAssertEqual(value(after: "--ubatch-size", in: s.arguments), "64")
        XCTAssertEqual(value(after: "--batch-size", in: s.arguments), "64")
        XCTAssertEqual(value(after: "-ub", in: s.benchmarkArguments), "64")
        XCTAssertEqual(value(after: "-b", in: s.benchmarkArguments), "64")
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
    private func denseModel(fileType: UInt32, bytes: Int64,
                            headCount: UInt32? = nil, headCounts: [UInt32]? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xeon-dense-ub-\(UUID().uuidString).gguf")
        var data = Data("GGUF".utf8)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func string(_ s: String) { u64(UInt64(s.utf8.count)); data.append(contentsOf: s.utf8) }
        var values: [(String, UInt32)] = [
            ("general.file_type", fileType),
            ("llama.block_count", 24),
        ]
        var arrays: [(String, [UInt32])] = []
        if let headCount { values.append(("llama.attention.head_count", headCount)) }
        if let headCounts { arrays.append(("llama.attention.head_count", headCounts)) }
        u32(3); u64(0); u64(UInt64(values.count + arrays.count))
        for (key, value) in values {
            string(key); u32(4); u32(value)
        }
        for (key, value) in arrays {
            string(key); u32(9); u32(4); u64(UInt64(value.count))
            for v in value { u32(v) }
        }
        try data.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(bytes))
        try handle.close()
        return url
    }
}
