// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs (fork of ToshLLM)
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import Security
@testable import XeonLLM

/// Exercises the one-time migration from ToshLLM (dev.engel.toshllm) to XeonLLM
/// (dev.xeonllm.app) against a throwaway UserDefaults suite, a temp support
/// directory, and no Keychain access. The old data is never deleted.
final class IdentityMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var supportDir: URL!

    override func setUp() {
        super.setUp()
        suiteName = "xeonllm-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        supportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xeonllm-support-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: supportDir)
        super.tearDown()
    }

    /// Place an old-app data folder with a marker file inside the support dir.
    private func makeOldDataFolder(_ name: String = "ToshLLM") -> URL {
        let old = supportDir.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: old.appendingPathComponent("marker.txt").path,
                                       contents: Data("old".utf8))
        return old
    }

    private func makeNewDataFolder() throws -> URL {
        let new = supportDir.appendingPathComponent("XeonLLM", isDirectory: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        return new
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
    }

    private func readJSON(_ url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    func testCopiesSettingsAndDataFolder() throws {
        let old = makeOldDataFolder()
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["theme": "dark", "modelsDir": "/tmp/models"],
                              supportDir: supportDir, newDataFolder: "XeonLLM", keychain: false)
        XCTAssertEqual(defaults.string(forKey: "theme"), "dark")
        XCTAssertEqual(defaults.string(forKey: "modelsDir"), "/tmp/models")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: supportDir.appendingPathComponent("XeonLLM/marker.txt").path))
        // The old data is never deleted.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: old.appendingPathComponent("marker.txt").path))
        XCTAssertTrue(try XCTUnwrap(defaults.bool(forKey: IdentityMigration.markerKey) as Bool?))
    }

    func testDoesNotOverwriteAnExistingSetting() throws {
        _ = makeOldDataFolder()
        defaults.set("already-set", forKey: "theme")
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["theme": "from-old"],
                              supportDir: supportDir, newDataFolder: "XeonLLM", keychain: false)
        // A value the new app already has is never replaced by the old one.
        XCTAssertEqual(defaults.string(forKey: "theme"), "already-set")
    }

    func testMergesMissingItemsIntoAnExistingNewDataFolder() throws {
        let old = makeOldDataFolder()
        let oldSub = old.appendingPathComponent("dynamic-moe", isDirectory: true)
        try FileManager.default.createDirectory(at: oldSub, withIntermediateDirectories: true)
        try Data("old-other".utf8).write(to: oldSub.appendingPathComponent("other.json"))
        try Data("old-shared".utf8).write(to: old.appendingPathComponent("shared.txt"))

        let newFolder = try makeNewDataFolder()
        try Data("new".utf8).write(to: newFolder.appendingPathComponent("mine.txt"))
        try Data("new-shared".utf8).write(to: newFolder.appendingPathComponent("shared.txt"))
        let newSub = newFolder.appendingPathComponent("dynamic-moe", isDirectory: true)
        try FileManager.default.createDirectory(at: newSub, withIntermediateDirectories: true)
        try Data("new-child".utf8).write(to: newSub.appendingPathComponent("child.json"))

        IdentityMigration.run(defaults: defaults,
                              oldDomain: [:], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)

        // An item missing in the new folder is copied.
        XCTAssertEqual(try String(contentsOf: newFolder.appendingPathComponent("marker.txt"), encoding: .utf8), "old")
        // An existing file is never overwritten.
        XCTAssertEqual(try String(contentsOf: newFolder.appendingPathComponent("shared.txt"), encoding: .utf8), "new-shared")
        // Directories gain the missing children and keep their own.
        XCTAssertEqual(try String(contentsOf: newSub.appendingPathComponent("other.json"), encoding: .utf8), "old-other")
        XCTAssertEqual(try String(contentsOf: newSub.appendingPathComponent("child.json"), encoding: .utf8), "new-child")
        // The old folder is untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("shared.txt").path))
        XCTAssertTrue(defaults.bool(forKey: IdentityMigration.folderMarkerKey))
    }

    func testConversationsAndProjectsAreMergedByID() throws {
        let old = makeOldDataFolder()
        let newFolder = try makeNewDataFolder()
        try writeJSON([["id": "a", "title": "old-a"], ["id": "b", "title": "old-b"]],
                      to: old.appendingPathComponent("conversations.json"))
        try writeJSON([["id": "b", "title": "new-b"], ["id": "c", "title": "new-c"]],
                      to: newFolder.appendingPathComponent("conversations.json"))
        try writeJSON([["id": "p1", "name": "old-project"]],
                      to: old.appendingPathComponent("projects.json"))
        try writeJSON([["id": "p2", "name": "new-project"]],
                      to: newFolder.appendingPathComponent("projects.json"))

        IdentityMigration.run(defaults: defaults,
                              oldDomain: [:], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)

        let conversations = try readJSON(newFolder.appendingPathComponent("conversations.json"))
        XCTAssertEqual(conversations.compactMap { $0["id"] as? String }, ["b", "c", "a"])
        // The new copy wins on a conflicting id.
        XCTAssertEqual(conversations.first { $0["id"] as? String == "b" }?["title"] as? String, "new-b")

        let projects = try readJSON(newFolder.appendingPathComponent("projects.json"))
        XCTAssertEqual(projects.compactMap { $0["id"] as? String }, ["p2", "p1"])
    }

    func testASecondRunChangesNothing() throws {
        let old = makeOldDataFolder()
        let newFolder = try makeNewDataFolder()
        try writeJSON([["id": "a", "title": "old-a"]],
                      to: old.appendingPathComponent("conversations.json"))
        try writeJSON([["id": "b", "title": "new-b"]],
                      to: newFolder.appendingPathComponent("conversations.json"))

        IdentityMigration.run(defaults: defaults,
                              oldDomain: [:], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)
        let first = try Data(contentsOf: newFolder.appendingPathComponent("conversations.json"))
        let firstItems = try FileManager.default.contentsOfDirectory(atPath: newFolder.path).sorted()

        IdentityMigration.run(defaults: defaults,
                              oldDomain: [:], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)
        XCTAssertEqual(try Data(contentsOf: newFolder.appendingPathComponent("conversations.json")), first)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: newFolder.path).sorted(), firstItems)
        // Nothing was removed from the old folder either.
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("conversations.json").path))
    }

    func testFolderMergeRunsOnceForBeta5MigratedUsers() throws {
        let old = makeOldDataFolder()
        let newFolder = try makeNewDataFolder()
        try Data("new".utf8).write(to: newFolder.appendingPathComponent("mine.txt"))
        // beta.5 already set the first marker but skipped the folder copy.
        defaults.set(true, forKey: IdentityMigration.markerKey)

        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["second": "2"], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: newFolder.appendingPathComponent("marker.txt").path))
        XCTAssertNil(defaults.string(forKey: "second"))
        XCTAssertTrue(defaults.bool(forKey: IdentityMigration.folderMarkerKey))
    }

    func testNeverDeletesTheOldDataFolder() throws {
        let old = makeOldDataFolder()
        IdentityMigration.run(defaults: defaults,
                              oldDomain: [:], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: old.appendingPathComponent("marker.txt").path))
    }

    func testASecondRunCopiesNothing() throws {
        _ = makeOldDataFolder()
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["first": "1"], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)
        XCTAssertEqual(defaults.string(forKey: "first"), "1")
        // A second run with different old data is a no-op: the marker guards it.
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["second": "2"], supportDir: supportDir,
                              newDataFolder: "XeonLLM", keychain: false)
        XCTAssertEqual(defaults.string(forKey: "second"), nil)
        XCTAssertEqual(defaults.string(forKey: "first"), "1")
    }

    func testSkipsSystemStateKeys() throws {
        _ = makeOldDataFolder()
        // NS* keys hold window frames; Apple* keys are system state. Neither travels.
        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["NSWindowFrame": "{0,0,100,100}",
                                          "AppleLocaleUserDictionary": ["en"],
                                          "aRealSetting": "kept"],
                              supportDir: supportDir, newDataFolder: "XeonLLM", keychain: false)
        XCTAssertNil(defaults.object(forKey: "NSWindowFrame"))
        XCTAssertNil(defaults.object(forKey: "AppleLocaleUserDictionary"))
        XCTAssertEqual(defaults.string(forKey: "aRealSetting"), "kept")
    }

    /// The migration still names ToshLLM's own data: that is the one place the old name stays.
    func testTheMigrationStillNamesToshLLMsOwnData() {
        XCTAssertEqual(IdentityMigration.oldIdentifier, "dev.engel.toshllm")
        XCTAssertEqual(IdentityMigration.oldDataFolder, "ToshLLM")
        XCTAssertEqual(IdentityMigration.markerKey, "migratedFromToshLLM")
        XCTAssertEqual(IdentityMigration.folderMarkerKey, "migratedFromToshLLMFolderV2")
    }

    /// A beta 8 profile is already under XeonLLM's name: the upgrade has no old folder to merge, so
    /// the new folder is left exactly as it is. The old domain's settings still travel once: they
    /// are the one thing the marker copies, folder or no folder.
    func testABeta8ProfileKeepsItsOwnFolder() throws {
        let newFolder = try makeNewDataFolder()
        try writeJSON([["id": "a", "title": "beta-8"]],
                      to: newFolder.appendingPathComponent("conversations.json"))
        let before = try Data(contentsOf: newFolder.appendingPathComponent("conversations.json"))

        IdentityMigration.run(defaults: defaults,
                              oldDomain: ["theme": "dark"],
                              supportDir: supportDir, newDataFolder: "XeonLLM", keychain: false)

        XCTAssertEqual(try Data(contentsOf: newFolder.appendingPathComponent("conversations.json")), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: newFolder.path).sorted(),
                       ["conversations.json"])
        // No ToshLLM folder is created, so nothing was merged into this profile.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: supportDir.appendingPathComponent("ToshLLM").path))
        XCTAssertEqual(defaults.string(forKey: "theme"), "dark")
        XCTAssertTrue(try XCTUnwrap(defaults.bool(forKey: IdentityMigration.markerKey) as Bool?))
    }

    func testKeychainItemsAreCopiedNotMovedOrOverwritten() throws {
        let old = "xeonllm-test-old-\(UUID().uuidString)", new = "xeonllm-test-new-\(UUID().uuidString)"
        func add(_ service: String, _ account: String, _ value: String) {
            let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                       kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8)]
            XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        }
        func read(_ service: String, _ account: String) -> String? {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
            var r: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
            return String(data: d, encoding: .utf8)
        }
        defer {
            for service in [old, new] {
                SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
            }
        }
        add(old, "a", "old-a"); add(old, "b", "old-b"); add(new, "b", "new-b")
        IdentityMigration.copyKeychainItems(oldService: old, newService: new)
        XCTAssertEqual(read(new, "a"), "old-a")
        XCTAssertEqual(read(new, "b"), "new-b")
        XCTAssertEqual(read(old, "a"), "old-a")
    }
}
