// Recolour the app icon and rebuild AppIcon.icns.
// Usage: swift scripts/make-icon.swift <source 1024 px PNG> <out 1024 px PNG> <out .icns>
//
// The source is the full icon art (a rounded square with a white chip on a gradient, transparent
// outside). Near-white pixels, the chip, stay white; every other pixel is repainted with a
// vertical yellow-to-amber gradient. The alpha is kept, so the shape and the antialiased edges
// are unchanged. The result is written as a 1024 px PNG and as an .icns with all ten sizes.
import AppKit
import CoreGraphics

let a = CommandLine.arguments
guard a.count == 4 else { print("usage: make-icon.swift <src.png> <out.png> <out.icns>"); exit(2) }
guard let src = NSImage(contentsOfFile: a[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { print("cannot read \(a[1])"); exit(1) }
let w = src.width, h = src.height
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let bpr = w * 4
var px = [UInt8](repeating: 0, count: h * bpr)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))

// gradient ends (sRGB): warm yellow at the top, amber at the bottom
let top: (Double, Double, Double) = (1.000, 0.776, 0.102)
let bot: (Double, Double, Double) = (0.941, 0.565, 0.000)
func smooth(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
    let t = min(1, max(0, (x - lo) / (hi - lo))); return t * t * (3 - 2 * t)
}
for y in 0..<h {
    let t = Double(y) / Double(h - 1)   // row 0 is the top in this bitmap
    let g = (top.0 + (bot.0 - top.0) * t, top.1 + (bot.1 - top.1) * t, top.2 + (bot.2 - top.2) * t)
    for x in 0..<w {
        let i = y * bpr + x * 4
        let alpha = Double(px[i + 3]) / 255
        guard alpha > 0 else { continue }
        // un-premultiply, then measure whiteness by the smallest channel
        let r = Double(px[i]) / 255 / alpha, gg = Double(px[i + 1]) / 255 / alpha, b = Double(px[i + 2]) / 255 / alpha
        let white = smooth(min(r, gg, b), 0.55, 0.92)
        let out = (g.0 + (1 - g.0) * white, g.1 + (1 - g.1) * white, g.2 + (1 - g.2) * white)
        px[i]     = UInt8(max(0, min(255, (out.0 * alpha * 255).rounded())))
        px[i + 1] = UInt8(max(0, min(255, (out.1 * alpha * 255).rounded())))
        px[i + 2] = UInt8(max(0, min(255, (out.2 * alpha * 255).rounded())))
    }
}
let master = ctx.makeImage()!

func writePNG(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func scaled(_ img: CGImage, _ s: Int) -> CGImage {
    let c = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: s * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(img, in: CGRect(x: 0, y: 0, width: s, height: s))
    return c.makeImage()!
}
writePNG(master, a[2])
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for (name, s) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                  ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512),
                  ("512x512@2x", 1024)] {
    writePNG(scaled(master, s), set.appendingPathComponent("icon_\(name).png").path)
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", a[3]]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
exit(p.terminationStatus)
