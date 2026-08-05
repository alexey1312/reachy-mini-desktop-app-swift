import ReachyKit
import SwiftUI

/// One app in the store list.
struct AppStoreRow: View {
    let app: RobotApp
    var isInstalled = false
    var isRunning = false
    var hasUpdate = false
    var isStartupApp = false

    var body: some View {
        HStack(spacing: 12) {
            AppArtworkTile(app: app)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(app.title)
                        .font(.headline)
                        .lineLimit(1)
                    if app.isOfficial {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Official")
                    }
                    if app.isPrivate {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Private")
                    }
                }
                .font(.caption)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String? {
        app.summary ?? app.author
    }

    /// Author and likes are all the Hub offers as a reputation signal, and the
    /// only way to tell two similarly named apps apart.
    private var footnote: String? {
        var parts: [String] = []
        if let author = app.author, app.summary != nil {
            parts.append(author)
        }
        if let likes = app.likes, likes > 0 {
            parts.append("♥ \(likes)")
        }
        if isStartupApp {
            parts.append("Starts on wake-up")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        if isRunning {
            Label("Running", systemImage: "waveform")
                .labelStyle(.iconOnly)
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative)
                .accessibilityLabel("Running")
        } else if hasUpdate {
            Text("Update")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.tint, in: .capsule)
                .foregroundStyle(.white)
        } else if isInstalled {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Installed")
        } else {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.tint)
                .accessibilityLabel("Not installed")
        }
    }
}
