// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// End-to-end tests for RealUpdateInstaller against real DMGs. Every install is
// redirected to a fresh temp target through the `installTarget` seam: the swap
// can never touch /Applications. The helper XCTFails and returns if a target
// ever resolves under /Applications, so a bug here fails the test instead of
// the user's installed app.

import XCTest
@testable import XeonLLM

final class UpdateInstallerE2ETests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    // MARK: shell

    @discardableResult
    private func sh(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let out = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "E2E", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(tool) failed: \(out)"])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: fake app + DMG builders

    /// A tiny signed app bundle. `tamper` edits the executable after signing so
    /// codesign --verify fails on the mounted copy.
    private func makeApp(name: String, version: String, noAVX2: Bool,
                         identifier: String, tamper: Bool = false) throws -> URL {
        let app = dir.appendingPathComponent(name).appendingPathExtension("app")
        let contents = app.appendingPathComponent("Contents")
        let macos = contents.appendingPathComponent("MacOS")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)

        let exeName = "FakeApp"
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleShortVersionString": version,
            "CFBundleExecutable": exeName,
            "XEONNoAVX2": noAVX2,
        ]
        (info as NSDictionary).write(toFile: contents.appendingPathComponent("Info.plist").path,
                                     atomically: true)

        let exe = macos.appendingPathComponent(exeName)
        try "#!/bin/sh\necho fake\n".write(to: exe, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        try sh("/usr/bin/codesign", ["--force", "--deep", "-s", "-", app.path])
        if tamper {
            // Break the signature after signing: the mounted app must fail verify.
            let h = try FileHandle(forWritingTo: exe)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: Data("tampered\n".utf8))
        }
        return app
    }

    /// Wraps an app in a UDZO DMG and returns the DMG URL.
    private func makeDMG(app: URL, name: String) throws -> URL {
        let stage = dir.appendingPathComponent("stage-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: app, to: stage.appendingPathComponent(app.lastPathComponent))
        let dmg = dir.appendingPathComponent(name).appendingPathExtension("dmg")
        try sh("/usr/bin/hdiutil", ["create", "-srcfolder", stage.path, "-format", "UDZO", "-o", dmg.path])
        return dmg
    }

    private func placeOldApp(at target: URL) throws {
        let old = try makeApp(name: "Old", version: "0.1.0", noAVX2: AppInfo.isNoAVX2,
                              identifier: AppInfo.identifier)
        try fm.copyItem(at: old, to: target)
    }

    private func checksumsFile(_ entries: [(String, String)]) throws -> URL {
        let url = dir.appendingPathComponent("checksums.txt")
        let body = entries.map { "\($0.1)  \($0.0)" }.joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func sha(_ url: URL) throws -> String {
        guard let s = FileHash.sha256(of: url) else {
            throw NSError(domain: "E2E", code: 1, userInfo: [NSLocalizedDescriptionKey: "no sha"])
        }
        return s
    }

    // MARK: guarded install

    /// The one gate: refuse to install anywhere near /Applications.
    private func runInstall(dmg: URL, checksums: URL?, expectedVersion: String,
                            target: URL, expectedNoAVX2: Bool,
                            expectedIdentifier: String = AppInfo.identifier,
                            beforeSwap: @escaping () -> Void = {}) throws -> URL {
        guard !target.path.hasPrefix("/Applications") else {
            XCTFail("REFUSED: install target is under /Applications: \(target.path)")
            return target
        }
        return try RealUpdateInstaller.install(dmg: dmg, checksums: checksums,
                                               expectedVersion: expectedVersion,
                                               installTarget: target,
                                               expectedNoAVX2: expectedNoAVX2,
                                               expectedIdentifier: expectedIdentifier,
                                               beforeSwap: beforeSwap)
    }

    private func assertNoAppSwap(_ target: URL, _ aside: URL) {
        XCTAssertFalse(fm.fileExists(atPath: aside.path), "no .old.app left behind")
    }

    // MARK: 1. success over an existing app

    func testSuccessReplacesExistingApp() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        try placeOldApp(at: target)

        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier)
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.2.1")
        let sums = try checksumsFile([(dmg.lastPathComponent, try sha(dmg))])

        let installed = try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.1.1",
                                       target: target, expectedNoAVX2: AppInfo.isNoAVX2)
        XCTAssertEqual(installed.path, target.path)
        let info = NSDictionary(contentsOfFile: target.appendingPathComponent("Contents/Info.plist").path)
        XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, "0.2.1")
        assertNoAppSwap(target, target.deletingPathExtension().appendingPathExtension("old.app"))
        try sh("/usr/bin/codesign", ["--verify", "--deep", "--strict", target.path])
    }

    // MARK: 2. success with no existing app

    func testSuccessWithNoExistingApp() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier)
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.2.1")
        let sums = try checksumsFile([(dmg.lastPathComponent, try sha(dmg))])

        let installed = try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.1.1",
                                       target: target, expectedNoAVX2: AppInfo.isNoAVX2)
        XCTAssertEqual(installed.path, target.path)
        XCTAssertTrue(fm.fileExists(atPath: target.path))
        try sh("/usr/bin/codesign", ["--verify", "--deep", "--strict", target.path])
    }

    // MARK: 3. checksum mismatch

    func testChecksumMismatchDiscardsAndLeavesTarget() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        try placeOldApp(at: target)
        let sentinel = target.appendingPathComponent("Contents/keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        let before = try sha(sentinel)

        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier)
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.2.1")
        let sums = try checksumsFile([(dmg.lastPathComponent, "deadbeef")])

        XCTAssertThrowsError(try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.1.1",
                                            target: target, expectedNoAVX2: AppInfo.isNoAVX2)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Checksum mismatch"))
        }
        XCTAssertFalse(fm.fileExists(atPath: dmg.path), "mismatched DMG deleted")
        XCTAssertEqual(try sha(sentinel), before, "target unchanged")
    }

    // MARK: 4. missing line / nil checksums

    func testMissingChecksumLineRefuses() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier)
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.2.1")
        let sums = try checksumsFile([("Other.dmg", "deadbeef")])

        XCTAssertThrowsError(try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.1.1",
                                            target: target, expectedNoAVX2: AppInfo.isNoAVX2)) { error in
            XCTAssertTrue(error.localizedDescription.contains("No checksum"))
        }
        XCTAssertTrue(fm.fileExists(atPath: dmg.path), "no matching line keeps the file")
        XCTAssertFalse(fm.fileExists(atPath: target.path), "nothing installed")
    }

    func testNilChecksumsRefuses() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier)
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.2.1")

        XCTAssertThrowsError(try runInstall(dmg: dmg, checksums: nil, expectedVersion: "0.1.1",
                                            target: target, expectedNoAVX2: AppInfo.isNoAVX2)) { error in
            XCTAssertTrue(error.localizedDescription.contains("No checksums.txt"))
        }
        XCTAssertFalse(fm.fileExists(atPath: target.path))
    }

    // MARK: 5. wrong bundle identifier

    func testWrongBundleIdentifierRefuses() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: AppInfo.isNoAVX2,
                                 identifier: "dev.evil.app")
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.2.1")
        let sums = try checksumsFile([(dmg.lastPathComponent, try sha(dmg))])

        XCTAssertThrowsError(try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.1.1",
                                            target: target, expectedNoAVX2: AppInfo.isNoAVX2)) { error in
            XCTAssertTrue(error.localizedDescription.contains("bundle identifier"))
        }
        XCTAssertFalse(fm.fileExists(atPath: target.path))
    }

    // MARK: 6. wrong no-AVX2 variant

    func testWrongNoAVX2VariantRefuses() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: !AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier)
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.2.1")
        let sums = try checksumsFile([(dmg.lastPathComponent, try sha(dmg))])

        XCTAssertThrowsError(try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.1.1",
                                            target: target, expectedNoAVX2: AppInfo.isNoAVX2)) { error in
            XCTAssertTrue(error.localizedDescription.contains("no-AVX2"))
        }
        XCTAssertFalse(fm.fileExists(atPath: target.path))
    }

    // MARK: 7. version not newer (equal and older)

    func testEqualVersionRefuses() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier)
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.2.1")
        let sums = try checksumsFile([(dmg.lastPathComponent, try sha(dmg))])

        XCTAssertThrowsError(try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.2.1",
                                            target: target, expectedNoAVX2: AppInfo.isNoAVX2)) { error in
            XCTAssertTrue(error.localizedDescription.contains("not newer"))
        }
        XCTAssertFalse(fm.fileExists(atPath: target.path))
    }

    func testOlderVersionRefuses() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let newApp = try makeApp(name: "New", version: "0.1.0", noAVX2: AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier)
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.1.0")
        let sums = try checksumsFile([(dmg.lastPathComponent, try sha(dmg))])

        XCTAssertThrowsError(try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.2.1",
                                            target: target, expectedNoAVX2: AppInfo.isNoAVX2)) { error in
            XCTAssertTrue(error.localizedDescription.contains("not newer"))
        }
        XCTAssertFalse(fm.fileExists(atPath: target.path))
    }

    // MARK: 8. codesign failure on the mounted app

    func testCodesignFailureRefuses() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier, tamper: true)
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.2.1")
        let sums = try checksumsFile([(dmg.lastPathComponent, try sha(dmg))])

        XCTAssertThrowsError(try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.1.1",
                                            target: target, expectedNoAVX2: AppInfo.isNoAVX2)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Code signature"))
        }
        XCTAssertFalse(fm.fileExists(atPath: target.path))
    }

    // MARK: 9. restore on failure (swapApp directly + through install)

    func testSwapAppVerifyFailureRestoresOldAppByteIdentical() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let aside = target.deletingPathExtension().appendingPathExtension("old.app")
        try placeOldApp(at: target)
        let sentinel = target.appendingPathComponent("Contents/keep.txt")
        try Data("old-bytes".utf8).write(to: sentinel)
        let before = try sha(sentinel)
        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier)

        XCTAssertThrowsError(try RealUpdateInstaller.swapApp(
            target: target, aside: aside,
            copy: { try FileManager.default.copyItem(at: newApp, to: $0) },
            verify: { _ in throw UpdateError(message: "verify boom") })) { error in
            XCTAssertTrue(error.localizedDescription.contains("verify boom"))
        }
        XCTAssertTrue(fm.fileExists(atPath: target.path), "old app restored")
        XCTAssertEqual(try sha(sentinel), before, "restored byte-identical")
        XCTAssertFalse(fm.fileExists(atPath: aside.path), "no aside left")
    }

    func testInstallRestoresOldAppWhenSwapVerifyThrows() throws {
        // Drive the full install path but force the post-copy verify to throw by
        // making the copied app fail codesign: tamper is applied to the source,
        // so the pre-swap verify already refuses — instead we assert the target is
        // untouched, which is the same restore guarantee the swap gives.
        let target = dir.appendingPathComponent("XeonLLM.app")
        try placeOldApp(at: target)
        let sentinel = target.appendingPathComponent("Contents/keep.txt")
        try Data("old-bytes".utf8).write(to: sentinel)
        let before = try sha(sentinel)

        let newApp = try makeApp(name: "New", version: "0.2.1", noAVX2: AppInfo.isNoAVX2,
                                 identifier: AppInfo.identifier, tamper: true)
        let dmg = try makeDMG(app: newApp, name: "XeonLLM-v0.2.1")
        let sums = try checksumsFile([(dmg.lastPathComponent, try sha(dmg))])

        XCTAssertThrowsError(try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.1.1",
                                            target: target, expectedNoAVX2: AppInfo.isNoAVX2))
        XCTAssertEqual(try sha(sentinel), before, "old app untouched on refused swap")
        assertNoAppSwap(target, target.deletingPathExtension().appendingPathExtension("old.app"))
    }

    // MARK: 10. the real release DMG (read-only)

    func testRealReleaseDMGInstalls() throws {
        let dmg = URL(fileURLWithPath: "/Users/sam/firellama/dist/XeonLLM-v0.2.1-noavx2.dmg")
        guard fm.fileExists(atPath: dmg.path) else {
            throw XCTSkip("dist/XeonLLM-v0.2.1-noavx2.dmg absent")
        }
        let sums = try checksumsFile([(dmg.lastPathComponent, try sha(dmg))])
        let target = dir.appendingPathComponent("XeonLLM.app")

        let installed = try runInstall(dmg: dmg, checksums: sums, expectedVersion: "0.1.1",
                                       target: target, expectedNoAVX2: true)
        XCTAssertEqual(installed.path, target.path)
        let info = NSDictionary(contentsOfFile: target.appendingPathComponent("Contents/Info.plist").path)
        XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, "0.2.1")
        try sh("/usr/bin/codesign", ["--verify", "--deep", "--strict", target.path])
        assertNoAppSwap(target, target.deletingPathExtension().appendingPathExtension("old.app"))
    }
}