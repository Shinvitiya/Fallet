import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum ShelfOperationError: LocalizedError {
    case noOutput
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noOutput: return "The operation produced no output."
        case .failed(let message): return message
        }
    }
}

enum ShelfOperations {
    static func createZIP(from sources: [URL], at destination: URL) throws {
        guard !sources.isEmpty else { throw ShelfOperationError.noOutput }
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appendingPathComponent("Fallet-ZIP-\(UUID().uuidString)")
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        for source in sources {
            var target = staging.appendingPathComponent(source.lastPathComponent)
            var number = 2
            while manager.fileExists(atPath: target.path) {
                let stem = source.deletingPathExtension().lastPathComponent
                let ext = source.pathExtension
                let name = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
                target = staging.appendingPathComponent(name)
                number += 1
            }
            try manager.copyItem(at: source, to: target)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-c", "-k", "--sequesterRsrc", staging.path, destination.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0, manager.fileExists(atPath: destination.path) else {
            throw ShelfOperationError.failed("Could not create the ZIP archive.")
        }
    }

    static func resizeImage(at source: URL, toWidth width: Int, saveTo destination: URL) throws {
        guard width > 0, width <= 16000,
              let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ShelfOperationError.failed("Could not read that image.")
        }
        let height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
        guard height <= 16000,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ShelfOperationError.failed("Could not prepare the resized image.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage(),
              let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ShelfOperationError.failed("Could not write the resized image.")
        }
        CGImageDestinationAddImage(writer, output, nil)
        guard CGImageDestinationFinalize(writer) else {
            throw ShelfOperationError.failed("Could not save the resized image.")
        }
    }

    static func recognizeText(in imageURL: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { throw ShelfOperationError.noOutput }
        return lines.joined(separator: "\n")
    }

    static func runScript(at script: URL, with files: [URL]) throws -> String {
        let task = Process()
        if FileManager.default.isExecutableFile(atPath: script.path) {
            task.executableURL = script
            task.arguments = files.map(\.path)
        } else {
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = [script.path] + files.map(\.path)
        }
        let output = Pipe()
        task.standardOutput = output
        task.standardError = output
        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard task.terminationStatus == 0 else {
            throw ShelfOperationError.failed(message.isEmpty ? "Script exited with status \(task.terminationStatus)." : message)
        }
        return message
    }
}
