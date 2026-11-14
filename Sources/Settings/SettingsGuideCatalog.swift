// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Copy for the panel beside each settings category.
extension SettingsDestination {
    func guideContent(_ loc: Localizer) -> SettingsGuideContent {
        let copy = guideCopy(loc)
        return SettingsGuideContent(icon: copy.icon, title: copy.title,
                                    detail: copy.detail, note: copy.note,
                                    items: guideItems(loc))
    }

    func guideItems(_ loc: Localizer) -> [SettingsGuideItem] {
        switch self {
        case .general:
            return [
                .init(icon: "desktopcomputer", title: AppInfo.branded("Interface"), detail: AppInfo.branded("Language, color, and menu bar.")),
                .init(icon: "gearshape", title: AppInfo.branded("Startup"), detail: AppInfo.branded("Launch, updates, and behavior.")),
                .init(icon: "shield", title: AppInfo.branded("Security"), detail: AppInfo.branded("Keep your API and data safe.")),
                .init(icon: "shippingbox", title: AppInfo.branded("Library"), detail: AppInfo.branded("Choose where your models live."))
            ]
        case .models:
            return [
                .init(icon: "doc.text", title: AppInfo.branded("Profiles"), detail: AppInfo.branded("Save configurations for reuse.")),
                .init(icon: "memorychip", title: "GPU", detail: AppInfo.branded("Choose a card or split the model.")),
                .init(icon: "externaldrive", title: AppInfo.branded("Memory"), detail: AppInfo.branded("Control VRAM, RAM, and caches.")),
                .init(icon: "point.3.connected.trianglepath.dotted", title: "Multi-GPU", detail: AppInfo.branded("Configure layers, tensors, and links."))
            ]
        case .inference:
            return [
                .init(icon: "text.document", title: AppInfo.branded("Context"), detail: AppInfo.branded("Set the token limit.")),
                .init(icon: "square.stack.3d.up", title: AppInfo.branded("KV cache"), detail: AppInfo.branded("Balance precision and memory.")),
                .init(icon: "bolt", title: "Flash Attention", detail: AppInfo.branded("Use the right kernel for your GPU.")),
                .init(icon: "arrow.triangle.branch", title: AppInfo.branded("Concurrency"), detail: AppInfo.branded("Control requests and chat templates."))
            ]
        case .speech:
            return [
                .init(icon: "mic", title: AppInfo.branded("Input"), detail: AppInfo.branded("Choose Apple Dictation or Whisper.")),
                .init(icon: "waveform", title: "Whisper.cpp", detail: AppInfo.branded("GPU-accelerated transcription.")),
                .init(icon: "arrow.down.circle", title: AppInfo.branded("Loading"), detail: AppInfo.branded("On demand or always available.")),
                .init(icon: "lock.shield", title: AppInfo.branded("Privacy"), detail: AppInfo.branded("Audio and text stay on your Mac."))
            ]
        case .advanced:
            return [
                .init(icon: "server.rack", title: AppInfo.branded("Engine"), detail: AppInfo.branded("Use the bundled or an external engine.")),
                .init(icon: "network", title: AppInfo.branded("API & network"), detail: AppInfo.branded("Configure port and local access.")),
                .init(icon: "point.3.connected.trianglepath.dotted", title: "Embeddings", detail: AppInfo.branded("Expose services for RAG clients.")),
                .init(icon: "terminal", title: AppInfo.branded("Diagnostics"), detail: AppInfo.branded("Additional arguments and logs."))
            ]
        case .extensions:
            return [
                .init(icon: "folder", title: AppInfo.branded("Folder"), detail: AppInfo.branded("Every subfolder with an extension.json is one extension.")),
                .init(icon: "checkmark.shield", title: AppInfo.branded("Approval"), detail: AppInfo.branded("Off until you approve them.")),
                .init(icon: "key", title: AppInfo.branded("Secrets"), detail: AppInfo.branded("Stored in the Keychain.")),
                .init(icon: "arrow.clockwise", title: AppInfo.branded("Apply"), detail: AppInfo.branded("When the server restarts."))
            ]
        }
    }

    func guideCopy(_ loc: Localizer) -> (icon: String, title: String, detail: String, note: String) {
        switch self {
        case .general:
            return ("paintbrush",
                    AppInfo.branded("Personalize your experience"),
                    AppInfo.branded("Adjust the interface, startup, security, and where your local library lives."),
                    AppInfo.branded("These settings affect the application and its startup behavior."))
        case .models:
            return ("memorychip",
                    AppInfo.branded("Models, GPU, and memory"),
                    AppInfo.branded("Save configurations and decide how weights, experts, and models load across your GPUs."),
                    AppInfo.branded("Engine changes take effect after restarting the server."))
        case .inference:
            return ("square.stack.3d.up",
                    AppInfo.branded("Inference and context"),
                    AppInfo.branded("Configure context, KV cache, Flash Attention, concurrency, and chat behavior."),
                    AppInfo.branded("Longer context and higher-precision caches require more RAM or VRAM."))
        case .speech:
            return ("waveform",
                    AppInfo.branded("Local voice, full control"),
                    AppInfo.branded("Configure audio input, Whisper loading, and the transcription profile."),
                    AppInfo.branded("Audio and text stay on this Mac."))
        case .advanced:
            return ("wrench.and.screwdriver",
                    AppInfo.branded("Services and engine"),
                    AppInfo.branded("Control the port, external engine, embeddings, persistent cache, and extra arguments."),
                    AppInfo.branded("Use extra arguments only when you know which llama.cpp option you need."))
        case .extensions:
            return ("puzzlepiece.extension",
                    AppInfo.branded("Extensions"),
                    AppInfo.branded("Add tools and agents to the engine from a folder of extensions, with their own settings."),
                    AppInfo.branded("An extension runs programs with your permissions: only turn on the ones you know."))
        }
    }
}
