// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Metal

struct CardCheckResult: Equatable, Sendable {
    let index: Int
    let passed: Bool
    let detail: String
}

/// A small Metal known-answer test per card. A card can start returning wrong
/// results after repeated GPU resets while still answering commands, so the app
/// asks every card to compute something with a known answer before a run.
enum CardHealth {
    /// A card is left out when its check failed or it is injected as faulty,
    /// unless the user forced it on. Never leave every card out: with no card
    /// left the engine runs as before, and the banner still reports the failure.
    static func excludedCards(results: [CardCheckResult],
                              forceInclude: Set<Int>,
                              injectedFaults: Set<Int>) -> Set<Int> {
        let known = Set(results.map(\.index)).union(injectedFaults)
        guard !known.isEmpty else { return [] }
        var excluded = Set<Int>()
        for index in known {
            if forceInclude.contains(index) { continue }
            let failed = injectedFaults.contains(index)
                || results.first { $0.index == index }?.passed == false
            if failed { excluded.insert(index) }
        }
        return excluded.count >= known.count ? [] : excluded
    }

    /// Reads XEONLLM_CARD_FAULT (comma-separated physical indices): the test
    /// override that proves the exclusion path reaches the launch environment.
    static func injectedFaults() -> Set<Int> {
        let raw = ProcessInfo.processInfo.environment["XEONLLM_CARD_FAULT"] ?? ""
        return Set(raw.split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        })
    }

    static var forceInclude: Set<Int> {
        guard let raw = UserDefaults.standard.array(forKey: SettingsKeys.cardHealthForceInclude) else {
            return []
        }
        return Set(raw.compactMap { ($0 as? NSNumber)?.intValue })
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedResults: [CardCheckResult] = []
    nonisolated(unsafe) private static var cachedExcluded: Set<Int> = []
    nonisolated(unsafe) private static var probeStarted = false
    nonisolated(unsafe) private static var excludedOverride: Set<Int>?

    static var lastResults: [CardCheckResult] {
        lock.lock()
        defer { lock.unlock() }
        return cachedResults
    }

    static var excluded: Set<Int> {
        lock.lock()
        defer { lock.unlock() }
        return excludedOverride ?? cachedExcluded
    }

    /// Test hook: force the excluded set without running the probe.
    static func setExcludedForTesting(_ value: Set<Int>?) {
        lock.lock()
        excludedOverride = value
        lock.unlock()
    }

    private static let probeDone = DispatchGroup()

    /// Blocks until the launch probe has finished, at most `timeout` seconds. An engine
    /// started by auto-start must not pick a card before its check has answered.
    @discardableResult
    static func waitForProbe(timeout: TimeInterval = 5) -> Bool {
        probeDone.wait(timeout: .now() + timeout) == .success
    }

    /// Runs the probe once per app launch, off the main thread, for every
    /// discrete card in MTLCopyAllDevices() order (the engine's own order).
    static func startProbe() {
        lock.lock()
        let alreadyStarted = probeStarted
        probeStarted = true
        lock.unlock()
        guard !alreadyStarted else { return }

        probeDone.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { probeDone.leave() }
            let results = MTLCopyAllDevices().enumerated()
                .filter { !$0.element.isLowPower }
                .map { check(device: $0.element, index: $0.offset) }
            let excluded = excludedCards(results: results,
                                         forceInclude: forceInclude,
                                         injectedFaults: injectedFaults())
            lock.lock()
            cachedResults = results
            cachedExcluded = excluded
            lock.unlock()
        }
    }

    /// One command buffer with two dispatches: out = a * b + a over n elements,
    /// then 256-element block sums of out. Buffers are only the n-sized inputs
    /// and outputs (~3 MiB): a seconds-long command buffer reboots this machine.
    static func check(device: MTLDevice, index: Int, timeout: TimeInterval = 2) -> CardCheckResult {
        let n = 262_144
        let blockSize = 256
        let blockCount = n / blockSize
        let bytes = n * MemoryLayout<Float>.stride

        var a = [Float](repeating: 0, count: n)
        var b = [Float](repeating: 0, count: n)
        for i in 0..<n {
            a[i] = Float(i % 97) * 0.25
            b[i] = Float(i % 89) * 0.5 - 7
        }

        // CPU answer, including the per-block sums the second pass must produce.
        var expectedOut = [Float](repeating: 0, count: n)
        var expectedBlocks = [Float](repeating: 0, count: blockCount)
        for i in 0..<n {
            expectedOut[i] = a[i] * b[i] + a[i]
        }
        for block in 0..<blockCount {
            var sum = 0.0
            for i in (block * blockSize)..<((block + 1) * blockSize) {
                sum += Double(expectedOut[i])
            }
            expectedBlocks[block] = Float(sum)
        }

        let source = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void muladd(device const float *a [[buffer(0)]],
                           device const float *b [[buffer(1)]],
                           device float *out [[buffer(2)]],
                           uint gid [[thread_position_in_grid]]) {
            out[gid] = a[gid] * b[gid] + a[gid];
        }

        kernel void blocksum(device const float *values [[buffer(0)]],
                             device float *blocks [[buffer(1)]],
                             uint gid [[thread_position_in_grid]],
                             uint tid [[thread_position_in_threadgroup]],
                             uint gsize [[threads_per_threadgroup]],
                             uint block [[threadgroup_position_in_grid]]) {
            threadgroup float scratch[256];
            scratch[tid] = values[gid];
            threadgroup_barrier(mem_flags::mem_threadgroup);
            for (uint s = gsize / 2; s > 0; s >>= 1) {
                if (tid < s) scratch[tid] += scratch[tid + s];
                threadgroup_barrier(mem_flags::mem_threadgroup);
            }
            if (tid == 0) blocks[block] = scratch[0];
        }
        """

        guard let library = try? device.makeLibrary(source: source, options: nil),
              let mulFunction = library.makeFunction(name: "muladd"),
              let blockFunction = library.makeFunction(name: "blocksum"),
              let mulPipeline = try? device.makeComputePipelineState(function: mulFunction),
              let blockPipeline = try? device.makeComputePipelineState(function: blockFunction)
        else {
            return CardCheckResult(index: index, passed: false, detail: "error: kernel did not compile")
        }

        guard let aBuffer = a.withUnsafeBytes({ raw in
                  device.makeBuffer(bytes: raw.baseAddress!, length: bytes, options: .storageModeShared)
              }),
              let bBuffer = b.withUnsafeBytes({ raw in
                  device.makeBuffer(bytes: raw.baseAddress!, length: bytes, options: .storageModeShared)
              }),
              let outBuffer = device.makeBuffer(length: bytes, options: .storageModeShared),
              let blockBuffer = device.makeBuffer(length: blockCount * MemoryLayout<Float>.stride,
                                                  options: .storageModeShared)
        else {
            return CardCheckResult(index: index, passed: false, detail: "error: buffer allocation failed")
        }

        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer()
        else {
            return CardCheckResult(index: index, passed: false, detail: "error: no command queue")
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return CardCheckResult(index: index, passed: false, detail: "error: no command encoder")
        }
        encoder.setComputePipelineState(mulPipeline)
        encoder.setBuffer(aBuffer, offset: 0, index: 0)
        encoder.setBuffer(bBuffer, offset: 0, index: 1)
        encoder.setBuffer(outBuffer, offset: 0, index: 2)
        let threadsPerGroup = MTLSize(width: blockSize, height: 1, depth: 1)
        let groups = MTLSize(width: n / blockSize, height: 1, depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)

        encoder.setComputePipelineState(blockPipeline)
        encoder.setBuffer(outBuffer, offset: 0, index: 0)
        encoder.setBuffer(blockBuffer, offset: 0, index: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        let semaphore = DispatchSemaphore(value: 0)
        var status: MTLCommandBufferStatus = .notEnqueued
        var commandError: Error?
        commandBuffer.addCompletedHandler { finished in
            status = finished.status
            commandError = finished.error
            semaphore.signal()
        }
        commandBuffer.commit()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            return CardCheckResult(index: index, passed: false, detail: "timeout")
        }
        if let commandError {
            return CardCheckResult(index: index, passed: false,
                                   detail: "error: \(commandError.localizedDescription)")
        }
        guard status == .completed else {
            return CardCheckResult(index: index, passed: false,
                                   detail: "error: command buffer status \(status.rawValue)")
        }

        func differs(_ actual: Float, _ expected: Float) -> Bool {
            !actual.isFinite || abs(actual - expected) > 1e-3 * max(1, abs(expected))
        }
        func format(_ value: Float) -> String { String(format: "%.6g", Double(value)) }

        let actualOut = outBuffer.contents().bindMemory(to: Float.self, capacity: n)
        for i in 0..<n where differs(actualOut[i], expectedOut[i]) {
            return CardCheckResult(index: index, passed: false,
                                   detail: "mismatch at \(i): \(format(actualOut[i])) vs \(format(expectedOut[i]))")
        }

        let actualBlocks = blockBuffer.contents().bindMemory(to: Float.self, capacity: blockCount)
        for block in 0..<blockCount where differs(actualBlocks[block], expectedBlocks[block]) {
            return CardCheckResult(index: index, passed: false,
                                   detail: "block sum mismatch at \(block): \(format(actualBlocks[block])) vs \(format(expectedBlocks[block]))")
        }

        return CardCheckResult(index: index, passed: true, detail: "ok")
    }
}
