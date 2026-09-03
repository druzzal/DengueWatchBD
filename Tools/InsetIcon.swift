import AppKit

// Inset the artwork so iOS's squircle mask stops clipping the mosquito's legs.
//
// The margin is filled with a blurred copy of the same artwork, where the blur
// is done by downscaling and scaling back up. Core Image's blur desaturated the
// border (alpha/colour-space handling on the clamped edge); a resample stays in
// one colour space and simply cannot introduce grey.

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let scale = CGFloat(Double(CommandLine.arguments[3]) ?? 0.88)

let size = 1024
let canvas = CGRect(x: 0, y: 0, width: size, height: size)
guard let source = NSImage(contentsOf: URL(fileURLWithPath: inputPath)) else { exit(1) }

func opaqueContext(_ side: Int) -> CGContext {
    CGContext(data: nil, width: side, height: side,
              bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

guard let sourceTiff = source.tiffRepresentation,
      let sourceRep = NSBitmapImageRep(data: sourceTiff),
      let sourceCG = sourceRep.cgImage else { exit(1) }

// --- backdrop: full-bleed art, blurred by resampling through a tiny buffer ---
let tiny = 40
let small = opaqueContext(tiny)
small.interpolationQuality = .high
small.draw(sourceCG, in: CGRect(x: 0, y: 0, width: tiny, height: tiny))
guard let smallImage = small.makeImage() else { exit(1) }

let bitmap = opaqueContext(size)
bitmap.interpolationQuality = .high
bitmap.draw(smallImage, in: canvas)

// --- foreground: the sharp artwork, inset, feathered into the backdrop ---
let inset = CGFloat(size) * (1 - scale) / 2
let target = CGRect(x: inset, y: inset,
                    width: CGFloat(size) * scale, height: CGFloat(size) * scale)

let feather = 34
let maskSide = size
let maskCtx = CGContext(data: nil, width: maskSide, height: maskSide,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
maskCtx.setFillColor(CGColor(gray: 0, alpha: 1))
maskCtx.fill(canvas)
maskCtx.setFillColor(CGColor(gray: 1, alpha: 1))
maskCtx.fill(target.insetBy(dx: CGFloat(feather) / 2, dy: CGFloat(feather) / 2))
guard let hardMask = maskCtx.makeImage() else { exit(1) }

// Feather the mask the same way: down then up.
let maskTiny = 96
let smallMask = CGContext(data: nil, width: maskTiny, height: maskTiny,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
smallMask.interpolationQuality = .high
smallMask.draw(hardMask, in: CGRect(x: 0, y: 0, width: maskTiny, height: maskTiny))
guard let smallMaskImage = smallMask.makeImage() else { exit(1) }
let softMaskCtx = CGContext(data: nil, width: maskSide, height: maskSide,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
softMaskCtx.interpolationQuality = .high
softMaskCtx.draw(smallMaskImage, in: canvas)
guard let softMask = softMaskCtx.makeImage() else { exit(1) }

bitmap.saveGState()
bitmap.clip(to: canvas, mask: softMask)
bitmap.draw(sourceCG, in: target)
bitmap.restoreGState()

guard let flattened = bitmap.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: flattened)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) at scale \(scale)")

// Usage:
//   swift Tools/InsetIcon.swift <source-1024.png> <output.png> <scale>
//
// 0.93 is what ships: it keeps the mosquito's legs and the map's right edge
// clear of the iOS squircle mask without giving up presence at icon size.
