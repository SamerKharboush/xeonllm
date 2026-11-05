// Host-to-card copy rate of one Metal device (ticket beta7-03): a blit from a shared (host)
// buffer into a private (card) buffer, `chunk` MiB per command buffer so no buffer runs long
// (a seconds-long command buffer on a D700 rebooted this Mac, 2026-11-04 19:00).
//
//   swiftc -O tools/metal-probe/hostcopy.swift -o hostcopy
//   ./hostcopy <device index> [total MiB=1024] [chunk MiB=64]
//
// Prints the rate from GPU time and from wall time (wall includes commit and wait).
import Metal
import Foundation

let a = CommandLine.arguments
guard a.count >= 2, let di = Int(a[1]) else { print("usage: hostcopy <device> [MiB] [chunk MiB]"); exit(2) }
let totalMiB = a.count > 2 ? Int(a[2]) ?? 1024 : 1024
let chunkMiB = a.count > 3 ? Int(a[3]) ?? 64 : 64
let dev = MTLCopyAllDevices()[di]
let total = totalMiB << 20, chunk = chunkMiB << 20
let src = dev.makeBuffer(length: total, options: .storageModeShared)!
memset(src.contents(), 0x5a, total)
let dst = dev.makeBuffer(length: total, options: .storageModePrivate)!
let q = dev.makeCommandQueue()!
func copyAll() -> (gpu: Double, wall: Double) {
    var gpu = 0.0
    let t0 = Date()
    var off = 0
    while off < total {
        let cb = q.makeCommandBuffer()!; let b = cb.makeBlitCommandEncoder()!
        let n = min(chunk, total - off)
        b.copy(from: src, sourceOffset: off, to: dst, destinationOffset: off, size: n)
        b.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        guard cb.status == .completed else { print("blit failed: \(String(describing: cb.error))"); exit(1) }
        let dt = cb.gpuEndTime - cb.gpuStartTime
        guard dt >= 0, dt < 0.2 else { print("blit timing \(dt) s out of bounds; stopping"); exit(1) }
        gpu += dt; off += n
    }
    return (gpu, Date().timeIntervalSince(t0))
}
_ = copyAll()  // warmup: first touch of the private pages, discarded
print("device \(di): \(dev.name), \(totalMiB) MiB in \(chunkMiB) MiB command buffers")
for i in 1...5 {
    let r = copyAll()
    let gpuRate = r.gpu > 0 ? String(format: "%.2f", Double(total) / r.gpu / 1e9) : "n/a (zero GPU time)"
    print(String(format: "rep %d  wall %.3f s  %.2f GB/s wall  ", i, r.wall, Double(total) / r.wall / 1e9) + "GPU-time rate \(gpuRate) GB/s")
}
