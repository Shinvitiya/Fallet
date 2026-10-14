import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: remove-icon-border input.png output.png\n", stderr)
    exit(1)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: inputURL),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1254,
        pixelsHigh: 1254,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not load the Fallet icon artwork.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.shouldAntialias = true
context.cgContext.clear(CGRect(x: 0, y: 0, width: 1254, height: 1254))

// The approved artwork's tile field spans this rounded outline. Keeping the
// original pixels inside it preserves the gradients and the gaps between tiles.
let tileOutline = NSBezierPath(
    roundedRect: CGRect(x: 150, y: 189, width: 954, height: 923),
    xRadius: 158,
    yRadius: 158
)
tileOutline.addClip()
source.draw(
    in: CGRect(x: 0, y: 0, width: 1254, height: 1254),
    from: .zero,
    operation: .copy,
    fraction: 1
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the borderless Fallet icon.\n", stderr)
    exit(1)
}
try png.write(to: outputURL, options: .atomic)
