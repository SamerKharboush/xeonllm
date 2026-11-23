// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import AppKit
import SwiftUI

struct UpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ReleaseNote: Identifiable {
    let version: String
    let published: Date
    let body: String
    var id: String { version }
}

/// A published release, as read from the feed's JSON. The feed is injected so a
/// test can serve a release without touching GitHub.
struct ReleaseInfo {
    let version: String
    let releaseURL: URL?
    let dmgURL: URL?
    let checksumsURL: URL?
    /// Set when GitHub refused the request (403/429); a rate limit is never "up to date".
    let rateLimited: Bool
}

/// The release-feed seam: latest-release JSON and the release list used for notes.
protocol UpdateFeed {
    func latestRelease() async throws -> ReleaseInfo
    func releaseNotes() async throws -> [(String, String, Date)]
}

/// The clock seam: now and the persisted timestamp of the last successful check.
protocol UpdateClock {
    func now() -> Date
    func lastSuccessfulCheck() -> Date?
    func recordSuccessfulCheck(_ date: Date)
}

/// The installer seam: download, verify, identity-check, swap and relaunch.
protocol UpdateInstalling: AnyObject {
    func install(dmg: URL, checksums: URL?, expectedVersion: String) async throws -> URL
    func relaunch(_ url: URL)
    /// Stops only the engine this app started; never another llama-server.
    @MainActor func stopOwnServer()
}

/// The app's feed: GitHub Releases, with the channel picked from this build's
/// no-AVX2 flag so an AVX-only Mac can never receive an AVX2 DMG.
struct GitHubUpdateFeed: UpdateFeed {
    let api = "https://api.github.com/repos/SamerKharboush/xeonllm"
    let isNoAVX2: Bool

    func latestRelease() async throws -> ReleaseInfo {
        guard let url = URL(string: api + "/releases/latest") else {
            throw UpdateError(message: "Invalid release feed URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 || status == 429 {
            throw UpdateError(message: "GitHub rate limit reached (HTTP \(status)). Try again later.")
        }
        guard status == 200 else {
            throw UpdateError(message: "Could not check for updates (HTTP \(status))")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else {
            throw UpdateError(message: "The release feed returned an unexpected response")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let picks = Self.pickAssets(from: obj["assets"] as? [[String: Any]] ?? [], isNoAVX2: isNoAVX2)
        return ReleaseInfo(version: version,
                           releaseURL: (obj["html_url"] as? String).flatMap(URL.init(string:)),
                           dmgURL: picks.dmg, checksumsURL: picks.checksums, rateLimited: false)
    }

    /// Picks the DMG asset on this build's channel (a no-AVX2 build takes only
    /// `-noavx2`, an AVX2 build never does) plus the shared checksums.txt.
    static func pickAssets(from assets: [[String: Any]], isNoAVX2: Bool) -> (dmg: URL?, checksums: URL?) {
        var dmg: URL?
        var checksums: URL?
        for asset in assets {
            guard let name = asset["name"] as? String,
                  let urlString = asset["browser_download_url"] as? String,
                  let assetURL = URL(string: urlString) else { continue }
            // Each build stays on its own channel: pick the asset matching this
            // bundle's variant so a no-AVX2 install never grabs an AVX2 DMG.
            if name.hasSuffix(".dmg"), name.contains("-noavx2") == isNoAVX2 { dmg = assetURL }
            if name == "checksums.txt" { checksums = assetURL }
        }
        return (dmg, checksums)
    }

    func releaseNotes() async throws -> [(String, String, Date)] {
        guard let url = URL(string: api + "/releases?per_page=30") else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 || status == 429 {
            throw UpdateError(message: "GitHub rate limit reached (HTTP \(status)). Try again later.")
        }
        guard status == 200,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw UpdateError(message: "Could not load the release notes")
        }
        return list.compactMap { obj in
            guard let tag = obj["tag_name"] as? String,
                  let published = obj["published_at"] as? String,
                  let date = UpdateChecker.isoDate.date(from: published) else { return nil }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            return (version, obj["body"] as? String ?? "", date)
        }
    }
}

/// Defaults-backed clock: the running app's own UserDefaults, written with the
/// normal API (never `defaults write` from a shell).
struct UserDefaultsUpdateClock: UpdateClock {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func now() -> Date { Date() }
    func lastSuccessfulCheck() -> Date? {
        let raw = defaults.double(forKey: SettingsKeys.updateLastCheck)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }
    func recordSuccessfulCheck(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: SettingsKeys.updateLastCheck)
    }
}

/// Mounts a verified DMG, checks the app inside it against this build's identity,
/// swaps it in, then relaunches. The old app stays aside until the new one is
/// copied and verified, and is restored on any failure.
final class RealUpdateInstaller: UpdateInstalling {
    private let stopServer: @MainActor () -> Void

    init(stopServer: @escaping @MainActor () -> Void = { ServerManager.shared.stopAllImmediately() }) {
        self.stopServer = stopServer
    }

    @MainActor func stopOwnServer() { stopServer() }

    func relaunch(_ url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(url.path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    func install(dmg: URL, checksums: URL?, expectedVersion: String) async throws -> URL {
        let stop = stopServer
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    continuation.resume(returning: try Self.install(
                        dmg: dmg, checksums: checksums, expectedVersion: expectedVersion,
                        beforeSwap: {
                            // Every check has passed: stop only this app's engine, then swap.
                            DispatchQueue.main.sync { MainActor.assumeIsolated { stop() } }
                        }))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    nonisolated private static func install(dmg: URL, checksums: URL?, expectedVersion: String,
                                             beforeSwap: () -> Void) throws -> URL {
        guard let checksums else {
            throw UpdateError(message: "No checksums.txt in the release: update refused")
        }
        let listing = try String(contentsOf: checksums, encoding: .utf8)
        let actual = try checksum(actual: FileHash.sha256(of: dmg) ?? "", dmg: dmg, listing: listing)

        let plist = try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-plist"])
        guard let data = plist.data(using: .utf8),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = obj["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw UpdateError(message: "Could not mount the DMG")
        }
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount, "-force"]) }

        let fm = FileManager.default
        guard let appName = try fm.contentsOfDirectory(atPath: mount).first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError(message: "The DMG contains no app")
        }
        let source = mount + "/" + appName

        // Identity checks happen on the mounted app, before anything is swapped.
        // All four must pass; any refusal keeps the DMG for inspection.
        guard let info = NSDictionary(contentsOfFile: source + "/Contents/Info.plist") else {
            throw UpdateError(message: "The DMG app has no Info.plist: update refused")
        }
        let bundleID = try identity(bundleID: info["CFBundleIdentifier"] as? String)
        _ = try identity(noAVX2: AppInfo.Identity(values: info as? [String: Any] ?? [:]).noAVX2,
                         expected: AppInfo.isNoAVX2)
        let candidateVersion = AppInfo.Identity(values: info as? [String: Any] ?? [:]).productVersion
            ?? info["CFBundleShortVersionString"] as? String
        _ = try identity(version: candidateVersion, newerThan: expectedVersion)
        do {
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source])
        } catch {
            throw UpdateError(message: "Code signature verification failed: update refused")
        }

        let bundle = Bundle.main.bundleURL
        let target = bundle.path.hasPrefix("/Applications/")
            ? bundle
            : URL(fileURLWithPath: "/Applications").appendingPathComponent(appName)

        let aside = target.deletingPathExtension().appendingPathExtension("old.app")
        beforeSwap()
        try swapApp(target: target, aside: aside, copy: { try copyStripped(source: source, target: $0) },
                    verify: { _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", $0.path]) })
        return target
    }

    /// Verifies the download against its checksums.txt entry. A missing file or
    /// line is as fatal as a mismatch: an unverified download is never installed.
    /// The mismatched file is removed. Returns the matched (lowercased) checksum.
    nonisolated static func checksum(actual: String, dmg: URL, listing: String) throws -> String {
        let expected = listing.split(separator: "\n")
            .first { $0.contains(dmg.lastPathComponent) }?
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
        guard let expected else {
            throw UpdateError(message: "No checksum for \(dmg.lastPathComponent): update refused")
        }
        guard !actual.isEmpty, expected.lowercased() == actual.lowercased() else {
            try? FileManager.default.removeItem(at: dmg)
            throw UpdateError(message: "Checksum mismatch: download discarded")
        }
        return expected.lowercased()
    }

    /// Validates the DMG app's bundle id. Returns it on success.
    nonisolated static func identity(bundleID: String?) throws -> String {
        guard let bundleID, bundleID == AppInfo.identifier else {
            throw UpdateError(message: "Wrong bundle identifier in the DMG: update refused")
        }
        return bundleID
    }

    /// An AVX2 app must never replace a no-AVX2 one (or the reverse): the flags
    /// must be equal.
    nonisolated static func identity(noAVX2 candidate: Bool, expected: Bool) throws {
        guard candidate == expected else {
            throw UpdateError(message: "Wrong no-AVX2 variant in the DMG: update refused")
        }
    }

    /// A DMG must be strictly newer than the running version.
    nonisolated static func identity(version candidate: String?, newerThan current: String) throws {
        guard let candidate, UpdateChecker.isVersion(candidate, newerThan: current) else {
            throw UpdateError(message: "The DMG app is not newer than \(current): update refused")
        }
    }

    /// Moves the old app aside, copies the new one, verifies it and deletes the
    /// aside copy. The old app stays at `aside` until the copy is verified, and is
    /// restored on any failure (including verification).
    nonisolated static func swapApp(target: URL, aside: URL,
                                    copy: (URL) throws -> Void,
                                    verify: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let hadOld = fm.fileExists(atPath: target.path)
        if hadOld {
            try? fm.removeItem(at: aside)
            try fm.moveItem(at: target, to: aside)
        }
        do {
            try copy(target)
            // Keep the old app until the new copy is in place and verified.
            try verify(target)
        } catch {
            try? fm.removeItem(at: target)
            if hadOld { try? fm.moveItem(at: aside, to: target) }
            throw error
        }
        if hadOld { try? fm.removeItem(at: aside) }
    }

    nonisolated private static func copyStripped(source: String, target: URL) throws {
        _ = try run("/usr/bin/ditto", [source, target.path])
        // The app's own downloads are not quarantined, but strip the attribute
        // defensively so Gatekeeper never flags the checksum-verified copy.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> String {
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
            let output = String(data: data, encoding: .utf8) ?? ""
            throw UpdateError(message: URL(fileURLWithPath: tool).lastPathComponent + ": "
                + (output.isEmpty ? "error \(p.terminationStatus)" : String(output.suffix(300))))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Checks GitHub Releases for a newer published version and installs it. The
/// feed, clock and installer are injected seams; production uses the GitHub,
/// UserDefaults and real-installer defaults.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var releaseURL: URL?
    @Published var checking = false
    @Published var installing = false
    @Published var installError: String?
    @Published var checkError: String?
    @Published var lastChecked: Date?

    private var dmgURL: URL?
    private var checksumsURL: URL?
    private var periodicTask: Task<Void, Never>?

    let feed: UpdateFeed
    let clock: UpdateClock
    let installer: UpdateInstalling
    private let autoCheck: () -> Bool

    init(feed: UpdateFeed? = nil, clock: UpdateClock? = nil, installer: UpdateInstalling? = nil,
         autoCheck: @escaping () -> Bool = {
             UserDefaults.standard.object(forKey: SettingsKeys.updateAutoCheck) == nil
                 || UserDefaults.standard.bool(forKey: SettingsKeys.updateAutoCheck)
         }) {
        self.feed = feed ?? GitHubUpdateFeed(isNoAVX2: AppInfo.isNoAVX2)
        self.clock = clock ?? UserDefaultsUpdateClock()
        self.installer = installer ?? RealUpdateInstaller()
        self.autoCheck = autoCheck
        self.lastChecked = self.clock.lastSuccessfulCheck()
    }

    /// True when an automatic check may hit the network: the toggle is on and the
    /// last successful check is older than 24 h (or has never happened).
    func isDue(now: Date? = nil) -> Bool {
        let current = now ?? clock.now()
        guard let last = lastChecked ?? clock.lastSuccessfulCheck() else { return true }
        return current.timeIntervalSince(last) > Self.dailyInterval
    }

    nonisolated static let dailyInterval: TimeInterval = 24 * 3600

    /// Checks at launch and then hourly, but only hits the network when due.
    /// A disabled toggle makes no network call at all.
    func startPeriodicChecks(interval: TimeInterval = 3600) {
        guard AppInfo.updatesEnabled, periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.checkAutomatic()
            }
        }
    }

    func checkAutomatic() async {
        guard AppInfo.updatesEnabled, autoCheck(), isDue() else { return }
        await check()
    }

    /// "Check for updates" always checks, regardless of the toggle or due date.
    func check() async {
        guard AppInfo.updatesEnabled, !checking else { return }
        checking = true
        checkError = nil
        defer { checking = false }
        do {
            let release = try await feed.latestRelease()
            lastChecked = clock.now()
            clock.recordSuccessfulCheck(lastChecked!)
            if Self.isVersion(release.version, newerThan: AppInfo.version) {
                latestVersion = release.version
                releaseURL = release.releaseURL
                dmgURL = release.dmgURL
                checksumsURL = release.checksumsURL
            } else {
                latestVersion = nil
                releaseURL = nil
                dmgURL = nil
                checksumsURL = nil
            }
        } catch let error as UpdateError {
            checkError = error.message
        } catch {
            checkError = "Could not check for updates: \(error.localizedDescription)"
        }
    }

    /// Downloads the release DMG, verifies it, installs the app and relaunches.
    func downloadAndInstall() async {
        guard !installing else { return }
        // The DMG asset may not have been uploaded yet when the release was
        // first detected (CI uploads it after creating the release); refresh
        // before giving up and sending the user to the website.
        if dmgURL == nil { await check() }
        guard let dmgURL else {
            if checkError == nil { checkError = "No \(AppInfo.isNoAVX2 ? "no-AVX2" : "AVX2") DMG found in the release" }
            if let releaseURL { NSWorkspace.shared.open(releaseURL) }
            return
        }
        installing = true
        installError = nil
        defer { installing = false }

        do {
            let (temp, _) = try await URLSession.shared.download(from: dmgURL)
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let dest = downloads.appendingPathComponent(dmgURL.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: temp, to: dest)
            // The feed's checksums URL is passed to the installer, which refuses
            // a missing or mismatched entry. The DMG stays on failure for inspection.
            // The installer stops only this app's own engine, and only after every
            // check has passed, just before the swap; a refused update leaves it running.
            let installed = try await installer.install(dmg: dest, checksums: checksumsURL,
                                                        expectedVersion: AppInfo.version)
            try? FileManager.default.removeItem(at: dest)
            installer.relaunch(installed)
        } catch let error as UpdateError {
            installError = error.message
        } catch {
            installError = error.localizedDescription
        }
    }

    // MARK: release notes

    @Published var releaseNotes: [ReleaseNote]?
    @Published var loadingNotes = false

    nonisolated static let isoDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Notes from the running version up to the newest release; when already
    /// up to date, just the running version's notes.
    func fetchReleaseNotes() async {
        guard !loadingNotes else { return }
        loadingNotes = true
        defer { loadingNotes = false }
        do {
            let all = try await feed.releaseNotes()
            releaseNotes = Self.notesToShow(all: all, current: AppInfo.version)
                .map { ReleaseNote(version: $0.0, published: $0.2, body: $0.1) }
        } catch {
            releaseNotes = []
        }
    }

    /// Releases published after the running version's own release, newest
    /// first; when the running version has no release on GitHub yet (a dev
    /// build), just the most recent one. Order follows `published_at`, not the
    /// version number: a beta numbered above the next release must not look
    /// newer than it.
    nonisolated static func notesToShow(all: [(String, String, Date)], current: String) -> [(String, String, Date)] {
        let sorted = all.sorted { $0.2 > $1.2 }
        guard let running = sorted.first(where: { $0.0 == current }) else {
            return sorted.first.map { [$0] } ?? []
        }
        let newer = sorted.filter { $0.2 > running.2 }
        return newer.isEmpty ? [running] : newer
    }

    /// Numeric per-component comparison (0.81.1 < 0.82 < 1.0).
    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Popup with the release notes covered by `fetchReleaseNotes`.
struct ReleaseNotesPopover: View {
    @EnvironmentObject var updates: UpdateChecker
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppInfo.branded("Release notes"), systemImage: "doc.text")
                .font(.headline)
            if updates.loadingNotes {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .frame(minHeight: 80)
            } else if let notes = updates.releaseNotes, !notes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(notes) { note in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text("v\(note.version)").font(.subheadline.weight(.semibold))
                                    if note.version == AppInfo.version {
                                        Text(AppInfo.branded("current"))
                                            .font(.caption2)
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                                RichText(text: note.body)
                                    .font(.callout)
                            }
                            if note.id != notes.last?.id { Divider() }
                        }
                    }
                    .padding(.trailing, 6)
                }
                .frame(maxHeight: 420)
            } else {
                Text(AppInfo.branded("Could not load the notes."))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(minHeight: 60)
            }
            Divider()
            Button(AppInfo.branded("View on GitHub")) {
                let tag = updates.releaseNotes?.first.map { "v\($0.version)" } ?? "v\(AppInfo.version)"
                NSWorkspace.shared.open(URL(string: "https://github.com/SamerKharboush/xeonllm/releases/tag/\(tag)")!)
            }
            .buttonStyle(.link).font(.caption)
        }
        .padding(14)
        .frame(width: 480)
        .task { await updates.fetchReleaseNotes() }
    }
}
