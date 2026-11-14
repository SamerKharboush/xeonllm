// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var manager: ServerManager
    @EnvironmentObject private var loc: Localizer
    @State private var selectedID: UUID?

    private var selected: ServerController {
        manager.servers.first { $0.id == selectedID } ?? manager.servers[0]
    }
    private var serverSelection: Binding<UUID> {
        Binding(get: { selected.id }, set: { selectedID = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            if manager.servers.count > 1 {
                HStack {
                    Label(AppInfo.branded("Instance"), systemImage: "server.rack")
                        .font(.callout.bold())
                    XeonDropdown(selection: serverSelection,
                                 options: manager.servers.map {
                                     .init(value: $0.id,
                                           title: manager.displayName(for: $0, loc: loc),
                                           subtitle: ModelName.forPath($0.effectiveSettings().modelPath).display,
                                           systemImage: "circle.fill")
                                 }, width: 280)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                Divider()
            }
            ServerLogView(server: selected).id(selected.id)
        }
    }
}

struct ServerLogView: View {
    @ObservedObject var server: ServerController
    @ObservedObject private var logBuffer: ServerLogBuffer
    @EnvironmentObject private var loc: Localizer

    @State private var query = ""
    @State private var selectedLevel = "all"
    @State private var autoFollow = true
    @State private var copied = false
    @State private var logSource = "server"
    @State private var imageLog = ""
    @State private var videoLog = ""
    @State private var lines: [PresentedLogLine] = []
    @State private var displayLimit = 400
    @StateObject private var checker = EngineChecker()
    @State private var checkVerdict: String?

    init(server: ServerController) {
        self.server = server
        self._logBuffer = ObservedObject(wrappedValue: server.logBuffer)
    }

    private var rawLog: String {
        switch logSource {
        case "images": imageLog
        case "video": videoLog
        default: server.log
        }
    }
    private var parseToken: String {
        "\(logSource)|\(rawLog.utf8.count)|\(rawLog.suffix(48))"
    }
    private var matchingLines: [PresentedLogLine] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedLevel == "all" && needle.isEmpty { return lines }
        return lines.filter {
            (selectedLevel == "all" || levelKey($0.level) == selectedLevel) &&
            (needle.isEmpty || $0.raw.localizedCaseInsensitiveContains(needle))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                serverSummary
                sourceSwitcher
                statistics
                logConsole
            }
            .padding(16)
        }
        .background(WorkspaceStyle.canvas)
        .task(id: logSource) { await pollExternalLog() }
        .task(id: parseToken) { await parseCurrentLog() }
        .sheet(isPresented: .constant(checker.running)) { engineCheckSheet }
        .alert(AppInfo.branded("Engine check"),
               isPresented: Binding(get: { checkVerdict != nil }, set: { if !$0 { checkVerdict = nil } })) {
            Button(AppInfo.branded("OK"), role: .cancel) {}
        } message: { Text(checkVerdict ?? "") }
    }

    private var settings: ServerSettings { server.effectiveSettings() }
    private var modelName: ModelName { ModelName.forPath(settings.modelPath) }

    private var serverSummary: some View {
        HStack(spacing: 16) {
            ModelBrandIcon(name: modelName.title, size: 42)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(modelName.title.isEmpty ? server.name : modelName.title)
                        .font(.title3.bold()).lineLimit(1)
                    statusPill
                }
                // on a narrow window the card's own details give way before the essentials are cut
                ViewThatFits(in: .horizontal) {
                    summaryValues(full: true)
                    summaryValues(full: false)
                }
            }
            Spacer(minLength: 12)
            GlassActionGroup {
                ServerWebUIButton(server: server)
                    .glassButton()
                serverAction
            }
        }
        .padding(16)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceStyle.border))
    }

    private func summaryValues(full: Bool) -> some View {
        HStack(spacing: 0) {
            summaryValue(modelName.quant.isEmpty ? "GGUF" : modelName.quant)
            if full { summaryValue("\(hardware.bestGPU?.vramGB ?? 0) GB VRAM") }
            summaryValue("\(AppInfo.branded("Port")) \(settings.port)")
            summaryValue(AppInfo.branded("\(compactContext(settings.ctx)) context"), last: !full)
            if full {
                summaryValue(settings.serverBinary == ServerSettings.defaultBinary ? "llama.cpp" : AppInfo.branded("External engine"), last: true)
            }
        }
    }

    private func summaryValue(_ value: String, last: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(value).font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            if !last { Divider().frame(height: 18) }
        }
        .padding(.trailing, last ? 0 : 10)
    }

    private var statusPill: some View {
        let presentation = statePresentation
        return Label(presentation.title, systemImage: presentation.icon)
            .font(.caption.bold()).foregroundStyle(presentation.color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(presentation.color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder private var serverAction: some View {
        switch server.state {
        case .running, .starting:
            Button(AppInfo.branded("Stop server"), systemImage: "stop.fill", role: .destructive) { server.stop() }
                .glassButton(prominent: true)
        default:
            Button(AppInfo.branded("Start server"), systemImage: "play.fill") { server.start(settings) }
                .glassButton(prominent: true).disabled(settings.modelPath.isEmpty)
        }
    }

    private var statePresentation: (title: String, icon: String, color: Color) {
        switch server.state {
        case .running: (AppInfo.branded("Running"), "checkmark.circle.fill", .green)
        case .starting: (AppInfo.branded("Starting"), "clock.fill", .orange)
        case .failed: (AppInfo.branded("Failed"), "xmark.circle.fill", .red)
        case .stopped: (AppInfo.branded("Stopped"), "circle", .secondary)
        }
    }
    private func compactContext(_ value: Int) -> String {
        value >= 1024 && value % 1024 == 0 ? "\(value / 1024)k" : "\(value)"
    }

    private var sourceSwitcher: some View {
        HStack {
            GlassSegmentedControl(selection: $logSource, segments: [
                .init(value: "server", title: AppInfo.branded("Server"), systemImage: "server.rack"),
                .init(value: "images", title: AppInfo.branded("Images"), systemImage: "photo"),
                .init(value: "video", title: AppInfo.branded("Video"), systemImage: "film"),
            ])
            Spacer()
            Button(AppInfo.branded("Logs in Finder"), systemImage: "folder") { revealCurrentLog() }
                .glassButton().controlSize(.small)
        }
    }

    private var statistics: some View {
        AdaptiveTwoUp(threshold: 640, spacing: 10) {
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    statisticCard(icon: "bolt.fill", title: AppInfo.branded("Uptime"), value: uptime, tint: Color.appAccent)
                }
                statisticCard(icon: "doc.text.fill", title: AppInfo.branded("Total lines"), value: lines.count.formatted(), tint: .secondary)
            }
        } second: {
            HStack(spacing: 10) {
                statisticCard(icon: "exclamationmark.triangle.fill", title: AppInfo.branded("Warnings"), value: warningCount.formatted(), tint: .orange)
                statisticCard(icon: "xmark.octagon.fill", title: AppInfo.branded("Errors"), value: errorCount.formatted(), tint: .red)
            }
        }
    }

    private func statisticCard(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
                .frame(width: 38, height: 38).background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.bold()).monospacedDigit()
            }
            Spacer()
        }
        .padding(14)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(WorkspaceStyle.border))
    }

    private var warningCount: Int { lines.lazy.filter { $0.level == .warning }.count }
    private var errorCount: Int { lines.lazy.filter { $0.level == .error }.count }
    private var uptime: String {
        guard let start = server.startedAt else { return "—" }
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds)s"
    }

    private var logConsole: some View {
        let matches = matchingLines
        let visible = matches.suffix(displayLimit)
        return VStack(spacing: 0) {
            consoleToolbar
            Divider()
            logTable(matches: matches, visible: visible)
            Divider()
            HStack {
                Text(AppInfo.branded("Showing \(visible.count.formatted()) of \(matches.count.formatted()) lines"))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Label(footerStatus.title, systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(footerStatus.color)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceStyle.border))
    }

    private var consoleToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                searchField
                levelFilter
                Spacer(minLength: 8)
                consoleActions
            }
            VStack(spacing: 10) {
                HStack { searchField; Spacer(minLength: 8); moreMenu }
                HStack { levelFilter; Spacer(minLength: 8); compactConsoleActions }
            }
        }
        .padding(12)
        .onChange(of: query) { displayLimit = 400 }
        .onChange(of: selectedLevel) { displayLimit = 400 }
    }

    private var searchField: some View {
        GlassSearchField(placeholder: AppInfo.branded("Search logs…"), text: $query)
            .frame(minWidth: 220, idealWidth: 320, maxWidth: 360)
    }

    private var levelFilter: some View {
        GlassSegmentedControl(selection: $selectedLevel, segments: [
            .init(value: "all", title: AppInfo.branded("All")),
            .init(value: "info", title: "Info", systemImage: "info.circle.fill"),
            .init(value: "warning", title: AppInfo.branded("Warnings"), systemImage: "exclamationmark.triangle.fill"),
            .init(value: "error", title: AppInfo.branded("Errors"), systemImage: "xmark.octagon.fill"),
        ])
    }

    private func levelKey(_ level: PresentedLogLevel) -> String {
        switch level { case .info: "info"; case .warning: "warning"; case .error: "error" }
    }

    private var footerStatus: (title: String, color: Color) {
        guard logSource == "server" else { return (AppInfo.branded("Auto refresh"), .green) }
        switch server.state {
        case .running, .starting: return (AppInfo.branded("Live"), .green)
        case .failed: return (AppInfo.branded("Failed"), .red)
        case .stopped: return (AppInfo.branded("Stopped"), .secondary)
        }
    }

    private var consoleActions: some View {
        HStack(spacing: 10) {
            Toggle(AppInfo.branded("Follow"), isOn: $autoFollow).toggleStyle(.switch).controlSize(.small)
            Button(AppInfo.branded("Clear"), systemImage: "trash") { clearVisibleLog() }.glassButton().controlSize(.small)
            Button(AppInfo.branded("Export"), systemImage: "square.and.arrow.up") { exportDiagnostics() }.glassButton().controlSize(.small)
            moreMenu
        }
    }

    private var compactConsoleActions: some View {
        HStack(spacing: 10) {
            Toggle(AppInfo.branded("Follow"), isOn: $autoFollow).toggleStyle(.switch).controlSize(.small)
            Button(AppInfo.branded("Clear"), systemImage: "trash") { clearVisibleLog() }.glassButton().controlSize(.small)
            Button(AppInfo.branded("Export"), systemImage: "square.and.arrow.up") { exportDiagnostics() }.glassButton().controlSize(.small)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(copied ? AppInfo.branded("Copied") : AppInfo.branded("Copy visible lines"),
                   systemImage: copied ? "checkmark" : "doc.on.doc") { copy() }
            Button(AppInfo.branded("Check engine and export…"), systemImage: "checkmark.seal") { startEngineCheck() }
                .disabled(!engineCheckReady).help(engineCheckHelp)
            Button(AppInfo.branded("Logs in Finder"), systemImage: "folder") { revealCurrentLog() }
        } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(AppInfo.branded("More actions"))
    }

    @ViewBuilder private func logTable(matches: [PresentedLogLine],
                                       visible: ArraySlice<PresentedLogLine>) -> some View {
        if matches.isEmpty {
            emptyState.frame(minHeight: 310)
        } else {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    logHeader
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if matches.count > displayLimit {
                                Button { displayLimit += 400 } label: {
                                    Label(AppInfo.branded("Load \(min(400, matches.count - displayLimit).formatted()) earlier lines"), systemImage: "arrow.up.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain).foregroundStyle(Color.appAccent).padding(12)
                            }
                            ForEach(visible) { line in PresentedLogRow(line: line) }
                            Color.clear.frame(height: 1).id("logEnd")
                        }
                    }
                    .frame(minHeight: 320, idealHeight: 470)
                    .onChange(of: lines.count) { if autoFollow { proxy.scrollTo("logEnd", anchor: .bottom) } }
                    .onChange(of: autoFollow) { if autoFollow { proxy.scrollTo("logEnd", anchor: .bottom) } }
                    .task { if autoFollow { proxy.scrollTo("logEnd", anchor: .bottom) } }
                }
            }
        }
    }

    private var logHeader: some View {
        HStack(spacing: 12) {
            Text(AppInfo.branded("Time")).frame(width: 106, alignment: .leading)
            Text(AppInfo.branded("Level")).frame(width: 74, alignment: .leading)
            Text(AppInfo.branded("Source")).frame(width: 90, alignment: .leading)
            Divider().frame(height: 18)
            Text(AppInfo.branded("Message")); Spacer()
        }
        .font(.caption.bold()).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(WorkspaceStyle.inset.opacity(0.55))
    }

    @ViewBuilder private var emptyState: some View {
        if rawLog.isEmpty {
            ContentUnavailableView(AppInfo.branded("No activity yet"), systemImage: "text.alignleft",
                                   description: Text(AppInfo.branded("Engine output will appear here when it runs.")))
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView(AppInfo.branded("No lines at this level"), systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private func parseCurrentLog() async {
        let snapshot = rawLog
        let source = logSource == "server" ? "Engine" : (logSource == "images" ? "Image" : "Video")
        let parsed = await Task.detached(priority: .utility) { LogPresentationParser.parse(snapshot, fallbackSource: source) }.value
        guard !Task.isCancelled else { return }
        lines = parsed
    }

    private func pollExternalLog() async {
        guard logSource != "server" else { return }
        while !Task.isCancelled {
            let source = logSource
            let url = source == "images" ? ImageGenerator.latestLogURL : VideoGenerator.latestLogURL
            let text = await Task.detached(priority: .utility) { LogFileTail.read(url) }.value
            guard !Task.isCancelled, source == logSource else { return }
            if source == "images" { imageLog = text } else { videoLog = text }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    private func clearVisibleLog() {
        switch logSource {
        case "images": imageLog = ""
        case "video": videoLog = ""
        default: server.log = ""
        }
        lines = []
    }
    private func copy() {
        let visible = matchingLines.suffix(displayLimit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(visible.map(\.raw).joined(separator: "\n"), forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
    }
    private func revealCurrentLog() {
        let file: URL
        switch logSource {
        case "images": file = ImageGenerator.latestLogURL ?? server.logsDirectory
        case "video": file = VideoGenerator.latestLogURL ?? server.logsDirectory
        default: file = server.logFileURL
        }
        revealInFinder(file: file, folder: server.logsDirectory)
    }

    private var engineBinary: String { ServerSettings.resolvedBinary() }
    private var engineCheckAvailable: Bool { EngineCheck.isAvailable(serverBinary: engineBinary) }
    private var engineCheckReady: Bool {
        server.state != .running && server.state != .starting && engineCheckAvailable
    }
    private var engineCheckHelp: String {
        if server.state == .running || server.state == .starting {
            return AppInfo.branded("Stop the server before checking: the test uses the whole GPU.")
        }
        if !engineCheckAvailable {
            return AppInfo.branded("This engine does not ship the check tool.")
        }
        return AppInfo.branded("Runs the engine tests and adds the result to diagnostics.")
    }
    private var engineCheckSheet: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(AppInfo.branded("Checking the engine…")).font(.headline)
            Text(AppInfo.branded("\(checker.testCount) operations tested\("\(checker.currentOp.isEmpty ? "" : " · \(checker.currentOp)")")"))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Button(AppInfo.branded("Cancel"), role: .cancel) { checker.cancel() }.keyboardShortcut(.cancelAction)
        }
        .padding(24).frame(minWidth: 340)
    }
    private func startEngineCheck() {
        checker.start(settings: ServerSettings.fromDefaults()) { result in
            guard !result.cancelled else { return }
            saveDiagnostics(extra: EngineCheck.report(result), name: "xeonllm-engine-check.txt")
            checkVerdict = EngineCheck.verdict(result)
        }
    }
    private func exportDiagnostics() { saveDiagnostics(extra: nil, name: "xeonllm-diagnostics.txt") }
    private func saveDiagnostics(extra: String?, name: String) {
        let currentSettings = ServerSettings.fromDefaults()
        let logTail = LogFileTail.read(server.logFileURL, maxBytes: 256 * 1024)
        let gpu = hardware.bestGPU.map { "\($0.name) (\($0.vramMB) MB VRAM)" } ?? "—"
        let report = """
        XeonLLM \(AppInfo.version) — diagnostics
        Date: \(Date().formatted(.iso8601))

        ## Hardware
        CPU: \(hardware.cpuBrand) (\(hardware.physicalCores)c/\(hardware.logicalCores)t)
        RAM: \(Int(hardware.ramGB)) GB
        GPU: \(gpu)
        Arch: \(hardware.arch)

        ## Configuration
        model: \(URL(fileURLWithPath: currentSettings.modelPath).lastPathComponent)
        engine: \(currentSettings.serverBinary)
        args: \(currentSettings.arguments.joined(separator: " "))
        \(extra.map { "\n\($0)\n" } ?? "")
        ## Recent log
        \(logTail.isEmpty ? server.log : logTail)
        """
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url { try? report.write(to: url, atomically: true, encoding: .utf8) }
    }
}

private struct PresentedLogRow: View {
    let line: PresentedLogLine
    private var tint: Color {
        switch line.level { case .info: .blue; case .warning: .orange; case .error: .red }
    }
    var body: some View {
        // top, not baseline: the column rule has no baseline and pushed a wrapped message down
        HStack(alignment: .top, spacing: 12) {
            Text(line.time).frame(width: 106, alignment: .leading).foregroundStyle(.secondary)
            Label(line.level.shortLabel, systemImage: "circle.fill")
                .labelStyle(LogLevelLabelStyle()).foregroundStyle(tint).frame(width: 74, alignment: .leading)
            Text(line.source).lineLimit(1).truncationMode(.tail)
                .frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
            Divider()
            Text(LogPresentationParser.softBreaks(line.message))
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(line.level == .error ? Color.red.opacity(0.045) : .clear)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
        .accessibilityElement(children: .combine)
    }
}

private struct LogLevelLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 7)); configuration.title }
    }
}
