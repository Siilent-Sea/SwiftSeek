import Foundation

public enum AppPaths {
    public static let appFolderName = "SwiftSeek"
    public static let databaseFileName = "index.sqlite3"

    public struct Paths {
        public let supportDirectory: URL
        public let databaseURL: URL

        public init(supportDirectory: URL, databaseURL: URL) {
            self.supportDirectory = supportDirectory
            self.databaseURL = databaseURL
        }
    }

    public static func ensureSupportDirectory(override: URL? = nil) throws -> Paths {
        let base: URL
        if let override {
            base = override
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            base = appSupport.appendingPathComponent(appFolderName, isDirectory: true)
        }

        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )

        return Paths(
            supportDirectory: base,
            databaseURL: base.appendingPathComponent(databaseFileName)
        )
    }
}
