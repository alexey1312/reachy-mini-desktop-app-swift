import Foundation
@testable import ReachySSH
import Testing

@Suite("Remote file mapping")
struct RemoteFileTests {
    @Test("reads the kind out of the S_IFMT bits, not out of longname")
    func kindFromMode() {
        #expect(RemoteFile.kind(mode: 0o040755, longname: "-rw-r--r-- 1 pollen") == .directory)
        #expect(RemoteFile.kind(mode: 0o100644, longname: "drwxr-xr-x 2 pollen") == .file)
        #expect(RemoteFile.kind(mode: 0o120777, longname: "-rw-r--r-- 1 pollen") == .symlink)
        #expect(RemoteFile.kind(mode: 0o140755, longname: "srwxr-xr-x 1 pollen") == .other)
    }

    /// A server sending bare permissions used to make every entry `.other`, so
    /// `isDirectory` was false everywhere and nothing could be opened.
    @Test("falls back to longname when the mode carries permissions but no type bits")
    func kindFromModeWithoutTypeBits() {
        #expect(RemoteFile.kind(mode: 0o755, longname: "drwxr-xr-x 2 pollen") == .directory)
        #expect(RemoteFile.kind(mode: 0o644, longname: "-rw-r--r-- 1 pollen") == .file)
        #expect(RemoteFile.kind(mode: 0o777, longname: "lrwxrwxrwx 1 pollen") == .symlink)
        #expect(RemoteFile.kind(mode: 0, longname: "drwxr-xr-x 2 pollen") == .directory)
    }

    @Test("falls back to the ls -l character when the server sent no permissions")
    func kindFromLongname() {
        #expect(RemoteFile.kind(mode: nil, longname: "drwxr-xr-x 2 pollen pollen 4096 …") == .directory)
        #expect(RemoteFile.kind(mode: nil, longname: "-rw-r--r-- 1 pollen pollen 148 …") == .file)
        #expect(RemoteFile.kind(mode: nil, longname: "lrwxrwxrwx 1 pollen pollen 11 …") == .symlink)
        #expect(RemoteFile.kind(mode: nil, longname: "") == .other)
    }

    @Test("renders permissions from the mode")
    func permissionsText() {
        #expect(RemoteFile.permissionsText(mode: 0o040755, kind: .directory) == "drwxr-xr-x")
        #expect(RemoteFile.permissionsText(mode: 0o100644, kind: .file) == "-rw-r--r--")
        #expect(RemoteFile.permissionsText(mode: 0o100600, kind: .file) == "-rw-------")
        #expect(RemoteFile.permissionsText(mode: 0o120777, kind: .symlink) == "lrwxrwxrwx")
        #expect(RemoteFile.permissionsText(mode: nil, kind: .file) == nil)
    }

    @Test("joins without doubling the separator at the root")
    func joining() {
        #expect(RemoteFile.joining("/", "venvs") == "/venvs")
        #expect(RemoteFile.joining("/venvs", "apps_venv") == "/venvs/apps_venv")
        #expect(RemoteFile.joining("/venvs/", "apps_venv") == "/venvs/apps_venv")
    }

    @Test("walks up to the root and then stops")
    func parent() {
        #expect(RemoteFile.parent(of: "/venvs/apps_venv/lib") == "/venvs/apps_venv")
        #expect(RemoteFile.parent(of: "/venvs/apps_venv/lib/") == "/venvs/apps_venv")
        #expect(RemoteFile.parent(of: "/venvs") == "/")
        #expect(RemoteFile.parent(of: "/") == nil)
    }

    @Test("identifies an entry by its path, so two names in one listing never collide")
    func identity() {
        let a = RemoteFile(name: "profile.md", path: "/a/profile.md", kind: .file)
        let b = RemoteFile(name: "profile.md", path: "/b/profile.md", kind: .file)
        #expect(a.id != b.id)
    }
}

@Suite("SSH error classification")
struct ReachySSHErrorTests {
    @Test("only a dropped connection is worth retrying with the same inputs")
    func retryable() {
        #expect(ReachySSHError.notConnected.isRetryable)
        #expect(ReachySSHError.transport("channel closed").isRetryable)
        #expect(ReachySSHError.authenticationFailed.isRetryable == false)
        #expect(ReachySSHError.pathNotFound("/nope").isRetryable == false)
        #expect(ReachySSHError.directoryNotEmpty("/a").isRetryable == false)
        #expect(ReachySSHError.fileTooLarge(bytes: 1, limit: 0).isRetryable == false)
    }
}

@Suite("Preview file system")
struct PreviewFileSystemTests {
    @Test("serves the broken-personality fixture the incident produced")
    func brokenPersonality() async throws {
        let fs = PreviewFileSystem.brokenPersonality()
        try await fs.connect(.init(host: "robot", username: "pollen", password: "root"))
        let personalities = try await fs.list(
            RemoteFile.joining(PreviewFileSystem.appPackage, "user_personalities")
        )
        #expect(personalities.map(\.name) == ["Test_Ru"])

        let profile = try await fs.list(personalities[0].path)
        // The whole point of the fixture: old-format files and no profile.md.
        #expect(profile.map(\.name).contains("profile.md") == false)
        #expect(profile.map(\.name) == ["greeting.txt", "instructions.txt", "tools.txt", "voice.txt"])
    }

    @Test("records what was asked, in order")
    func recordsCalls() async throws {
        let fs = PreviewFileSystem(tree: ["/": []])
        try await fs.connect(.init(host: "robot", username: "pollen", password: "root"))
        _ = try await fs.list("/")
        #expect(fs.calls == ["connect", "list(/)"])
        #expect(fs.isConnected)
    }

    @Test("fails every call when built with a failure, so a preview can sit in one")
    func injectedFailure() async {
        let fs = PreviewFileSystem(failure: .authenticationFailed)
        await #expect(throws: ReachySSHError.authenticationFailed) {
            try await fs.connect(.init(host: "robot", username: "pollen", password: "wrong"))
        }
    }

    @Test("refuses a read over the limit rather than returning it")
    func readLimit() async throws {
        let fs = PreviewFileSystem(contents: ["/big": Data(count: 4096)])
        await #expect(throws: ReachySSHError.fileTooLarge(bytes: 4096, limit: 1024)) {
            try await fs.read("/big", limit: 1024)
        }
        #expect(try await fs.read("/big", limit: 8192).count == 4096)
    }
}
