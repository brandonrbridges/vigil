import Foundation

struct RemoteFile: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modified: String
    let permissions: String

    var icon: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "log": return "doc.text"
        case "json", "yml", "yaml", "xml", "toml": return "doc.badge.gearshape"
        case "swift", "py", "js", "ts", "go", "rs", "rb", "sh", "bash": return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        case "zip", "tar", "gz", "bz2", "xz": return "doc.zipper"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "flac", "aac": return "music.note"
        case "pdf": return "doc.richtext"
        case "conf", "cfg", "ini", "env": return "gearshape"
        default: return "doc"
        }
    }

    private static nonisolated(unsafe) let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var formattedSize: String {
        guard !isDirectory else { return "—" }
        return Self.byteFormatter.string(fromByteCount: size)
    }
}
