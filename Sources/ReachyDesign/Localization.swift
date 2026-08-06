import Foundation

public extension LocalizedStringResource {
    /// A string from this app's one catalogue.
    ///
    /// It has to live here rather than beside the views. A `Text("Connect")` inside
    /// a library target resolves its key against `Bundle.main` — the bundle of
    /// whichever *executable* is running — so a catalogue under `Sources/ReachyUI`
    /// would never be read at all, and the app would ship English while looking
    /// fully localized in the editor. Naming the bundle is what fixes that, and
    /// `LocalizedStringResource` is the only currency SwiftUI takes that can carry
    /// one: `Text`, `Button`, `Label`, `Section`, `navigationTitle` and the rest all
    /// have a `@_disfavoredOverload` taking it.
    ///
    /// The catalogue sits in `ReachyDesign` because **both** executables link this
    /// target — the app and the widget extension — and each therefore gets its own
    /// copy of the resource bundle. One catalogue, one hand-off to a translator,
    /// two bundles served.
    static func reachy(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
