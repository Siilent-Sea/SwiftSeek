import Foundation

public struct FileRow: Equatable {
    public let path: String
    public let pathLower: String
    public let name: String
    public let nameLower: String
    public let isDir: Bool
    public let size: Int64
    public let mtime: Int64

    public init(path: String,
                pathLower: String,
                name: String,
                nameLower: String,
                isDir: Bool,
                size: Int64,
                mtime: Int64) {
        self.path = path
        self.pathLower = pathLower
        self.name = name
        self.nameLower = nameLower
        self.isDir = isDir
        self.size = size
        self.mtime = mtime
    }

    public static func from(url: URL, isDir: Bool, size: Int64, mtime: Int64) -> FileRow {
        let path = url.path
        let name = url.lastPathComponent
        return FileRow(
            path: path,
            pathLower: path.lowercased(),
            name: name,
            nameLower: name.lowercased(),
            isDir: isDir,
            size: size,
            mtime: mtime
        )
    }
}
