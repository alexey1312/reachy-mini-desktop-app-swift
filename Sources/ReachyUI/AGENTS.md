# ReachyUI

Shared SwiftUI views for all platforms (macOS/iPadOS/iOS). Depends on ReachyKit and ReachyMedia (WebRTC camera).

- Adaptive layouts, not per-platform copies; `#if os(iOS)` only for platform-exclusive APIs (Settings deep link etc.).
- `horizontalSizeClass` is unavailable on macOS — guard size-class branching with `#if os(macOS)` (always regular there).
  The root used to build a two-column `HStack` for a regular width and hide the Live tab on a compact one;
  `.tabViewStyle(.sidebarAdaptable)` does that adaptation itself, and it is iOS 18 / macOS 15, not an iOS 26 API.
  Reaching for the size class to fork a _layout_ is still a sign the layout is being forked rather than adapted.
- **There is exactly one size-class branch, in `FloatingViewportModifier`, and it is not a layout fork.** The floating
  viewport asks a different question: not "how wide is this" but **"does the shell draw a tab bar or a sidebar"**. A
  sidebar keeps the Live tab beside every other destination, so there is nothing to float out of it and no second
  place the viewport could go; a tab bar hides it, which is the whole reason the window exists. `.sidebarAdaptable`
  makes that decision on the size class and offers no way to ask what it decided, so the modifier reads the same input
  and writes `FloatingViewportModel.hasTabBar`. False collapses `placement` to `.inline` everywhere — the exact
  behaviour this target had before the window existed, including `viewportIsOnScreen`. This entry used to say nothing
  in the target branched on the size class; do not "restore" it by deleting the branch.
- **Navigation is `ReachyRouter` plus two destinations.** `ReachyRootView` owns what outlives a screen and picks the
  gate or the shell; `Navigation/` holds the router, the effect cluster and the sheet stack; `Shell/` holds the five
  tabs. The five are unconditional — a tab that comes and goes forces the shell to catch its disappearance and drag
  the selection elsewhere, which is what `onChange(of: offersLiveTab)` used to do. An unavailable feature renders an
  unavailable state inside its own tab instead.
- **The running-app dock is a tab accessory, and it is not a `safeAreaInset` on the `TabView`. Do not put it back.**
  It was one for five releases, on the reasoning that growing the `TabView`'s safe area would push the bar up and
  leave the strip below it — the Telegram shape. A `safeAreaInset` does not shrink the frame it is applied to, and
  that safe area does not cross into the tab bar's controller or into the tabs' hosting controllers. Measured off the
  references with a pixel diff: with the dock up, the tab's content was **byte-identical** to the dock-free capture
  for the top 63% of the frame and the tab bar was **absent from the image entirely**. With an app running there was
  no tab bar on screen at all. `ReachyTabAccessory` holds the replacement and the reason each half exists.
  - **The tab bar minimises again, and that reverses the previous entry here.** It was switched off because the bar
    shrank into the row the opaque strip occupied and the whole bar went with it. The accessory _is_ that row, so
    minimising is now the interaction rather than the thing that breaks it: `reachyMinimizingTabBar()` takes no flag.
    Nothing scrolls in a snapshot, so no reference covers this in either direction — it is a device check.
  - **The old entry read `Root — dock on the apps tab` as showing the bar where the layout puts it.** It showed the
    bar buried. When a reference is the evidence for a claim about layout, say which pixels — and see
    `ReachyDesign/AGENTS.md` on why no reference can be evidence about the safe area at all.
- **`.unreachable` belongs to the shell, not the gate.** Only `.idle` and `.connecting` show the gate. A network blip
  must not pull the tab bar out from under a finger, and the robot screen already reports the state in place.
- **The gate's fork has progress conditions, and they only ever delay.** For `.connected`, `isConnectedEnough` waits
  until `progress.displayed` has caught the session and `progress.holdsGate` is false. Crossing that line throws the
  gate's whole subtree away, so the equality check keeps the child phase observer alive long enough to see the final
  transition, and the hold then keeps its three checkmarks on screen — on a local network the stages can resolve in
  tens of milliseconds and otherwise read as an unexplained flash. `.unreachable` bypasses both conditions: it is a
  later network blip that belongs to the shell and must never resurrect the gate.
  `ConnectProgressModel` therefore lives in the root, not in the gate: it holds each stage on screen for a floor of
  `dwell`, holds one further `dwell` after the last frame, and releases on a `maxHold` ceiling that depends on
  nothing. At `dwell: .zero` it never holds at all, which is what every preview injects and why the reference images
  behave as they did before it existed.
- **Anything conditional on "an attempt is running" mounts and unmounts every 10 s.** The candidate sweep beats on
  that period and an automatic attempt falls back to `.idle` rather than `.failed`, so the phase walks
  `idle → handshaking → idle` forever while nothing answers. This was a reported bug — the screen visibly compressed
  and expanded — and it had **two** sources, not one: the connection stepper as a form section, and the `robotError`
  section, because `beginAttempt` clears `robotError` while `failAttempt` sets it for automatic attempts too (its
  `guard !automatically` comes after the assignment). Fixing only the first leaves the symptom intact. The rail is now
  mounted for the whole life of the gate, its detail slot reserves one caption line whether or not there is anything
  to say, and `robotError` is shown only once `automaticConnectionAllowed` is false. Before adding anything to this
  screen, ask what it does on that heartbeat. **`.disabled(!phase.acceptsConnectionChoice)` is on that heartbeat too**
  — the Hugging Face segment carried it and went dead every 10 s under a finger, which is the third instance of the
  same bug and the reason `YourReachiesSection` is now the one segment nothing disables: a robot on the relay is not
  on this Wi-Fi, so a sweep of this one says nothing about whether it can be reached.
- **Privacy permissions are one screen and four in-place refusals, and the split is deliberate.**
  `Settings/Permissions/` holds the overview: `PermissionsScreen` reports Bluetooth, Local Network and
  the microphone, and offers each one an action. Its governing rule is that **opening it must never raise
  a prompt** — `refresh()` reads only what can answer without asking, and every prompting path is behind a
  button. Bluetooth is the awkward one: there is no `requestAuthorization` for it, so "Allow" builds a
  short-lived central, which is exactly what `CoreBluetoothTransport` says to do only behind a screen that
  has explained itself. This screen, with a "why" under every row, _is_ that screen; opening it still is
  not. It is reachable from Settings **and** from the gate through `router.showsPermissions`, because the
  Settings tab does not exist until a robot has answered and two of the three permissions are what
  answering takes. A `Button` and a sheet rather than a `NavigationLink`: `PreviewScene.connection` has no
  `NavigationHost`, and adding one would put an empty large-title bar on all thirteen references.
  `PrivacySettingsLink` is the one deep link — the same six lines used to sit in three screens, each under
  `#if os(iOS)`, so on macOS a refusal was reported with **no way at all to act on it**. It is `public`
  only because `SpikeView` calls it. And the Local Network banner now lives in
  `ConnectionScreen.privacySection`, outside the route segments, for the reason `setUpSection` is: it used
  to sit in `NetworkRobotsSection`, where only one of the three routes could show it, while the manual
  address — where a blocked user goes next — failed just as silently.
- Leaves stay injectable rather than reading the router: `ConnectionScreen.showRemoteRobots` is optional because its
  absence is what hides `YourReachiesSection` in previews. The router is the shell's business.
- All robot interaction goes through `RobotSession` / `RobotBrowser` from ReachyKit — no direct URLSession here.
- Screen logic belongs in a `@MainActor @Observable` model beside the view (`MovesModel`, `LogConsoleModel`), covered
  by `Tests/ReachyUITests`; the view stays thin. `@Observable` does honour `didSet`, so derived caches can live there.
- **A model must never be constructed inside a `.sheet` content closure.** SwiftUI re-runs that closure on every
  update of the view the sheet hangs off, so the model is silently replaced by a fresh, empty one — and `.task` does
  not run a second time, so nothing refills it. `RootSheets` hangs off `ReachyRootView`, whose body reads
  `session.phase`, and the candidate sweep walks that `idle → handshaking → idle` every 10 s: "Your Reachies" listed
  the account's robots and then swapped them for a permanent spinner within seconds of opening. The model now lives in
  the root's `@State` and `YourReachiesScreen` adopts it into `@State` of its own, the way `HFAccountSection` already
  did — which is why the sign-in card never showed the same symptom despite being built the same way. The rule reads
  the same for `NavigationLink(destination:)` and for anything else that takes a `@ViewBuilder` the parent re-runs.
- Content catalogues use `contentLoading(isPresented:title:)` for their initial or uncached load. The model must
  distinguish "never answered" from a real empty result and expose loading before `.task` gets its first turn, so the
  first frame never lies with an empty-state. A refresh keeps any rows already on screen; only a request with no data
  gets the centred, lightly robot-themed label. Every such state gets a frozen preview and recorded snapshots.
- `Section` has no title-plus-footer overload: `Section("X") { … } footer: { … }` fails to compile with a misleading
  "generic parameter 'Content' could not be inferred". Either `Section("X") { … }` or the full
  `Section { … } header: { Text("X") } footer: { … }`.
- A container view taking a closure argument _and_ two trailing `@ViewBuilder`s trips SwiftLint's
  `multiple_closures_with_trailing_closure`. Pass the extra behaviour as a child view instead
  (`OnboardingBackButton`), not as a third closure.
- `background(_:)` defaults to `ignoresSafeAreaEdges: .all`, so a full-bleed backdrop also paints the inset the
  floating tab bar sits in — bottom on iPhone, top on iPad. That bar is glass and renders whatever it finds there, so
  it turns dark on that one tab, a frame behind the switch. Neither viewport paints a backdrop any more: the 3D scene
  and the camera's letterbox both take the system background, so the chrome over them stays legible in both
  appearances. **Do not pin a colour under adaptive chrome** — every such backdrop drags a pinned foreground along
  with it, and then neither half can be removed alone. The Live tab's `Color.black` forced
  `toolbarColorScheme(.dark)` to keep the title readable (drop one and the title goes white-on-white or
  black-on-black); the camera's forced a white `Connecting…` for the same reason. `RTCMTLVideoView` clears its own
  unfilled area, so the video never needed the SwiftUI backdrop — that one only ever painted the safe-area insets.
- Deployment floor is iOS 18 / macOS 15 (`Package.swift`, `Apps/Project.swift`), set by `RealityView`.
  `ScrollPosition`, `onScrollPhaseChange` and `onScrollGeometryChange` are available; the zero-height sentinel row in
  `LogConsoleScreen` predates the bump and is not a required pattern.

## Errors

**An error is shown by the screen whose action caused it.** A daemon failure goes into the slot on that screen's
model — `AppStoreModel.lastError`, `MovesModel.lastError`, `AudioSettingsModel.errorMessage`,
`SystemUpdateModel.state`, `WiFiSettingsCard.loadFailure`, `HFAccountSection.linkError`. `RobotSession.robotError`
is **not** a fallback for anything: it holds the robot's connection and power, which are the only failures with no
screen of their own, and `RobotScreen` / `ConnectionScreen` are its only readers. It used to be `lastError` and
every funnel wrote to it, which is how an Apps failure — and before that a _cancelled_ Apps call — ended up printed
on the Robot tab.

- **Fill a slot with `lastError.recordDaemonFailure(error)`** (`DaemonFailure.swift`), never by describing the error
  here. Each of these models used to carry its own `describe` helper, and the moment the session stopped absorbing
  cancellations those eight copies would each have started printing the word "cancelled" on their own tab. The one
  filter is `RobotSession.message(for:)`; `recordDaemonFailure` is the one-liner over it, and it logs on the way past.
- Where the failure lands in a **state enum** rather than an optional (`SystemUpdateModel`, `AppInstallModel`), the
  same rule reads `guard let message = RobotSession.message(for: error) else { return }` — pulled into a private
  `fail(on:)` in both, because two of those guards in one function put `install` over SwiftLint's cyclomatic limit.
- `OnboardingModel` and `HFSignInModel` keep their own `describe`: they report BLE and `ASWebAuthenticationSession`
  failures, neither of which is a daemon call, and the latter already models cancellation as its own error type.
  `YourReachiesModel` maps relay failures to sentences of its own and so guards on `RobotSession.isCancellation`
  at the top of `report(_:)` instead.
- **A crashed app's `error` is a stderr _tail_, not a line, and only one surface may inline it.**
  `RobotAppStatus.error` opens with the daemon's own `Process exited with code 1` and carries the app's last stderr
  lines under it — uvicorn's logging interleaved with a Python traceback. `RunningAppCaption.label` therefore takes
  `Failure`: the dock passes `.inline` because its one caption line is the only place a crash can be read, and
  `AppDetailSheet` passes `.shownSeparately` because `failureRow` prints the whole tail two rows below. It used to
  inline there too, so "State" read `Process exited with code 1 / INFO: connection rejected (403 For…` — the first
  two lines of the very text underneath it, under a heading that promised a state.
  **The references passed over that for as long as it shipped**, because `RobotAppStatus.previewCrashed` was a
  single `ModuleNotFoundError` line, and a one-line tail renders identically whether a surface prints it once or
  twice. It is several lines now, on purpose; do not shorten it back.
- **An error rendered _in place of_ a state has to expire; one in a slot of its own does not.** `lastError` is
  cleared only by a later successful command, which is correct for `AppDetailSheet`, where it is its own red row
  under a state that stays visible. The dock has one caption line, so the same value there hides the state — and a
  refused Restart on an app that goes on running would hide it, and the conversation turn with it, for the rest of
  the session. `RunningAppModel.expireActionFailure(at:)` retires it after `actionFailureWindow`, driven by the poll
  rather than by a `Timer`: the poll is the only clock this model already owns, and while backgrounded there is
  nothing on screen for a stale refusal to be stale on. It must not be shortened to "clear on the next tick" —
  the tick can land milliseconds after the tap, which is the original bug (a refusal shown nowhere) wearing a
  stopwatch.
- **A verdict may only be reached from a reading that arrived.** `refresh` swallows its own failure with `try?`, so
  after an unreachable poll `session.runningApp` still holds the previous status — and timing _that_ as if it were
  fresh is what let a Wi-Fi blip during a stop be reported as a wedged daemon, with `WedgedAppNotice` sending the
  reader to restart the robot's software over Bluetooth. `noteTransition` now runs only on a successful read; a
  verdict already reached stands, and silence concludes nothing new. Anything else this model infers from elapsed
  time owes the same check.

## One page per app

**`AppDetailSheet` is the only page about an app, and both surfaces open it** — a store row and the dock's expand
button. It used to be two views: this one for a catalogue entry (install, update, remove, start-on-wake-up) and
`RunningAppSheet` for the process (state, restart, stop, settings). The split was real but it was about _models_,
not about apps: the store card needs `AppStoreModel` and `AppInstallModel`, which the root did not own. The reader
got one object with two half-pages, and a crashed app had no way back — the running half offered Dismiss and no
Start.

- **The two models live in `ReachyTabShell`, not in `AppStoreScreen`.** The dock is mounted on the `TabView` and
  expands from every tab, so a model built inside the Apps tab would be a second copy: install something from the
  dock's page and the store would go on offering "Install". `AppStoreScreen` adopts them into its own `@State`, the
  way `YourReachiesScreen` adopts the root's.
- **Which sections appear is decided by the app's state, never by which surface asked.** `runningStatus` is read off
  the session and matched against this app by name (`matches(installed:)` covers a Space slug that differs from its
  Python entry point) — not through `model.isRunning(_:)`, which needs the installed list the dock's page may not
  have loaded yet. `loadInstalledIfNeeded` fills that in without the catalogue's Hugging Face round trip.
- **Start is gated on `isBusy`, not on "has a status".** A crashed app keeps its status so its output stays
  readable; hiding Start for it is what left the merged page with no way to try again, and the reference caught it.
- The toolbar button reads "Minimize" while the app holds the robot and "Done" otherwise. Closing the page never
  stops anything — only Stop does.

## An app's own settings

`AppSettingsScreen` is **the only `WKWebView` in this app**, and the only screen that is not built out of the design
system — because there is nothing to build it out of. The daemon carries no route for an app's configuration; it
reports a port (`extra["custom_app_url"]`) and the app serves its own page there. A native screen could only be
written against Conversation App 1.0's `/rpc` and would leave every other app with no settings whatsoever.
(`WebAuthenticationBrowser` is **not** a second web view — that is `ASWebAuthenticationSession`, out of process on
purpose so no Hugging Face credential passes through one of ours.)

- **`AppDetailSheet` decides whether to offer it, not the screen.** `RobotSession.appSettingsURL(for:)` answers nil
  without a declared port and without a LAN address; the page adds `state == .running` and `isReachable`, because
  the process serving the page is the process that crashes. There is no way to reach an app's settings while it is
  down, which is worst precisely when a bad setting is what took it down — say so rather than papering over it.
- **The row was invisible on every real robot for as long as it shipped, and not because of any of that.** The
  daemon builds a running-app status as `AppInfo(name=…, source_kind=INSTALLED)` with an empty `extra`, so
  `customAppPort` was nil for the one app anybody wanted it for. `RobotSession.describedFromInstalled` is the join
  that fixes it; the previews never caught it because their fixtures carry the metadata a real status does not.
  When something on this page is missing on hardware and present in a reference, suspect the status rather than the
  view.
- **`.ready` has no reference and cannot have one.** The web view renders nothing headless and is not even mounted
  under `reachyPreviewMode`, and unlike `CameraViewport.streaming` this phase grows no chrome to capture over it —
  so it is uncapturable in the sense `SceneViewport.ready` is. `.loading` and `.failed` are both covered.
- The Settings row's presence and absence are both already under cover, and by accident of the fixtures rather than
  by design: `previewConversation` declares 7860 so `Running app — conversation` shows the row, and
  `previewInstalled[0]` declares nothing so `Running app — running` shows the page without it. Keep it that way —
  a reference for the offered state alone cannot tell a conditional row from a permanent one. `previewInstalled[0]`
  carrying no metadata at all is not an oversight either: it is what a local app with no Hub card looks like, which
  is the one case `describedFromInstalled` still cannot describe.

## Maintenance, and the guard the robot does not have

`MaintenanceCard` carries the two `/cache/*` actions. Both delete something on the robot, both are irreversible from
here, and both sit behind a `confirmationDialog` — but only one of them needs a rule:

- **`reset-apps` is `shutil.rmtree("/venvs/apps_venv/")` and nothing else.** The daemon does not stop the running app
  first, so its interpreter is deleted underneath it. `MaintenanceModel.blockingApp(_:)` refuses while
  `runningApp.isBusy`, and the card **names the app to stop** rather than only greying the button out — a disabled
  control with no reason attached tells the reader nothing to act on. An unfamiliar process state counts as busy,
  the way `RobotAppStatus.State.isBusy` treats it: refusing to delete an environment that might be in use is the
  safe way to be wrong.
- The description goes **above** the button in both rows, which is how the robot's own dashboard reads it and the
  right way round for something irreversible: what it does before the thing that does it.
- **The dialog's keys deliberately do not echo the buttons'.** `Uninstall all apps` and `Uninstall all apps?` differ
  only in punctuation, and the catalogue derives one Swift symbol per key — that pair is a hard `xcstringstool`
  build error, not a warning. Hence `Remove every app?` and `Clear cached models?`.
- `canPerformMaintenance` gates the whole section, so a Lite robot and a relay session show nothing — the same shape
  as `canConfigureWiFi`. **The gate is only under cover because `PreviewRobotClient` conforms to
  `CacheMaintenanceClient`**, which is why that conformance exists: the gate asks "does this client speak that
  protocol", so without it the section is absent from every `Settings —` reference and `Settings — Lite robot`
  certifies nothing at all. `WiFiConfigClient`, `TeleopClient` and `DaemonLogClient` are on the preview client for
  exactly this reason; a new capability gate needs the same line adding or its screen quietly loses coverage.
  Which reference shows it is decided by scroll position, not by the gate: **`Settings — backend stopped` is the one**,
  because a stopped backend drops the audio section and pulls Maintenance up into the frame. `Settings — wireless
  robot` and `Settings — rename unavailable` pass the gate too and keep the section below the fold, so they did not
  move when it was added — which is the tell, not a bug. Content lives in the five standalone `Maintenance —`
  references.

`WiFiSettingsCard` gained "Forget all" on the same principle: one `/wifi/forget_all` rather than a loop over the
rows, because the per-network route answers 409 while another `nmcli` operation runs and a loop would race itself.
It appears only above one saved network — `Wi-Fi — own hotspot` (one) captures its absence, `Wi-Fi — on a network`
(three) and `Wi-Fi — join failed` (two) its presence. The count is over `known` as the daemon sends it, `Hotspot`
included, so a robot with one real network saved offers the button as well; that matches the rows, which list every
entry the same way and let the robot answer 400 for its own hotspot.

## Strings

Project rule 9 in the root `AGENTS.md` is the whole of it: `.reachy("…")` where SwiftUI takes a
`LocalizedStringResource`, `String(localized: .reachy("…"))` where the value has to stay a `String`. Two things this
target learned doing it:

- **A caption type, not `String(describing:)`.** `DaemonStateCaption` maps the generated
  `Components.Schemas.DaemonState` onto words; `RunningAppCaption` does the same for a process state. Both live here
  rather than in `ReachyKit`, because `ReachyKit` does not link `ReachyDesign` and must not start — a caller maps its
  own domain type onto a presentation value, never the reverse.
- **A sentence is one key.** Prose split across `+` for the sake of the 120-column rule became one literal with
  `// swiftlint:disable:next line_length` above it. Two half-keys cannot be reordered by a translator, and the
  fragments collide as generated symbols with whatever else ends in the same words.

## Previews and snapshots

`Previews/` sits here but is **excluded from the SwiftPM target** (`Package.swift`) and compiled only by the Xcode
targets in `Apps/`. `#Preview` is an external macro implemented by `libPreviewsMacros.dylib`, which ships inside
Xcode's platform SDKs and not in the pinned swift.org toolchain — a `#Preview` anywhere under a SwiftPM target breaks
`mise run build`, `mise run test` and CI with "plugin for module 'PreviewsMacros' not found".

Adding a screen (project rule 8) means: a preview per state in `Previews/<Screen>Previews.swift`, whatever seam and
`#if DEBUG` factory those states need, `mise run test:snapshots:record`, and `git add` on the PNGs.

- Preview files use `@testable import ReachyUI`; that is why `ENABLE_TESTABILITY` is set for the whole Xcode project.
- **Prefire reads previews off the filesystem; Xcode compiles the file list Tuist baked in.** A new file under
  `Previews/` is therefore picked up by the generator but not compiled until `mise run project` runs again — which is
  why the snapshot tasks depend on it. A bare `xcodebuild` skips that and fails with "cannot find … in scope".
  **Deleting** a file needs the same regeneration, and fails less legibly: `Build input file cannot be found`, which
  reads as a broken checkout rather than a stale file list.
- Anything a preview body references must be visible target-wide, because Prefire copies the body into a separate
  generated file. Shared wrappers live in `PreviewScene`; a `private` helper compiles locally and breaks the test.
- **A preview with no `traits:` is captured at full device size.** Prefire defaults the trait list to `.device`
  (`RawPreviewModel.isScreen`), and that device trait is what carries `horizontalSizeClass` — so it is what makes the
  iPad snapshot exercise the regular-width layout. Components opt out with `traits: .sizeThatFitsLayout`.
- **A preview must be final on its first frame.** Prefire captures synchronously and its `.snapshot(delay:)` modifier
  lives in a module this target cannot import without breaking the macOS build. Never rely on a `.task` completing —
  hand the view a model that is already in its end state (`AudioSettingsModel.preview()`, `RobotSession.preview()`).
- Model preview factories live **in the model's own file** under `#if DEBUG`, not in `Previews/`: they write members
  that are `private` to that file, and `@testable` does not reach `private`.
- Screens take their model through an initialiser with a default (`init(session:model:)`), so production call sites
  are unchanged and previews inject a frozen one.
- A defaulted argument whose value is `@MainActor` (`= SpikeModel()`, `= .preview()`) compiles in the SwiftPM targets
  but not in the `Apps/` ones, where it is evaluated nonisolated. Use `nil` and resolve it in the body.
- A model that already takes a factory closure (`OnboardingModel(session:)`, `BLEConsoleModel(link:)`) needs no new
  seam — hand it a `BLELink.preview(…)`, which sits on an inert `PreviewBLETransport` and is assigned its state
  directly. Building the link is not enough on its own: `OnboardingModel.session` is only set by `beginScan()`, which
  is the CoreBluetooth call a preview must not make, so the factory assigns it.
- A screen whose `.task` guards on `model == nil` needs no `reachyPreviewMode` check — injecting the model is what
  makes it inert. Add the guard only where the effect runs unconditionally (`WiFiSettingsCard`, `LogConsoleScreen`).
- **A tab whose content is loaded by a `.task` has no usable root capture, only a standalone one.** The shell builds
  all five tabs at once, and whichever loses that race is caught mid-layout. Settings comes out pure white on iPhone
  while rendering fine on iPad; Moves came out on iPad with its spinner but with the caption under it missing, and
  only a later run — one preview added elsewhere, timings shifted — produced the full frame. The tell is in the
  image: bare tab-bar glyphs instead of labels, or a state missing half of itself. Neither `SettingsScreen` nor
  `MovesTab` can be handed a settled model from `PreviewScene.root`, because the root builds the shell and the shell
  builds the tab — threading a seam through both for a preview is not worth it. So capture those screens standalone
  (`SettingsPreviews`, `MovesScreenPreviews`) and capture _placement_ from a state that needs no `.task` at all
  (`Root — relay moves tab`, which renders `MovesUnavailableView`). A blank or half-drawn reference is worse than a
  missing one: it reads as coverage and passes any change.
- Not covered, deliberately: `SceneViewport` in `.ready` — a bare `RealityView`, which renders nothing meaningful
  headless, so its overlay phases are what get snapshotted.
- **Not covered either, and measured rather than assumed: a `confirmationDialog`.** It presents in a context of its
  own that captures as nothing. Recorded twice for `RobotScreen`'s power-off dialog — once with a running app and
  once without, which change the sentence in it — the two references came out **byte-identical**, and identical to
  the same screen with no dialog at all. Three references for one image, none of which could tell the states apart.
  The rule that leaves behind: a dialog's _copy_ is model logic, and belongs in a model test
  (`RobotPowerOffModelTests` asserts which app gets named); the screen behind it is what a reference is for.
  `MaintenanceCard` never had one of these either, which now reads as the same finding made silently.
- **`CameraViewport` in `.streaming` used to be on that list and is not any more.** The reasoning was that the video
  is a Metal-backed `RTCMTLVideoView` and captures as an empty rectangle — true, and beside the point once the phase
  grew chrome of its own. The joystick and the return-to-neutral button draw over that empty rectangle perfectly
  well, and the button is _conditional_: a reference for the turned state alone cannot tell a conditional control
  from a permanent one, so `Camera — facing forward` exists to capture its **absence**. A black frame with controls
  on it is the intended image. The rule this leaves behind: a phase is uncapturable only while nothing but the
  unrenderable layer is in it.
- One `RobotSceneModel` per preview: `ReachyScene/AGENTS.md` requires exactly one live `RealityView` per model.
- **Navigation chrome does not stay inside a preview card.** SwiftUI hoists `.toolbar` and
  `.searchable` out of the storybook's scaled cards into the app's own bars, even though each
  preview brings its own `NavigationStack` — this is the limitation Prefire records as
  "NavigationView in Preview not supported for Playbook". The storybook hides its root bars to
  absorb it; `LogConsoleScreen`'s search field still floats over the catalogue, which is cosmetic
  and not worth contorting the screen for. Snapshots are unaffected — they capture the title _and_
  the toolbar items, so `RobotScreen`'s Settings gear and `MovesScreen`'s Refresh are covered.
  Only the storybook hoists.
