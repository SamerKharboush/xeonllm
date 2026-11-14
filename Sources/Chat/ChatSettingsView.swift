// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum ChatSettingsDestination: Hashable {
    case general, sampling, agents, advanced, mcp
}

struct ChatSettingsView: View {
    @EnvironmentObject private var loc: Localizer
    @State private var destination: ChatSettingsDestination = .general

    var body: some View {
        VStack(spacing: 0) {
            navigation
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            content
        }
    }

    private var navigation: some View {
        HStack(spacing: 14) {
            GlassSegmentedControl(selection: $destination, segments: [
                .init(value: .general, title: AppInfo.branded("General"), systemImage: "bubble.left.and.bubble.right"),
                .init(value: .sampling, title: AppInfo.branded("Sampling"), systemImage: "dial.medium"),
                .init(value: .agents, title: AppInfo.branded("Agents"), systemImage: "hammer"),
                .init(value: .advanced, title: AppInfo.branded("Advanced"), systemImage: "slider.horizontal.3"),
                .init(value: .mcp, title: "MCP", systemImage: "point.3.connected.trianglepath.dotted")
            ])
            Spacer(minLength: 16)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().opacity(0.65)
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 0) {
                    form.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if proxy.size.width >= 930 {
                        Divider().opacity(0.65)
                        SettingsCategoryGuide(content: guideContent)
                            .frame(width: 340)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .background(WorkspaceStyle.surface.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(WorkspaceStyle.border)
            .allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var panelHeader: some View {
        HStack(spacing: 12) {
            SectionGlyph(systemName: panelCopy.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(panelCopy.title).font(.headline)
                Text(panelCopy.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if destination == .mcp {
                    MCPSettingsSection()
                } else {
                    ChatAdvancedSettingsSection(destination: destination)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var panelCopy: (icon: String, title: String, subtitle: String) {
        switch destination {
        case .general:
            return ("bubble.left.and.bubble.right", AppInfo.branded("Conversation"),
                    AppInfo.branded("Chat behavior, text, and system prompt."))
        case .sampling:
            return ("dial.medium", AppInfo.branded("Sampling"),
                    AppInfo.branded("How the model picks each word."))
        case .agents:
            return ("hammer", AppInfo.branded("Agents and attachments"),
                    AppInfo.branded("Tools, memory, and files the model can use."))
        case .advanced:
            return ("slider.horizontal.3", AppInfo.branded("Advanced"),
                    AppInfo.branded("Custom requests for the engine."))
        case .mcp:
            return ("point.3.connected.trianglepath.dotted", "MCP",
                    AppInfo.branded("External tool servers."))
        }
    }

    private var guideContent: SettingsGuideContent {
        switch destination {
        case .general:
            return .init(icon: "bubble.left.and.bubble.right",
                         title: AppInfo.branded("Tune your conversation"),
                         detail: AppInfo.branded("Control how the chat behaves, how the text looks, and what instructions the model gets by default."),
                         note: AppInfo.branded("Changes apply to the next message you send."),
                         items: [
                            .init(icon: "arrow.down.right.and.arrow.up.left", title: AppInfo.branded("Context"),
                                  detail: AppInfo.branded("Summarize old turns to keep talking.")),
                            .init(icon: "textformat.size", title: AppInfo.branded("Reading"),
                                  detail: AppInfo.branded("Chat text size.")),
                            .init(icon: "text.quote", title: AppInfo.branded("Instructions"),
                                  detail: AppInfo.branded("System prompt for every chat.")),
                            .init(icon: "clock.arrow.circlepath", title: AppInfo.branded("History"),
                                  detail: AppInfo.branded("Delete every conversation."))
                         ])
        case .sampling:
            return .init(icon: "dial.medium",
                         title: AppInfo.branded("How the model writes"),
                         detail: AppInfo.branded("These values decide how much the model gambles on each word and how much it repeats itself."),
                         note: AppInfo.branded("If something goes wild, reset to defaults in Advanced."),
                         items: [
                            .init(icon: "dial.medium", title: AppInfo.branded("Sampling"),
                                  detail: AppInfo.branded("Top P, Min P, Top K, and seed.")),
                            .init(icon: "arrow.uturn.backward", title: AppInfo.branded("Penalties"),
                                  detail: AppInfo.branded("Keep it from repeating.")),
                            .init(icon: "thermometer.medium", title: AppInfo.branded("Temperature"),
                                  detail: AppInfo.branded("Dynamic range and XTC.")),
                            .init(icon: "waveform.path", title: "DRY",
                                  detail: AppInfo.branded("Cuts long text loops."))
                         ])
        case .agents:
            return .init(icon: "hammer",
                         title: AppInfo.branded("What the model can do"),
                         detail: AppInfo.branded("Tools to read files, run code, and remember what was said, plus how attachments are handled."),
                         note: AppInfo.branded("Every sensitive operation asks for permission first."),
                         items: [
                            .init(icon: "hammer", title: AppInfo.branded("Tools"),
                                  detail: AppInfo.branded("Read, edit, and run.")),
                            .init(icon: "shippingbox", title: AppInfo.branded("Isolation"),
                                  detail: AppInfo.branded("Run them off your Mac.")),
                            .init(icon: "brain.head.profile", title: AppInfo.branded("Memory"),
                                  detail: AppInfo.branded("Archive and recall turns.")),
                            .init(icon: "paperclip", title: AppInfo.branded("Attachments"),
                                  detail: AppInfo.branded("Images and PDFs you send."))
                         ])
        case .advanced:
            return .init(icon: "slider.horizontal.3",
                         title: AppInfo.branded("For specific cases"),
                         detail: AppInfo.branded("Override the parameters with your own JSON and connect MCP servers to extend the chat's tools."),
                         note: AppInfo.branded("Invalid JSON is ignored until you fix it."),
                         items: [
                            .init(icon: "curlybraces", title: AppInfo.branded("Request"),
                                  detail: AppInfo.branded("JSON that wins over the rest.")),
                            .init(icon: "arrow.counterclockwise", title: AppInfo.branded("Reset"),
                                  detail: AppInfo.branded("Back to the defaults."))
                         ])
        case .mcp:
            return .init(icon: "point.3.connected.trianglepath.dotted",
                         title: AppInfo.branded("Tools from other servers"),
                         detail: AppInfo.branded("Connect MCP servers so the chat can use their tools alongside the local ones."),
                         note: AppInfo.branded("MCP tools ask for permission just like local ones."),
                         items: [
                            .init(icon: "plus.circle", title: AppInfo.branded("Servers"),
                                  detail: AppInfo.branded("Add one by its address.")),
                            .init(icon: "key", title: AppInfo.branded("Credentials"),
                                  detail: AppInfo.branded("Stored in the Keychain.")),
                            .init(icon: "hammer", title: AppInfo.branded("Tools"),
                                  detail: AppInfo.branded("Added to the chat's own.")),
                            .init(icon: "lock.shield", title: AppInfo.branded("Permissions"),
                                  detail: AppInfo.branded("Per-call authorization."))
                         ])
        }
    }
}
