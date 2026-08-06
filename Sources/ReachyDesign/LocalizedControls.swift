import SwiftUI

/// The four containers whose `LocalizedStringResource` initialiser Apple shipped
/// only in iOS 26 / macOS 26, backfilled at this app's floor.
///
/// `Text`, `Button`, `Label`, `navigationTitle` and most of the rest have taken one
/// since iOS 16, so a single spelling — `.reachy("…")` — covers the whole UI. These
/// four did not, and without them 28 call sites would have to spell a title as a
/// two-closure builder instead, which is five lines where there was one.
///
/// Each forwards to the `Text`-taking form, which is what the SDK's own iOS 26
/// version does. Both are visible when building against the iOS 26 SDK; the SDK's
/// carries `@_disfavoredOverload`, so these win, and the result is identical either
/// way.
public extension Section where Parent == Text, Content: View, Footer == EmptyView {
    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) })
    }
}

public extension LabeledContent where Label == Text, Content == Text {
    init(_ title: LocalizedStringResource, value: some StringProtocol) {
        self.init(content: { Text(value) }, label: { Text(title) })
    }
}

public extension LabeledContent where Label == Text, Content: View {
    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }
}

public extension TextField where Label == Text {
    init(_ title: LocalizedStringResource, text: Binding<String>) {
        self.init(text: text, label: { Text(title) })
    }
}

public extension SecureField where Label == Text {
    init(_ title: LocalizedStringResource, text: Binding<String>) {
        self.init(text: text, label: { Text(title) })
    }
}
