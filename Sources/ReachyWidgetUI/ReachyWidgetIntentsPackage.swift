import AppIntents

/// Declares this package's intents and entities to whoever links it.
///
/// A `ControlWidgetButton` holds an intent instance built by code compiled into
/// the extension, so it runs with no metadata at all — which is why the wake and
/// sleep controls worked without this. A widget's **configuration UI** is the
/// opposite: the parameter list, the entity type and its query are all read out
/// of the host's `Metadata.appintents` bundle, and types declared in a static
/// library are exactly what goes missing there. The app and the extension each
/// name this package in an `AppIntentsPackage` of their own so extraction reaches
/// it.
public struct ReachyWidgetIntentsPackage: AppIntentsPackage {}
