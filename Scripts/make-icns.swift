import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift Scripts/make-icns.swift ICONSET OUTPUT.icns")
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let images: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func appendBigEndian(_ number: UInt32, to data: inout Data) {
    var value = number.bigEndian
    withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
}

var body = Data()
for (type, filename) in images {
    let png = try Data(contentsOf: iconset.appendingPathComponent(filename))
    guard png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
        fatalError("Not a PNG: \(filename)")
    }
    body.append(contentsOf: type.utf8)
    appendBigEndian(UInt32(png.count + 8), to: &body)
    body.append(png)
}

var icns = Data("icns".utf8)
appendBigEndian(UInt32(body.count + 8), to: &icns)
icns.append(body)
try icns.write(to: output, options: .atomic)
