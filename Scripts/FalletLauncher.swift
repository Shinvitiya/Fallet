import AppKit

guard let path = Bundle.main.object(forInfoDictionaryKey: "FalletHomebrewTarget") as? String,
      FileManager.default.fileExists(atPath: path),
      NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
    exit(1)
}
