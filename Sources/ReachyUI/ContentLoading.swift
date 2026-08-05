import SwiftUI

private struct ContentLoadingModifier: ViewModifier {
    let isPresented: Bool
    let title: String

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ProgressView {
                    Text(title)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// An initial or uncached content request, centred in the space the eventual
    /// rows will occupy. Navigation, filters and pickers remain available around it.
    func contentLoading(isPresented: Bool, title: String) -> some View {
        modifier(ContentLoadingModifier(isPresented: isPresented, title: title))
    }
}
