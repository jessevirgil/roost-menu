#!/usr/bin/env swift
// Composites the supplied artwork (tools/roost-icon.png, rendered from roost-icon.svg) onto the
// standard macOS white icon plate and writes a 1024x1024 PNG.
// Usage: swift tools/make_icon.swift <output.png> <artwork.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let src = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "tools/roost-icon.png"
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high

guard let isrc = CGImageSourceCreateWithURL(URL(fileURLWithPath: src) as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(isrc, 0, nil) else { fatalError("cannot read \(src)") }

// macOS icon grid: 824pt plate inside a 1024pt canvas.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.30))
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.addPath(platePath); ctx.fillPath()
ctx.restoreGState()

// The artwork's own square is 1124 units with the nest ~828 wide; scale so the nest fills ~78% of the plate.
let side: CGFloat = 869
let artRect = CGRect(x: 512 - side / 2, y: 512 - side / 2 + 4, width: side, height: side)
ctx.saveGState()
ctx.addPath(platePath); ctx.clip()
ctx.draw(art, in: artRect)
ctx.restoreGState()

ctx.addPath(platePath)
ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.07)); ctx.setLineWidth(2); ctx.strokePath()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out)") }
print("wrote \(out)")
