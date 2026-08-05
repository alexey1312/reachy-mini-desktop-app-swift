import SwiftUI

/// The Hub's avatar for one account, with a monogram behind it.
///
/// Its own type rather than a helper on the section that used to own it: the
/// toolbar button renders one too, and anything a `#Preview` body reaches has to
/// be visible target-wide — Prefire copies that body into a generated file, where
/// a `private` helper does not exist.
struct HFAvatar: View {
    let username: String
    var size: CGFloat = 32

    /// A snapshot must not go to the network, so previews stop at the monogram the
    /// placeholder already draws.
    @Environment(\.reachyPreviewMode) private var previewMode

    var body: some View {
        if previewMode {
            monogram
        } else if let url = URL(string: "https://huggingface.co/api/users/\(username)/avatar") {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                monogram
            }
            .frame(width: size, height: size)
            .clipShape(.circle)
        } else {
            monogram
        }
    }

    private var monogram: some View {
        Circle()
            .fill(.tint.opacity(0.2))
            .overlay {
                Text(username.prefix(1).uppercased())
                    .font(size < 30 ? .subheadline : .headline)
            }
            .frame(width: size, height: size)
    }
}
