// XeonLLM - run LLMs locally (fork of ToshLLM) on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// MARK: - About

enum AppInfo {
    static let version = "0.87.31-beta.8"
    /// True for the pre-AVX2 legacy build (Info.plist XEONNoAVX2). Kept on its own
    /// update channel so it never pulls an AVX2 DMG that would SIGILL on those CPUs.
    static let isNoAVX2 = identity.noAVX2
    static let developerName = "Samer Kharboush"
    static let developerHandle = "SamerKharboush"
    static let githubURL = "https://github.com/SamerKharboush"
    static let repositoryURL = "https://github.com/SamerKharboush/xeonllm"
    static let issuesURL = repositoryURL + "/issues"
    static let featureRequestURL = repositoryURL + "/issues/new?template=feature_request.yml"
    static let discussionsURL = repositoryURL + "/discussions"

    /// Ways to support development. Every donate surface (toolbar, About, docs) reads
    /// this list so they cannot drift apart, and the test checks it is exactly these two.
    static let donateOptions: [(label: String, url: String)] = [
        ("GitHub Sponsors", "https://github.com/sponsors/SamerKharboush"),
        ("PayPal", "https://paypal.me/Samerelnady"),
    ]

    // A build packaged under another identity (XEON_APP_NAME in make-app.sh) carries these keys;
    // a plain build has none of them and keeps XeonLLM's.
    static let identity = Identity(values: Bundle.main.infoDictionary ?? [:])
    static let name = identity.name ?? "XeonLLM"
    static let identifier = identity.identifier ?? "dev.xeonllm.app"
    static let dataFolder = identity.dataFolder ?? "XeonLLM"
    /// The build's own version; `version` stays the XeonLLM it is built on.
    static let productVersion = identity.productVersion ?? version
    static let updatesEnabled = !identity.updatesDisabled
    static var isRebranded: Bool { name != "XeonLLM" }

    /// The identity a bundle's Info.plist carries, under the keys `make-app.sh` writes.
    /// `values` is the plist as a dictionary, so a test can read the keys the app looks for
    /// without packaging an app.
    struct Identity {
        let noAVX2: Bool
        let name: String?
        let identifier: String?
        let dataFolder: String?
        let productVersion: String?
        let updatesDisabled: Bool

        init(values: [String: Any]) {
            noAVX2 = values["XEONNoAVX2"] as? Bool ?? false
            name = Self.string(values["XEONProductName"])
            identifier = Self.string(values["XEONIdentifier"])
            dataFolder = Self.string(values["XEONDataFolder"])
            productVersion = Self.string(values["XEONProductVersion"])
            updatesDisabled = values["XEONUpdatesDisabled"] as? Bool ?? false
        }

        private static func string(_ value: Any?) -> String? {
            (value as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// Interface text that names the app, with this build's name in it.
    static func branded(_ text: String) -> String {
        isRebranded ? text.replacingOccurrences(of: "XeonLLM", with: name) : text
    }
}

struct AboutView: View {
    @EnvironmentObject private var loc: Localizer
    @EnvironmentObject private var updates: UpdateChecker
    @State private var showNotes = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                benefits
                details
                systemInformation
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(WorkspaceStyle.canvas)
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            WorkspaceHeroArtwork()
            LinearGradient(colors: [WorkspaceStyle.surface.opacity(0.99),
                                    WorkspaceStyle.surface.opacity(0.91),
                                    WorkspaceStyle.surface.opacity(0.12)],
                           startPoint: .leading, endPoint: .trailing)
                .allowsHitTesting(false)
            HStack(spacing: 20) {
                XeonLLMLogo(size: 92)
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppInfo.name)
                        .font(.system(size: 32, weight: .bold))
                    HStack(spacing: 9) {
                        Text(versionLine)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        updateBadge
                    }
                    Text(AppInfo.branded("Local language models with Metal acceleration on Intel Macs with AMD GPUs."))
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(2)
                    Text(AppInfo.branded("Private. Fast. Powerful. XeonLLM brings open-source AI to your machine with a clean, native macOS experience."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    HStack(spacing: 9) {
                        updateButton
                        Button {
                            showNotes = true
                        } label: {
                            Label(AppInfo.branded("View release notes"), systemImage: "doc.text")
                        }
                        .glassButton()
                        .popover(isPresented: $showNotes, arrowEdge: .bottom) { ReleaseNotesPopover() }
                    }
                    if let error = updates.installError {
                        Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                    }
                }
                .frame(maxWidth: 650, alignment: .leading)
            }
            .padding(.horizontal, 68)
            .padding(.vertical, 30)
        }
        .frame(minHeight: 250)
        .cardSurface(tint: Color.purple.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: CardMetrics.corner, style: .continuous))
    }

    private var versionLine: String {
        let line = AppInfo.branded("Version") + " " + AppInfo.productVersion
        guard AppInfo.isRebranded else { return line }
        return line + " · " + AppInfo.branded("based on \("XeonLLM") \(AppInfo.version)")
    }

    @ViewBuilder private var updateBadge: some View {
        if !AppInfo.updatesEnabled {
            EmptyView()
        } else if let latest = updates.latestVersion {
            Text(AppInfo.branded("\(latest) available"))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(.orange)
                .background(Color.orange.opacity(0.12), in: Capsule())
        } else {
            Text(AppInfo.branded("Latest"))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(.green)
                .background(Color.green.opacity(0.12), in: Capsule())
        }
    }

    @ViewBuilder private var updateButton: some View {
        if !AppInfo.updatesEnabled {
            Label(AppInfo.branded("Updates for this build are managed outside the app"),
                  systemImage: "building.2")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let latest = updates.latestVersion {
            Button {
                Task { await updates.downloadAndInstall() }
            } label: {
                Label(updates.installing
                      ? AppInfo.branded("Updating…")
                      : AppInfo.branded("Download \(latest)"),
                      systemImage: updates.installing ? "arrow.down.circle" : "arrow.down.app")
                    .spinningSymbol(updates.installing)
            }
            .glassButton(prominent: true)
            .disabled(updates.installing)
        } else {
            Button {
                Task { await updates.check() }
            } label: {
                Label(updates.checking
                      ? AppInfo.branded("Checking…")
                      : AppInfo.branded("Check for updates"),
                      systemImage: "arrow.triangle.2.circlepath")
                    .spinningSymbol(updates.checking)
            }
            .glassButton(prominent: true)
            .disabled(updates.checking)
        }
    }

    private var benefits: some View {
        AdaptiveTwoUp(threshold: 860, spacing: 0) {
            HStack(spacing: 0) {
                AboutBenefit(icon: "shield.checkered", color: .pink,
                             title: AppInfo.branded("100% Local"),
                             detail: AppInfo.branded("Your data stays on your machine."))
                AboutBenefit(icon: "bolt.fill", color: .pink,
                             title: AppInfo.branded("Metal Acceleration"),
                             detail: AppInfo.branded("Optimized for Apple Silicon and AMD GPUs."))
            }
        } second: {
            HStack(spacing: 0) {
                AboutBenefit(icon: "shippingbox", color: .blue,
                             title: AppInfo.branded("Open Source"),
                             detail: AppInfo.branded("Powered by the community and open models."))
                AboutBenefit(icon: "lock", color: .green,
                             title: AppInfo.branded("Privacy First"),
                             detail: AppInfo.branded("No telemetry. No tracking. No cloud required."))
            }
        }
        .padding(.vertical, 8)
        .cardSurface()
    }

    private var details: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                developerCard
                creditsCard
            }
            .frame(maxWidth: .infinity)
            projectLinksCard
                .frame(maxWidth: 470)
        }
    }

    private var developerCard: some View {
        AboutCard(icon: "person.2", title: AppInfo.branded("Developer")) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppInfo.developerName).font(.system(size: 14, weight: .semibold))
                    Text("@" + AppInfo.developerHandle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button { open(AppInfo.githubURL) } label: {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .glassButton().fixedSize()
                Menu {
                    ForEach(AppInfo.donateOptions, id: \.url) { option in
                        Button(option.label) { open(option.url) }
                    }
                } label: {
                    Label(AppInfo.branded("Donate"), systemImage: "heart.fill")
                }
                .menuStyle(.button)
                .glassButton(prominent: true)
                .fixedSize()
            }
        }
    }

    private var creditsCard: some View {
        AboutCard(icon: "hands.clap", title: AppInfo.branded("Credits")) {
            VStack(spacing: 0) {
                AboutLinkRow(icon: nil, title: "ToshLLM (engeldlgado)",
                             detail: AppInfo.branded("XeonLLM is a fork of ToshLLM")) {
                    open("https://github.com/engeldlgado/toshllm")
                }
                Divider()
                AboutLinkRow(icon: nil, title: "llama.cpp", detail: "ggml-org · " + AppInfo.branded("inference engine")) {
                    open("https://github.com/ggml-org/llama.cpp")
                }
                Divider()
                AboutLinkRow(icon: nil, title: "iRon-Llama (Basten7)",
                             detail: AppInfo.branded("Metal patches for AMD dGPU on Intel Mac")) {
                    open("https://github.com/Basten7/iRon-Llama-RC1")
                }
            }
        }
    }

    private var projectLinksCard: some View {
        AboutCard(icon: "link", title: AppInfo.branded("Project links")) {
            VStack(spacing: 0) {
                AboutLinkRow(icon: "chevron.left.forwardslash.chevron.right",
                             title: AppInfo.branded("GitHub repository")) { open(AppInfo.repositoryURL) }
                Divider()
                AboutLinkRow(icon: "exclamationmark.triangle",
                             title: AppInfo.branded("Report an issue")) { open(AppInfo.issuesURL) }
                Divider()
                AboutLinkRow(icon: "lightbulb",
                             title: AppInfo.branded("Request a feature")) { open(AppInfo.featureRequestURL) }
                Divider()
                AboutLinkRow(icon: "bubble.left.and.bubble.right",
                             title: AppInfo.branded("Discussions")) { open(AppInfo.discussionsURL) }
            }
        }
    }

    private var systemInformation: some View {
        let hardware = AboutHardware.snapshot
        return AboutCard(icon: "desktopcomputer", title: AppInfo.branded("System information"),
                         subtitle: AppInfo.branded("Your current environment.")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button {
                        copySystemInformation(hardware)
                    } label: {
                        Label(copied ? AppInfo.branded("Copied") : AppInfo.branded("Copy system info"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .glassButton()
                }
                .padding(.top, -38)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    AboutSystemMetric(icon: "apple.logo", title: "macOS", value: hardware.osVersion)
                    AboutSystemMetric(icon: "cpu", title: AppInfo.branded("Chip"),
                                      value: hardware.arch == "arm64" ? "Apple Silicon" : "Intel Mac")
                    AboutSystemMetric(icon: "display", title: "GPU", value: hardware.bestGPU?.name ?? "—")
                    AboutSystemMetric(icon: "memorychip", title: AppInfo.branded("Memory"),
                                      value: String(format: "%.0f GB", hardware.ramGB))
                }
            }
        }
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copySystemInformation(_ hardware: HardwareInfo) {
        let gpu = hardware.gpus.isEmpty
            ? "—"
            : hardware.gpus.map { "\($0.name) (\($0.vramGB) GB)" }.joined(separator: ", ")
        let value = """
        \(AppInfo.name) \(AppInfo.productVersion)\(AppInfo.isRebranded ? " (XeonLLM \(AppInfo.version))" : "")\(AppInfo.isNoAVX2 ? " (no-AVX2)" : "")
        \(hardware.osVersion)
        Model: \(hardware.model)
        CPU: \(hardware.cpuBrand) · \(hardware.physicalCores) cores / \(hardware.logicalCores) threads
        Architecture: \(hardware.arch)
        GPU: \(gpu)
        Memory: \(String(format: "%.0f GB", hardware.ramGB))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

private enum AboutHardware {
    /// Hardware probing touches sysctl and Metal; keep one result for the whole
    /// process rather than repeating it as the view hierarchy refreshes.
    static let snapshot = HardwareInfo.detect()
}

private struct AboutBenefit: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
    }
}

private struct AboutCard<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    init(icon: String, title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.appAccent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardSurface()
    }
}

private struct AboutLinkRow: View {
    let icon: String?
    let title: String
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(WorkspaceStyle.inset,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AboutSystemMetric: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
                .background(WorkspaceStyle.inset,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(WorkspaceStyle.inset.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(WorkspaceStyle.border))
    }
}
