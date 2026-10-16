import AppKit

/// Avatars are downloaded to the App Group because widgets can't load remote images at render time.
enum AvatarStore {
    private static var directory: URL {
        let url = AppGroup.containerURL.appending(path: "Avatars", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(_ authorID: String) -> URL {
        directory.appending(path: "\(authorID).img")
    }

    static func image(for authorID: String) -> NSImage? {
        NSImage(contentsOf: fileURL(authorID))
    }

    static func prefetch(_ posts: [Post]) async {
        var seen = Set<String>()
        let missing = posts.filter { post in
            post.avatarURL != nil && seen.insert(post.authorID).inserted
                && !FileManager.default.fileExists(atPath: fileURL(post.authorID).path)
        }
        await withTaskGroup(of: Void.self) { group in
            for post in missing.prefix(30) {
                group.addTask {
                    // "_normal" is 48px; "_bigger" (73px) stays crisp on Retina.
                    let url = URL(string: post.avatarURL!.absoluteString.replacingOccurrences(of: "_normal", with: "_bigger"))!
                    if let (data, _) = try? await URLSession.shared.data(from: url) {
                        try? data.write(to: fileURL(post.authorID), options: .atomic)
                    }
                }
            }
        }
    }
}
