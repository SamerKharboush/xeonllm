// Read ceiling of one Metal device: a kernel whose only work is reading a private buffer much
// larger than any cache, for at least `soak` seconds per variant (ticket 19).
//
//   swiftc -O tools/metal-probe/readceiling.swift -o readceiling
//   ./readceiling <device index> [MiB=1024] [soak seconds=1.5] [private|shared]
//
// `shared` reads a .storageModeShared (host RAM) buffer across PCIe (beta8 ticket 07). The host
// fills it, and each command buffer reads one 128 MiB slice, cycling through the buffer, so a
// pass stays short at PCIe rates.
//
// Each command buffer holds ONE pass (tens of ms); the soak is a loop of them, at most 400.
//
// Each variant prints: load width, threadgroups x threads, passes, seconds, GB/s (1e9 bytes).
// A variant that reads less than the others is kernel-limited; when several differently shaped
// variants land on the same rate, that rate is the card's.
import Metal
import Foundation

let args = CommandLine.arguments
guard args.count >= 2, let devIndex = Int(args[1]) else {
    print("usage: readceiling <device index> [MiB] [soak s]"); exit(2)
}
let mib = args.count > 2 ? Int(args[2]) ?? 1024 : 1024
let soak = args.count > 3 ? Double(args[3]) ?? 1.5 : 1.5
let shared = args.count > 4 && args[4] == "shared"
let devices = MTLCopyAllDevices()
guard devIndex < devices.count else { print("no device \(devIndex)"); exit(2) }
let dev = devices[devIndex]
let bytes = mib * 1024 * 1024

let src = """
#include <metal_stdlib>
using namespace metal;
// grid-stride reads; the xor keeps the loads live, one store per thread
kernel void read4(device const uint4 * a [[buffer(0)]], device uint * out [[buffer(1)]],
                  constant uint & n [[buffer(2)]], uint gid [[thread_position_in_grid]],
                  uint gsz [[threads_per_grid]]) {
    uint4 acc = 0;
    for (uint i = gid; i < n; i += gsz) acc ^= a[i];
    out[gid] = acc.x ^ acc.y ^ acc.z ^ acc.w;
}
kernel void read1(device const uint * a [[buffer(0)]], device uint * out [[buffer(1)]],
                  constant uint & n [[buffer(2)]], uint gid [[thread_position_in_grid]],
                  uint gsz [[threads_per_grid]]) {
    uint acc = 0;
    for (uint i = gid; i < n; i += gsz) acc ^= a[i];
    out[gid] = acc;
}
kernel void fill(device uint * a [[buffer(0)]], uint gid [[thread_position_in_grid]]) {
    a[gid] = gid * 2654435761u;
}
"""
let lib = try! dev.makeLibrary(source: src, options: nil)
func pipe(_ name: String) -> MTLComputePipelineState {
    try! dev.makeComputePipelineState(function: lib.makeFunction(name: name)!)
}
let queue = dev.makeCommandQueue()!
let buf = dev.makeBuffer(length: bytes, options: shared ? .storageModeShared : .storageModePrivate)!
let slice = shared ? min(bytes, 128 << 20) : bytes  // bytes read per command buffer
let slices = bytes / slice
let maxThreads = 256 * 1024
let out = dev.makeBuffer(length: maxThreads * 4, options: .storageModePrivate)!

// fill once so the reads are of written pages, not of untouched memory
if shared {
    let w = buf.contents().bindMemory(to: UInt32.self, capacity: bytes / 4)
    for i in 0..<(bytes / 4) { w[i] = UInt32(truncatingIfNeeded: i &* 2654435761) }
} else {
    let cb = queue.makeCommandBuffer()!; let enc = cb.makeComputeCommandEncoder()!
    let p = pipe("fill"); enc.setComputePipelineState(p); enc.setBuffer(buf, offset: 0, index: 0)
    enc.dispatchThreads(MTLSize(width: bytes / 4, height: 1, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
    enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
}

print("device \(devIndex): \(dev.name), buffer \(mib) MiB \(shared ? "shared (host)" : "private (card)"), \(slice >> 20) MiB per command buffer, soak >= \(soak) s")
let variants: [(String, Int, Int)] = [  // kernel, threadgroups, threads per group
    ("read4", 1024, 256), ("read4", 4096, 256), ("read4", 512, 64),
    ("read1", 1024, 256), ("read1", 4096, 256),
]
for (name, groups, tpg) in variants {
    let p = pipe(name)
    var n = UInt32(name == "read4" ? slice / 16 : slice / 4)
    var k = 0
    // One pass per command buffer: a D700 hung by a seconds-long command buffer takes the Mac down
    // with a CPU machine check (2026-11-04 19:00). The soak is a loop of short buffers.
    func pass() -> Double {
        let cb = queue.makeCommandBuffer()!
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p); enc.setBuffer(buf, offset: (k % slices) * slice, index: 0); k += 1
        enc.setBuffer(out, offset: 0, index: 1); enc.setBytes(&n, length: 4, index: 2)
        enc.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: tpg, height: 1, depth: 1))
        enc.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
        if cb.status != .completed { print("command buffer failed: \(String(describing: cb.error))"); exit(1) }
        return cb.gpuEndTime - cb.gpuStartTime
    }
    let first = pass()  // warmup, discarded; also the per-buffer bound
    guard first > 0 else { print("timing read \(first) s; stopping"); exit(1) }
    guard first < 0.2 else { print(String(format: "one pass took %.3f s, over the 0.2 s bound; stopping", first)); exit(1) }
    let maxPasses = 400
    var passes = 0, t = 0.0
    while t < soak && passes < maxPasses {
        let dt = pass()
        guard dt > 0, dt < 0.2 else { print("pass timing \(dt) s out of bounds; stopping"); exit(1) }
        t += dt; passes += 1
    }
    let gbs = Double(slice) * Double(passes) / t / 1e9
    print(String(format: "%@ %5d x %3d  passes %4d  %.3f s  %.2f GB/s", name, groups, tpg, passes, t, gbs))
}
