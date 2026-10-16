import SwiftUI

/// One post, shared by the desktop panel and the widget.
struct PostRow: View {
    let post: Post
    var lineLimit = 3
    var avatarSize: CGFloat = 28

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
