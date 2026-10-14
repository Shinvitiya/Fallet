import AppKit
import AVFoundation
import CoreText
import ImageIO

// Rebuild docs/demo/fallet-demo.mp4 from the three checked-in app captures.
// Run from the repository root:
// swiftc -target arm64-apple-macosx13.0 -module-cache-path .build/module-cache \
//   -framework AppKit -framework AVFoundation Scripts/make-demo-video.swift \
//   -o .build/make-demo-video && .build/make-demo-video

let width = 1280
let height = 720
let fps: Int32 = 30
let seconds = 9
let output = URL(fileURLWithPath: "docs/demo/fallet-demo.mp4")

struct Scene {
    let image: CGImage
    let title: String
    let detail: [String]
    let imageFrame: CGRect
}

func loadImage(_ path: String) -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Could not read \(path)")
    }
    return image
}

let scenes = [
    Scene(image: loadImage("docs/demo/01-empty-shelf.png"),
          title: "A place for your files",
          detail: ["Open Fallet and drop files", "onto the floating shelf."],
          imageFrame: CGRect(x: 530, y: 205, width: 660, height: 319)),
    Scene(image: loadImage("docs/demo/02-files-on-shelf.png"),
          title: "Keep a batch together",
          detail: ["Take one file to one folder,", "or move them all at once."],
          imageFrame: CGRect(x: 665, y: 140, width: 525, height: 378)),
    Scene(image: loadImage("docs/demo/03-moved-to-folder.png"),
          title: "Done in Finder",
          detail: ["Both files arrived in the", "destination folder."],
          imageFrame: CGRect(x: 645, y: 150, width: 545, height: 380))
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, alpha])!
}

func text(_ value: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight,
          tint: NSColor, in context: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: tint
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
    context.textMatrix = .identity
    context.textPosition = point
    CTLineDraw(line, context)
}

func drawScene(_ scene: Scene, alpha: CGFloat, progress: CGFloat, in context: CGContext) {
    guard alpha > 0 else { return }
    context.saveGState()
    context.setAlpha(alpha)

    text("FALLET", at: CGPoint(x: 80, y: 605), size: 16, weight: .bold,
         tint: NSColor(calibratedRed: 0.71, green: 0.77, blue: 1, alpha: 1), in: context)
    text("FILE SHELF FOR MAC", at: CGPoint(x: 80, y: 576), size: 12, weight: .medium,
         tint: NSColor(calibratedWhite: 0.58, alpha: 1), in: context)
    text(scene.title, at: CGPoint(x: 80, y: 382), size: 40, weight: .bold,
         tint: .white, in: context)
    for (index, line) in scene.detail.enumerated() {
        text(line, at: CGPoint(x: 82, y: 323 - CGFloat(index) * 33), size: 22, weight: .regular,
             tint: NSColor(calibratedWhite: 0.83, alpha: 1), in: context)
    }

    let drift = 8 * sin(progress * .pi)
    let imageFrame = scene.imageFrame.offsetBy(dx: 0, dy: drift)
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 38,
                      color: color(0, 0, 0, 0.46))
    let rounded = CGPath(roundedRect: imageFrame, cornerWidth: 24, cornerHeight: 24, transform: nil)
    context.addPath(rounded)
    context.clip()
    context.draw(scene.image, in: imageFrame)
    context.restoreGState()
}

func pixelBuffer(at time: Double) -> CVPixelBuffer {
    var optionalBuffer: CVPixelBuffer?
    let properties: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                     kCVPixelFormatType_32ARGB, properties as CFDictionary,
                                     &optionalBuffer)
    guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
        fatalError("Could not allocate video frame")
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                  width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
    else { fatalError("Could not draw video frame") }

    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [color(0.060, 0.067, 0.116),
                                         color(0.126, 0.082, 0.183),
                                         color(0.052, 0.067, 0.132)] as CFArray,
                                locations: [0, 0.53, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: 1280, y: 720), options: [])
    context.setFillColor(color(0.20, 0.25, 0.95, 0.10))
    context.fillEllipse(in: CGRect(x: 490, y: 210, width: 560, height: 560))
    context.setFillColor(color(0.98, 0.22, 0.31, 0.10))
    context.fillEllipse(in: CGRect(x: 905, y: -120, width: 470, height: 470))

    let centers = [1.5, 4.5, 7.5]
    for (index, scene) in scenes.enumerated() {
        let distance = abs(time - centers[index])
        let alpha = min(1, max(0, (1.8 - distance) / 0.30))
        drawScene(scene, alpha: alpha, progress: CGFloat(time / Double(seconds)), in: context)
    }

    for index in 0..<3 {
        let rect = CGRect(x: 80 + index * 48, y: 65, width: 36, height: 5)
        context.setFillColor(index == min(2, Int(time / 3))
                             ? color(0.91, 0.36, 0.48) : color(1, 1, 1, 0.22))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 2.5, cornerHeight: 2.5,
                               transform: nil))
        context.fillPath()
    }
    text("Captured from Fallet on macOS", at: CGPoint(x: 80, y: 38), size: 13,
         weight: .regular, tint: NSColor(calibratedWhite: 0.6, alpha: 1), in: context)
    return buffer
}

try? FileManager.default.removeItem(at: output)
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_000_000]
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height
])
writer.add(input)
guard writer.startWriting() else { fatalError("Could not start video writer: \(String(describing: writer.error))") }
writer.startSession(atSourceTime: .zero)

for frame in 0..<(seconds * Int(fps)) {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
    let time = Double(frame) / Double(fps)
    let buffer = pixelBuffer(at: time)
    let presentationTime = CMTime(value: Int64(frame), timescale: fps)
    guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
        fatalError("Could not append frame \(frame): \(String(describing: writer.error))")
    }
}
input.markAsFinished()
let completion = DispatchSemaphore(value: 0)
writer.finishWriting { completion.signal() }
completion.wait()
guard writer.status == .completed else { fatalError("Video failed: \(String(describing: writer.error))") }
print("Created \(output.path)")
