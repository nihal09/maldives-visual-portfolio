import AppKit

// Generates a subtle film-grain tile (assets/img/noise.png)
let size = 256
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
var seed: UInt64 = 0x9E3779B97F4A7C15
func rnd() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double((seed >> 33) & 0xFFFFFFFF) / 0xFFFFFFFF
}
for y in 0..<size {
    for x in 0..<size {
        let v = rnd()
        let a: Double = v > 0.86 ? (v - 0.86) / 0.14 * 0.16 : 0.0
        let g = v > 0.86 ? 0.55 + 0.45 * v : 0.5
        ctx.setFillColor(CGColor(red: g, green: g, blue: g, alpha: a))
        ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
    }
}
guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: "assets/img/noise.png"))
print("noise.png generated")