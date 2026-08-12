import AppKit
import UniformTypeIdentifiers

/// Reads a Finder drag/drop of a folder (public.file-url) into a URL.
enum FolderDrop {
    static func handle(_ providers: [NSItemProvider], completion: @escaping (URL) -> Void) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var path: String?
            if let url = item as? URL {
                path = url.path
            } else if let url = item as? NSURL {
                path = url.path
            } else if let data = item as? Data {
                path = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                path = string
            }
            guard let path else { return }
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            DispatchQueue.main.async {
                if exists && isDir.boolValue {
                    completion(URL(fileURLWithPath: path))
                }
            }
        }
    }
}
