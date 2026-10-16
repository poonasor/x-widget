import Foundation

/// Placeholder posts shown until an X Client ID is configured, and in previews.
enum DemoData {
    static func posts(for kind: FeedKind) -> [Post] {
        let base: [(String, String, String, Int)] = kind == .following ? [
            ("Swift", "swiftlang", "Swift 6.3 is out with faster builds and improved concurrency diagnostics.", 4),
            ("Apple Developer", "AppleDevs", "Widgets on macOS now support Liquid Glass rendering modes. Here's how to adopt them.", 18),
            ("Ricky", "perpetualmedia", "Building a live X feed that sits right on the desktop. No box, full height.", 32),
            ("WWDC", "WWDC", "Session videos are now available with transcripts and code samples.", 55),
            ("SwiftUI Lab", "SwiftUILab", "Tip: use .contentTransition(.numericText()) for counters that animate smoothly.", 71),
            ("Xcode", "xcode", "Previews now render widgets in every size class side by side.", 95),
        ] : [
            ("Space News", "spacenews", "Starship completes another full-duration test flight with booster catch.", 6),
            ("Tech Daily", "techdaily", "Waymo expands driverless service to three more cities this fall.", 21),
            ("Design Notes", "designnotes", "Why glass interfaces finally work in 2026: contrast, motion and restraint.", 40),
            ("Markets", "markets", "Global indices open higher as chip stocks rally on earnings beats.", 63),
            ("Culture", "culture", "Lo-fi beats stream from an unexpected source tops the charts.", 88),
            ("Science", "science", "Researchers map 1,000 new deep-sea species in a single expedition.", 120),
        ]
        return base.enumerated().map { index, item in
            Post(
                id: "demo-\(kind.rawValue)-\(index)",
                text: item.2,
                createdAt: .now.addingTimeInterval(TimeInterval(-item.3 * 60)),
                authorID: "demo-\(item.1)",
                authorName: item.0,
                authorHandle: item.1,
                avatarURL: nil,
                likeCount: (index + 3) * 137,
                replyCount: (index + 1) * 12,
                repostCount: (index + 2) * 31
            )
        }
    }
}
