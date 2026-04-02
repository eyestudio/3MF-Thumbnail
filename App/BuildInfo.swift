import Foundation

enum BuildInfo {
    static let version = "1.0"

    /// Returns the modification date of the app's executable as the "build time"
    static var buildTime: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let execURL = Bundle.main.executableURL!
        if let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
           let date = attrs[.modificationDate] as? Date
        {
            return fmt.string(from: date)
        }
        return "unknown"
    }
}
