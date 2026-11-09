#!/usr/bin/env swift
// Draws the Roost Menu app icon (a woven nest with eggs, Google-colour gradient on a white plate)
// and writes a 1024x1024 PNG. Usage: swift tools/make_icon.swift <output.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, a])!
}

// Deterministic "random" so the icon is the same every run.
var seed: UInt64 = 20261105
func rnd(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return lo + (hi - lo) * CGFloat(Double(seed >> 33) / Double(1 << 31))
}

// MARK: Plate (macOS icon grid: 824pt artwork inside a 1024pt canvas)
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.30))
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.addPath(platePath); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(platePath)
ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.07)); ctx.setLineWidth(2); ctx.strokePath()

// MARK: Google gradient
let blue = rgb(66, 133, 244), red = rgb(234, 67, 53), yellow = rgb(251, 188, 5), green = rgb(52, 168, 83)
let gradient = CGGradient(colorsSpace: cs, colors: [blue, red, yellow, green] as CFArray,
                          locations: [0.0, 0.36, 0.66, 1.0])!
let gStart = CGPoint(x: 190, y: 740), gEnd = CGPoint(x: 830, y: 330)

func fillGradient(_ path: CGPath) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(gradient, start: gStart, end: gEnd, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func fillWhite(_ path: CGPath) {
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.addPath(path); ctx.fillPath()
}

// MARK: Twigs
/// An arc of a slightly wobbly, rotated ellipse, as a polyline.
func arc(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, rot: CGFloat, from a0: CGFloat, to a1: CGFloat) -> CGPath {
    let phase = rnd(0, 6.28), wob = rnd(0.012, 0.03)
    let p = CGMutablePath()
    var first = true
    var t = a0
    while t <= a1 {
        let r = t * .pi / 180
        let k = 1 + wob * sin(3 * r + phase)
        let x = rx * k * cos(r), y = ry * k * sin(r)
        let pt = CGPoint(x: cx + x * cos(rot) - y * sin(rot), y: cy + x * sin(rot) + y * cos(rot))
        if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
        t += 2
    }
    return p
}

/// Draw one twig: a white halo (so crossings read as woven) then the gradient stroke.
func twig(_ path: CGPath, width: CGFloat) {
    let halo = path.copy(strokingWithWidth: width + 12, lineCap: .round, lineJoin: .round, miterLimit: 10)
    fillWhite(halo)
    fillGradient(path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10))
}

let cx: CGFloat = 512

// Centre the artwork on the plate and scale it up a little.
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.scaleBy(x: 1.02, y: 1.02)
ctx.translateBy(x: -512, y: -539)

// Back wall of the nest: frowning arcs behind the eggs (the far rim)
for _ in 0..<6 {
    let p = arc(cx: cx + rnd(-10, 10), cy: 640 + rnd(-8, 14), rx: rnd(240, 285), ry: rnd(55, 95),
                rot: rnd(-0.08, 0.08), from: rnd(12, 28), to: rnd(152, 168))
    twig(p, width: rnd(16, 22))
}

// Eggs, sitting in the bowl (white halo, then gradient)
let eggs: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rot: CGFloat)] = [
    (402, 628, 92, 118, 0.24), (516, 646, 96, 122, -0.03), (630, 626, 92, 118, -0.26),
]
for e in eggs {
    var t = CGAffineTransform(translationX: e.x, y: e.y).rotated(by: e.rot)
    let rect = CGRect(x: -e.w / 2, y: -e.h / 2, width: e.w, height: e.h)
    let egg = CGPath(ellipseIn: rect, transform: &t)
    var t2 = t
    let halo = CGPath(ellipseIn: rect.insetBy(dx: -9, dy: -9), transform: &t2)
    fillWhite(halo)
    fillGradient(egg)
    var t3 = CGAffineTransform(translationX: e.x - e.w * 0.17, y: e.y + e.h * 0.2).rotated(by: e.rot)
    let hl = CGPath(ellipseIn: CGRect(x: -e.w * 0.11, y: -e.h * 0.16, width: e.w * 0.22, height: e.h * 0.32), transform: &t3)
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.38)); ctx.addPath(hl); ctx.fillPath()
}

// Front wall: smiling arcs, the highest crossing the eggs' lower halves, each lower one deeper
for i in 0..<9 {
    let k = CGFloat(i) / 8
    let ry = 78 + k * 235
    let p = arc(cx: cx + rnd(-10, 10), cy: 662 + rnd(-6, 6), rx: 300 + rnd(-22, 22) + k * 12, ry: ry + rnd(-6, 6),
                rot: rnd(-0.07, 0.07), from: rnd(172, 186), to: rnd(354, 368))
    twig(p, width: rnd(22, 30))
}

ctx.restoreGState()

// MARK: Write PNG
let image = ctx.makeImage()!
let url = URL(fileURLWithPath: out)
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out)") }
print("wrote \(out)")
