// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ToolPermissionCard: View {
    let request: PendingToolPermission
    let decide: (ToolPermissionDecision) -> Void
    @EnvironmentObject private var loc: Localizer
    @State private var showingArguments = false

    private var usesInternet: Bool { request.name == ChatRoadRoute.toolName }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: usesInternet ? "network" : request.writesData ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .foregroundStyle(usesInternet || request.writesData ? .orange : .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.displayName).font(.callout.weight(.semibold))
                    Text(usesInternet
                         ? AppInfo.branded("Sends the points to Apple Maps over the internet to find the road route. If you deny it, a straight line is drawn.")
                         : request.writesData
                         ? AppInfo.branded("Can modify files or run actions.")
                         : AppInfo.branded("Requests read access."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(AppInfo.branded("Show arguments"), systemImage: "chevron.down") {
                    showingArguments.toggle()
                }
                    .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            if showingArguments {
                Text(request.arguments.isEmpty ? "{}" : request.arguments)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
            }
            HStack {
                Button(AppInfo.branded("Deny"), role: .destructive) { decide(.deny) }
                Spacer()
                if request.serverID != nil {
                    Button(AppInfo.branded("Always this server")) { decide(.alwaysServer) }
                }
                Button(AppInfo.branded("Always allow")) { decide(.always) }
                Button(AppInfo.branded("Allow once")) { decide(.once) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.25)))
        .accessibilityElement(children: .contain)
    }
}
