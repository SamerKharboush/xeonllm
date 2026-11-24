// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// A release feed whose responses the test controls, so the scheduler, channel
/// selection and error paths can be exercised without GitHub.
final class StubUpdateFeed: UpdateFeed {
    var latest: Result<ReleaseInfo, Error> = .success(ReleaseInfo(version: "0.0.0", releaseURL: nil, dmgURL: nil, checksumsURL: nil, rateLimited: false))
    var notes: Result<[(String, String, Date)], Error> = .success([])
    var latestCalls = 0

    func latestRelease() async throws -> ReleaseInfo {
        latestCalls += 1
        return try latest.get()
    }

    func releaseNotes() async throws -> [(String, String, Date)] {
        try notes.get()
    }
}

/// A clock whose time and last-check the test sets.
final class StubClock: UpdateClock {
    var currentTime: Date
    var last: Date?
    init(now: Date, last: Date? = nil) { self.currentTime = now; self.last = last }

    func now() -> Date { currentTime }
    func lastSuccessfulCheck() -> Date? { last }
    func recordSuccessfulCheck(_ date: Date) { last = date }
}

/// An installer that records the swap and can fail on demand; never touches the
/// filesystem or the real engine.
final class StubInstaller: UpdateInstalling {
    var installed: URL?
    var installError: Error?
    var relaunched: URL?
    var stopCalls = 0
    var installCalls = 0

    func install(dmg: URL, checksums: URL?, expectedVersion: String) async throws -> URL {
        installCalls += 1
        if let error = installError { throw error }
        installed = dmg
        return dmg
    }

    func relaunch(_ url: URL) { relaunched = url }
    @MainActor func stopOwnServer() { stopCalls += 1 }
}

@MainActor
final class UpdateCheckerScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let yesterday = Date(timeIntervalSince1970: 2_000_000_000 - 24 * 3600)
    private let dayAgo = Date(timeIntervalSince1970: 2_000_000_000 - 25 * 3600)
    private let hourAgo = Date(timeIntervalSince1970: 2_000_000_000 - 3600)

    private func checker(_ clock: StubClock, autoCheck: @escaping () -> Bool = { true },
                         feed: StubUpdateFeed? = nil) -> (UpdateChecker, StubUpdateFeed) {
        let f = feed ?? StubUpdateFeed()
        let c = UpdateChecker(feed: f, clock: clock, installer: StubInstaller(), autoCheck: autoCheck)
        return (c, f)
    }

    func testNeverCheckedIsDue() {
        let (c, _) = checker(StubClock(now: now, last: nil))
        XCTAssertTrue(c.isDue(now: now), "no successful check yet is due")
    }

    func testDueAfter24h() {
        let (c, _) = checker(StubClock(now: now, last: dayAgo))
        XCTAssertTrue(c.isDue(now: now), "a check over 24 h old is due")
    }

    func testNotDueBefore24h() {
        let (c, _) = checker(StubClock(now: now, last: hourAgo))
        XCTAssertFalse(c.isDue(now: now), "a check under 24 h old is not due")
    }

    func testNotDueAtExactly24h() {
        let (c, _) = checker(StubClock(now: now, last: yesterday))
        XCTAssertFalse(c.isDue(now: now), "exactly 24 h is not yet older than 24 h")
    }

    func testAutomaticFetchRunsWhenDue() async {
        let clock = StubClock(now: now, last: dayAgo)
        let (c, f) = checker(clock)
        await c.checkAutomatic()
        XCTAssertEqual(f.latestCalls, 1)
        XCTAssertNotNil(clock.last, "a successful check is recorded")
    }

    func testAutomaticFetchSkippedWhenNotDue() async {
        let clock = StubClock(now: now, last: hourAgo)
        let (c, f) = checker(clock)
        await c.checkAutomatic()
        XCTAssertEqual(f.latestCalls, 0, "not due means no network call")
    }

    func testManualCheckAlwaysRunsWhenNotDue() async {
        let clock = StubClock(now: now, last: hourAgo)
        let (c, f) = checker(clock)
        await c.check()
        XCTAssertEqual(f.latestCalls, 1, "the button always checks")
    }

    func testDisabledToggleNeverFetchesAutomatically() async {
        let clock = StubClock(now: now, last: dayAgo)
        let (c, f) = checker(clock, autoCheck: { false })
        await c.checkAutomatic()
        XCTAssertEqual(f.latestCalls, 0, "off means no automatic network call")
    }

    func testManualCheckRunsEvenWhenToggleOff() async {
        let clock = StubClock(now: now, last: hourAgo)
        let (c, f) = checker(clock, autoCheck: { false })
        await c.check()
        XCTAssertEqual(f.latestCalls, 1, "the button still works with the toggle off")
    }

    func testSuccessfulCheckRecordsTimestamp() async {
        let clock = StubClock(now: now, last: nil)
        let (c, _) = checker(clock)
        await c.check()
        XCTAssertEqual(clock.last, now)
    }

    func testRateLimitIsAnErrorNotUpToDate() async {
        let feed = StubUpdateFeed()
        feed.latest = .failure(UpdateError(message: "GitHub rate limit reached (HTTP 403). Try again later."))
        let (c, _) = checker(StubClock(now: now, last: nil), feed: feed)
        await c.check()
        XCTAssertNotNil(c.checkError, "a rate limit must surface an error")
        XCTAssertTrue(c.checkError?.contains("rate limit") ?? false)
        XCTAssertNil(c.latestVersion, "a rate limit is not an up-to-date result")
    }

    func testNetworkFailureIsAnError() async {
        let feed = StubUpdateFeed()
        feed.latest = .failure(UpdateError(message: "Could not check for updates (HTTP 500)"))
        let (c, _) = checker(StubClock(now: now, last: nil), feed: feed)
        await c.check()
        XCTAssertNotNil(c.checkError)
        XCTAssertNil(c.latestVersion)
    }
}

final class UpdateChannelTests: XCTestCase {
    private func assets(_ names: [String]) -> [[String: Any]] {
        names.map { ["name": $0, "browser_download_url": "https://example.test/\($0)"] }
    }

    func testNoAVX2BuildPicksOnlyNoAVX2DMG() {
        let picks = GitHubUpdateFeed.pickAssets(from: assets([
            "XeonLLM-v0.2.0.dmg", "XeonLLM-v0.2.0-noavx2.dmg", "checksums.txt"
        ]), isNoAVX2: true)
        XCTAssertEqual(picks.dmg?.lastPathComponent, "XeonLLM-v0.2.0-noavx2.dmg")
        XCTAssertEqual(picks.checksums?.lastPathComponent, "checksums.txt")
    }

    func testAVX2BuildNeverPicksNoAVX2DMG() {
        let picks = GitHubUpdateFeed.pickAssets(from: assets([
            "XeonLLM-v0.2.0.dmg", "XeonLLM-v0.2.0-noavx2.dmg", "checksums.txt"
        ]), isNoAVX2: false)
        XCTAssertEqual(picks.dmg?.lastPathComponent, "XeonLLM-v0.2.0.dmg")
    }

    func testNoDMGOnThisChannelPicksNil() {
        let picks = GitHubUpdateFeed.pickAssets(from: assets(["XeonLLM-v0.2.0.dmg"]),
                                                isNoAVX2: true)
        XCTAssertNil(picks.dmg, "a no-AVX2 build gets no AVX2 DMG")
        XCTAssertNil(picks.checksums)
    }
}

final class UpdateChecksumTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeDMG(_ name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try? Data("dmg".utf8).write(to: url)
        return url
    }

    func testMatchingChecksumPasses() throws {
        let dmg = makeDMG("XeonLLM-v0.2.0.dmg")
        // The real sha of the dummy file, so the match is computed not assumed.
        let actual = FileHash.sha256(of: dmg)!
        let listing = "\(actual)  XeonLLM-v0.2.0.dmg"
        let out = try RealUpdateInstaller.checksum(actual: actual, dmg: dmg, listing: listing)
        XCTAssertEqual(out, actual)
    }

    func testMismatchIsRefusedAndFileRemoved() {
        let dmg = makeDMG("XeonLLM-v0.2.0.dmg")
        let listing = "0000  XeonLLM-v0.2.0.dmg"
        XCTAssertThrowsError(try RealUpdateInstaller.checksum(actual: FileHash.sha256(of: dmg)!,
                                                              dmg: dmg, listing: listing)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Checksum mismatch"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dmg.path),
                       "a mismatched download is removed")
    }

    func testMissingChecksumLineIsRefused() throws {
        let dmg = makeDMG("XeonLLM-v0.2.0.dmg")
        let listing = "deadbeef  Other.dmg"
        XCTAssertThrowsError(try RealUpdateInstaller.checksum(actual: FileHash.sha256(of: dmg)!,
                                                              dmg: dmg, listing: listing)) { error in
            XCTAssertTrue(error.localizedDescription.contains("No checksum"))
        }
        // A missing line leaves the file for inspection, like a wrong asset would.
        XCTAssertTrue(FileManager.default.fileExists(atPath: dmg.path))
    }
}

final class UpdateIdentityTests: XCTestCase {
    func testWrongBundleIDIsRefused() {
        XCTAssertThrowsError(try RealUpdateInstaller.identity(bundleID: "dev.evil.app")) { error in
            XCTAssertTrue(error.localizedDescription.contains("bundle identifier"))
        }
    }

    func testRightBundleIDPasses() throws {
        let id = try RealUpdateInstaller.identity(bundleID: AppInfo.identifier)
        XCTAssertEqual(id, AppInfo.identifier)
    }

    func testNoAVX2MismatchIsRefused() {
        XCTAssertThrowsError(try RealUpdateInstaller.identity(noAVX2: !AppInfo.isNoAVX2,
                                                              expected: AppInfo.isNoAVX2)) { error in
            XCTAssertTrue(error.localizedDescription.contains("no-AVX2"))
        }
    }

    func testEqualNoAVX2FlagPasses() throws {
        try RealUpdateInstaller.identity(noAVX2: AppInfo.isNoAVX2, expected: AppInfo.isNoAVX2)
    }

    func testOlderVersionIsRefused() {
        XCTAssertThrowsError(try RealUpdateInstaller.identity(version: "0.1.1", newerThan: AppInfo.version)) { error in
            XCTAssertTrue(error.localizedDescription.contains("not newer"))
        }
    }

    func testEqualVersionIsRefused() {
        XCTAssertThrowsError(try RealUpdateInstaller.identity(version: AppInfo.version,
                                                              newerThan: AppInfo.version)) { error in
            XCTAssertTrue(error.localizedDescription.contains("not newer"))
        }
    }

    func testNewerVersionPasses() throws {
        try RealUpdateInstaller.identity(version: "0.2.1", newerThan: AppInfo.version)
    }
}

final class UpdateSwapTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testSuccessfulSwapRemovesAside() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let aside = dir.appendingPathComponent("XeonLLM.old.app")
        try Data("old".utf8).write(to: target)
        try RealUpdateInstaller.swapApp(target: target, aside: aside,
                                        copy: { try Data("new".utf8).write(to: $0) },
                                        verify: { _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path),
                       "the aside copy is removed after a verified install")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "new")
    }

    func testCopyFailureRestoresOldApp() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let aside = dir.appendingPathComponent("XeonLLM.old.app")
        try Data("old".utf8).write(to: target)
        XCTAssertThrowsError(try RealUpdateInstaller.swapApp(
            target: target, aside: aside,
            copy: { _ in throw UpdateError(message: "copy failed") },
            verify: { _ in })) { error in
            XCTAssertTrue(error.localizedDescription.contains("copy failed"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "old",
                       "the old app is put back")
    }

    func testVerifyFailureRestoresOldApp() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let aside = dir.appendingPathComponent("XeonLLM.old.app")
        try Data("old".utf8).write(to: target)
        XCTAssertThrowsError(try RealUpdateInstaller.swapApp(
            target: target, aside: aside,
            copy: { try Data("new".utf8).write(to: $0) },
            verify: { _ in throw UpdateError(message: "codesign failed") })) { error in
            XCTAssertTrue(error.localizedDescription.contains("codesign failed"))
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "old",
                       "a failed verification still restores the old app")
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path))
    }

    func testFirstInstallHasNoAside() throws {
        let target = dir.appendingPathComponent("XeonLLM.app")
        let aside = dir.appendingPathComponent("XeonLLM.old.app")
        try RealUpdateInstaller.swapApp(target: target, aside: aside,
                                        copy: { try Data("new".utf8).write(to: $0) },
                                        verify: { _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path))
    }
}