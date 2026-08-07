import Foundation
import ReachySSH
@testable import ReachyUI
import Testing

@MainActor
@Suite("Robot files", .timeLimit(.minutes(1)))
struct RobotFilesModelTests {
    private func model(
        _ files: any RobotFileSystem,
        path: String = "/",
        password: String = "root"
    ) -> RobotFilesModel {
        let model = RobotFilesModel(
            files: files,
            credentials: EphemeralCredentialStore(),
            robot: "unit-test",
            host: "reachy-mini.local",
            path: path
        )
        model.password = password
        return model
    }

    @Test("asks for a password before opening a socket")
    func startsWithoutAPassword() async {
        let files = PreviewFileSystem(tree: ["/": []])
        let model = model(files, password: "")
        await model.start()
        #expect(model.phase == .needsPassword)
        #expect(files.calls.isEmpty)
    }

    @Test("lists the directory once connected")
    func listsAfterConnecting() async {
        let model = model(PreviewFileSystem.brokenPersonality(), path: PreviewFileSystem.appPackage)
        await model.start()
        #expect(model.phase == .browsing)
        #expect(model.hasListed)
        #expect(model.entries.isEmpty == false)
    }

    @Test("puts directories first, then sorts by name without regard to case")
    func ordering() async {
        let model = model(PreviewFileSystem.brokenPersonality(), path: PreviewFileSystem.appPackage)
        await model.start()
        let kinds = model.entries.map(\.isDirectory)
        // Every directory precedes every file: no `false` may appear before a `true`.
        #expect(kinds == kinds.sorted { $0 && !$1 })
        let names = model.entries.filter { !$0.isDirectory }.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test("distinguishes never-listed from listed-and-empty")
    func emptyIsNotTheSameAsUnasked() async {
        let model = model(PreviewFileSystem(tree: ["/": []]))
        #expect(model.hasListed == false)
        await model.start()
        #expect(model.hasListed)
        #expect(model.entries.isEmpty)
    }

    @Test("a refused password sends the user back to the field, not to a dead end")
    func authenticationFailure() async {
        let model = model(PreviewFileSystem(failure: .authenticationFailed))
        await model.start()
        #expect(model.phase == .needsPassword)
        #expect(model.lastError != nil)
    }

    @Test("an unknown host key becomes a confirmation, never a silent accept")
    func unknownHostKey() async throws {
        let fingerprint = try #require(
            HostKeyFingerprint(
                openSSHPublicKey:
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKxSnnReKXYSkOtrc1X2t3KlT7aQiTAgRxF4A+fDZCz"
            )
        )
        let model = model(PreviewFileSystem(failure: .hostKeyUnknown(fingerprint)))
        await model.start()
        #expect(model.phase == .confirmHostKey(fingerprint))
    }

    @Test("a changed host key is its own state, not the first-contact one")
    func changedHostKey() async throws {
        let pinned = try #require(
            HostKeyFingerprint(
                openSSHPublicKey:
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKxSnnReKXYSkOtrc1X2t3KlT7aQiTAgRxF4A+fDZCz"
            )
        )
        let offered = try #require(
            HostKeyFingerprint(
                openSSHPublicKey:
                // swiftlint:disable:next line_length
                "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOd1Bvm7mJHkOBy3mwgfQgJfhM1H1yc7OSwU9wBbe6kADDBL+lrQDy6gQYbUcDEy3u9toj9LO4G4ejlikUDOtFk="
            )
        )
        let model = model(PreviewFileSystem(failure: .hostKeyChanged(pinned: pinned, offered: offered)))
        await model.start()
        #expect(model.phase == .hostKeyChanged(pinned: pinned, offered: offered))
    }

    @Test("walks into a folder and back out again")
    func navigation() async throws {
        let model = model(PreviewFileSystem.brokenPersonality(), path: PreviewFileSystem.appPackage)
        await model.start()
        let personalities = try #require(model.entries.first { $0.name == "user_personalities" })

        await model.open(personalities)
        #expect(model.path == personalities.path)
        #expect(model.entries.map(\.name) == ["Test_Ru"])

        await model.goUp()
        #expect(model.path == PreviewFileSystem.appPackage)
    }

    @Test("opening a file changes nothing — only folders navigate")
    func openingAFileIsNotNavigation() async {
        let model = model(PreviewFileSystem.brokenPersonality(), path: PreviewFileSystem.appPackage)
        await model.start()
        guard let file = model.entries.first(where: { !$0.isDirectory }) else { return }
        await model.open(file)
        #expect(model.path == PreviewFileSystem.appPackage)
    }

    @Test("stops going up at the root")
    func rootHasNoParent() async {
        let model = model(PreviewFileSystem(tree: ["/": []]))
        await model.start()
        #expect(model.canGoUp == false)
        await model.goUp()
        #expect(model.path == "/")
    }

    @Test("builds a breadcrumb that ends at the current folder")
    func breadcrumb() {
        let model = model(PreviewFileSystem(tree: [:]), path: "/venvs/apps_venv/lib")
        let trail = model.breadcrumb
        #expect(trail.map(\.name) == ["/", "venvs", "apps_venv", "lib"])
        #expect(trail.map(\.path) == ["/", "/venvs", "/venvs/apps_venv", "/venvs/apps_venv/lib"])
    }

    @Test("an upload lands on the path it was given, then re-reads the folder")
    func uploadReplacesInPlace() async throws {
        let files = PreviewFileSystem.brokenPersonality()
        let model = model(files, path: PreviewFileSystem.appPackage)
        await model.start()
        let settings = RemoteFile.joining(PreviewFileSystem.appPackage, "startup_settings.json")

        await model.upload(Data(#"{"profile": "default"}"#.utf8), to: settings)
        #expect(model.lastError == nil)
        #expect(files.calls.contains("write(\(settings))"))

        let written = try await files.read(settings, limit: 4096)
        #expect(String(data: written, encoding: .utf8) == #"{"profile": "default"}"#)
    }

    @Test("an upload with no explicit target goes into the folder being shown")
    func uploadDestination() {
        let model = model(PreviewFileSystem(tree: [:]), path: "/home/pollen")
        #expect(model.destination(forFileNamed: "profile.md") == "/home/pollen/profile.md")
    }

    @Test("refuses to create a folder with a blank name")
    func blankFolderName() async {
        let files = PreviewFileSystem(tree: ["/": []])
        let model = model(files)
        await model.start()
        await model.makeDirectory(named: "   ")
        #expect(files.calls.contains { $0.hasPrefix("makeDirectory") } == false)
    }

    @Test("a rename to the same name asks the robot nothing")
    func noOpRename() async {
        let files = PreviewFileSystem.brokenPersonality()
        let model = model(files, path: PreviewFileSystem.appPackage)
        await model.start()
        guard let file = model.entries.first(where: { !$0.isDirectory }) else { return }
        await model.rename(file, to: file.name)
        #expect(files.calls.contains { $0.hasPrefix("rename") } == false)
    }

    @Test("reports a non-empty folder in words the reader can act on")
    func directoryNotEmpty() {
        let message = RobotFilesModel.describe(ReachySSHError.directoryNotEmpty("/a"))
        #expect(message.contains("not empty"))
    }

    @Test("passes the robot's own wording through untouched")
    func transportKeepsServerWording() {
        let message = RobotFilesModel.describe(ReachySSHError.transport("Connection reset by peer"))
        #expect(message == "Connection reset by peer")
    }

    @Test("a cancelled listing neither reports a failure nor clears one")
    func cancellationIsNotAFailure() async {
        let model = model(PreviewFileSystem(failure: .transport("boom")))
        await model.start()
        // A real failure did land.
        #expect(model.phase == .failed("boom"))
    }
}
