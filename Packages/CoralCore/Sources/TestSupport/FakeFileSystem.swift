import Foundation
import CoralCore

/// In-memory filesystem tree for testing `FilesystemSource` without touching disk.
public final class FakeFileSystem: @unchecked Sendable {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = ["/"]

    public init() {}

    public func addDirectory(at path: String) {
        directories.insert(path)
        // Ensure all parent directories exist
        var current = (path as NSString).deletingLastPathComponent
        while current != "/" && !current.isEmpty {
            directories.insert(current)
            current = (current as NSString).deletingLastPathComponent
        }
    }

    public func addFile(at path: String, content: Data = Data()) {
        files[path] = content
        addDirectory(at: (path as NSString).deletingLastPathComponent)
    }

    public func exists(at path: String) -> Bool {
        files[path] != nil || directories.contains(path)
    }

    public func isDirectory(at path: String) -> Bool {
        directories.contains(path)
    }

    public func contents(at path: String) -> Data? {
        files[path]
    }

    public func contentsOfDirectory(at path: String) -> [String] {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        var result: Set<String> = []

        for key in files.keys {
            if key.hasPrefix(prefix) {
                let remainder = String(key.dropFirst(prefix.count))
                if let first = remainder.split(separator: "/").first {
                    result.insert(prefix + first)
                }
            }
        }

        for dir in directories {
            if dir.hasPrefix(prefix) && dir != path {
                let remainder = String(dir.dropFirst(prefix.count))
                if let first = remainder.split(separator: "/").first {
                    result.insert(prefix + first)
                }
            }
        }

        return result.sorted()
    }
}
