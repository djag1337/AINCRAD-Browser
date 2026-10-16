// Draws AINCRAD Browser's icon in AINCRAD's style (same tile and sky, one glowing SAO button with
// a globe) into an asset-catalog icon set. Usage: swift scripts/make_icon.swift Browser/Assets.xcassets
import AppKit

func draw(_ px: Int) -> Data {
    let s = CGFloat(px) / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) in CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(rgb(20, 27, 38, 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
    let sky = CGGradient(colorsSpace: nil, colors: [rgb(58, 92, 138, 1), rgb(22, 30, 46, 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()
    // The SAO button: white glass circle with an orange ring and glow.
    let c = CGPoint(x: 512, y: 512), r: CGFloat = 270
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: rgb(242, 165, 22, 0.85))
    ctx.setStrokeColor(rgb(242, 165, 22, 1)); ctx.setLineWidth(22)
    ctx.strokeEllipse(in: CGRect(x: c.x - r - 22, y: c.y - r - 22, width: 2 * (r + 22), height: 2 * (r + 22)))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); ctx.clip()
    let glass = CGGradient(colorsSpace: nil, colors: [rgb(255, 255, 255, 1), rgb(222, 224, 230, 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(glass, start: CGPoint(x: 512, y: c.y + r), end: CGPoint(x: 512, y: c.y - r), options: [])
    ctx.restoreGState()
    // Globe: outline, equator, two latitudes and a meridian ellipse, in the menu's grey.
    let g: CGFloat = 165
    ctx.setStrokeColor(rgb(90, 94, 102, 1)); ctx.setLineWidth(20)
    ctx.strokeEllipse(in: CGRect(x: c.x - g, y: c.y - g, width: 2 * g, height: 2 * g))
    ctx.strokeEllipse(in: CGRect(x: c.x - g * 0.45, y: c.y - g, width: g * 0.9, height: 2 * g))
    ctx.move(to: CGPoint(x: c.x - g, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + g, y: c.y)); ctx.strokePath()
    for dy in [g * 0.55, -g * 0.55] {
        let half = sqrt(g * g - dy * dy)
        ctx.move(to: CGPoint(x: c.x - half, y: c.y + dy)); ctx.addLine(to: CGPoint(x: c.x + half, y: c.y + dy)); ctx.strokePath()
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let catalog = URL(fileURLWithPath: CommandLine.arguments[1])
let set = catalog.appendingPathComponent("AppIcon.appiconset")
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
try! #"{"info":{"author":"xcode","version":1}}"#.write(to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
var images: [String] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! draw(size * scale).write(to: set.appendingPathComponent(name))
        images.append(#"{"idiom":"mac","size":"\#(size)x\#(size)","scale":"\#(scale)x","filename":"\#(name)"}"#)
    }
}
try! #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(set.path)")
