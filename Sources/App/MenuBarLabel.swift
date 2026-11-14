// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The menu bar glyph. Its own view so the VRAM sample and the server state
/// invalidate this label alone, not the whole scene.
struct MenuBarLabel: View {
    @ObservedObject var server: ServerController
    @ObservedObject var vram: VRAMMonitor
    @ObservedObject var loc: Localizer
    @AppStorage(SettingsKeys.menuBarGPU) private var menuBarGPU = "panel"

    /// A crashed engine used to look exactly like a stopped one from here, which is
    /// the one state worth noticing from another app.
    private var iconName: String {
        switch server.state {
        case .running:  return "cpu.fill"
        case .starting: return "cpu.badge.clock"
        case .failed:   return "exclamationmark.triangle.fill"
        case .stopped:  return "cpu"
        }
    }

    private var stateLabel: String {
        switch server.state {
        case .running:  return AppInfo.branded("XeonLLM: server running")
        case .starting: return AppInfo.branded("XeonLLM: starting")
        case .failed:   return AppInfo.branded("XeonLLM: the engine failed")
        case .stopped:  return AppInfo.branded("XeonLLM: server stopped")
        }
    }

    var body: some View {
        // "icon" mode shows aggregate VRAM next to the glyph; per-GPU bars
        // live in the panel.
        if menuBarGPU == "icon", vram.totalMB > 0 {
            Label("\(Int(vram.fraction * 100))%", systemImage: iconName)
        } else {
            Label(stateLabel, systemImage: iconName)
                .labelStyle(.iconOnly)
        }
    }
}
