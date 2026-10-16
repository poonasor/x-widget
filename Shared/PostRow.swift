import SwiftUI

/// One post, shared by the desktop panel and the widget.
struct PostRow: View {
    let post: Post
    var lineLimit = 3
    var avatarSize: CGFloat = 28
    /// Remote images load with AsyncImage, which widgets can't use, so only the desktop panel turns this on.
    var showMedia = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Avatar(post: post, size: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(post.authorName).fontWeight(.semibold).lineLimit(1)
                    Text("@\(post.authorHandle)").foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(post.createdAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .font(.caption)
                Text(post.text)
                    .font(.callout)
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                if showMedia, let media = post.media, !media.isEmpty {
                    MediaGrid(media: media)
                        .padding(.top, 4)
                }
                HStack(spacing: 12) {
                    Metric(symbol: "bubble.left", value: post.replyCount)
                    Metric(symbol: "arrow.2.squarepath", value: post.repostCount)
                    Metric(symbol: "heart", value: post.likeCount)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            }
        }
    }
}

struct Avatar: View {
    let post: Post
    var size: CGFloat

    var body: some View {
        Group {
            if let image = AvatarStore.image(for: post.authorID) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Text(post.authorName.prefix(1))
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hue: Double(post.authorID.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 360) / 360, saturation: 0.5, brightness: 0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct Metric: View {
    let symbol: String
    let value: Int

    var body: some View {
        Label(value.formatted(.number.notation(.compactName)), systemImage: symbol)
            .labelStyle(.titleAndIcon)
    }
}

/// Up to four images in X's layouts: one full-width, two side by side, three as one tall plus two, four as a 2×2 grid.
private struct MediaGrid: View {
    let media: [PostMedia]
    private let spacing: CGFloat = 3
    private let maxHeight: CGFloat = 240

    var body: some View {
        let items = Array(media.prefix(4))
        Group {
            switch items.count {
            case 1:
                // Keep the photo's own shape, but cap very tall images.
                MediaTile(media: items[0])
                    .aspectRatio(max(items[0].aspectRatio ?? 16 / 9, 0.75), contentMode: .fit)
                    .frame(maxHeight: maxHeight)
            case 2:
                HStack(spacing: spacing) { ForEach(items, id: \.imageURL) { MediaTile(media: $0) } }
                    .aspectRatio(16 / 9, contentMode: .fit)
            case 3:
                HStack(spacing: spacing) {
                    MediaTile(media: items[0])
                    VStack(spacing: spacing) { MediaTile(media: items[1]); MediaTile(media: items[2]) }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
            default:
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) { MediaTile(media: items[0]); MediaTile(media: items[1]) }
                    HStack(spacing: spacing) { MediaTile(media: items[2]); MediaTile(media: items[3]) }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
            }
        }
        .clipShape(.rect(cornerRadius: 10))
    }
}

private struct MediaTile: View {
    let media: PostMedia

    var body: some View {
        Color.white.opacity(0.08)
            .overlay {
                AsyncImage(url: media.smallImageURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
            .overlay {
                if media.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .shadow(radius: 4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if media.kind == .gif {
                    Text("GIF")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
                        .padding(6)
                }
            }
            .clipped()
            .accessibilityLabel(media.altText ?? (media.kind == .photo ? "Image" : "Video"))
    }
}
