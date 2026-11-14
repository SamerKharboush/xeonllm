// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct AudioVADCalibrationView: View {
    @EnvironmentObject private var loc: Localizer

    @AppStorage(SettingsKeys.audioVADMode) private var modeRaw = AudioVADMode.defaultMode.rawValue
    @AppStorage(SettingsKeys.audioVADProfile) private var profileRaw = AudioVADProfile.defaultProfile.rawValue
    @AppStorage(SettingsKeys.audioVADThreshold) private var threshold = 0.5
    @AppStorage(SettingsKeys.audioVADMinSpeechMS) private var minSpeechMS = 250.0
    @AppStorage(SettingsKeys.audioVADMinSilenceMS) private var minSilenceMS = 100.0
    @AppStorage(SettingsKeys.audioVADMaxSpeechSeconds) private var maxSpeechSeconds = 30.0
    @AppStorage(SettingsKeys.audioVADSpeechPadMS) private var speechPadMS = 80.0

    private var profile: AudioVADProfile {
        AudioVADProfile(rawValue: profileRaw) ?? .defaultProfile
    }

    private var mode: AudioVADMode {
        AudioVADMode(rawValue: modeRaw) ?? .defaultMode
    }

    private var calibration: AudioVADCalibration {
        if profile == .custom {
            .custom(threshold: threshold, minSpeechDurationMS: minSpeechMS,
                    minSilenceDurationMS: minSilenceMS,
                    maxSpeechDurationSeconds: maxSpeechSeconds,
                    speechPadMS: speechPadMS)
        } else {
            profile.calibration
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppInfo.branded("Voice detection")).font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $modeRaw) {
                    ForEach(AudioVADMode.allCases) { item in
                        Text(modeName(item)).tag(item.rawValue)
                    }
                }
                .labelsHidden()
                .help(AppInfo.branded("Disables VAD, uses Whisper.cpp native values, or applies a XeonLLM calibration."))
            }

            Text(modeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if mode == .calibrated {
                Picker(AppInfo.branded("Calibration"), selection: $profileRaw) {
                    ForEach(AudioVADProfile.allCases) { item in
                        Text(profileName(item)).tag(item.rawValue)
                    }
                }
                .help(AppInfo.branded("Changes how strongly a signal must resemble speech before it is sent to Whisper."))

                Text(profileDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if profile == .custom {
                    AudioVADCustomControls(
                        threshold: $threshold, minSpeechMS: $minSpeechMS,
                        minSilenceMS: $minSilenceMS,
                        maxSpeechSeconds: $maxSpeechSeconds, speechPadMS: $speechPadMS
                    )
                }

                LabeledContent(AppInfo.branded("Threshold")) {
                    Text(calibration.threshold,
                         format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                }
                .font(.caption)

                Label(AppInfo.branded("VAD reduces weak voices, but cannot isolate a main voice when background speech is also clearly audible."),
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(AppInfo.branded("Separating overlapping voices would require a different source-separation process."))
            }
        }
    }

    private var modeDescription: String {
        switch mode {
        case .disabled:
            AppInfo.branded("Whisper processes the complete audio, including silence.")
        case .standard:
            AppInfo.branded("Silero VAD uses Whisper.cpp defaults with no added calibration.")
        case .calibrated:
            AppInfo.branded("XeonLLM adjusts speech sensitivity and segmentation with the selected profile.")
        }
    }

    private func modeName(_ mode: AudioVADMode) -> String {
        switch mode {
        case .disabled: AppInfo.branded("Disabled")
        case .standard: AppInfo.branded("Whisper default")
        case .calibrated: AppInfo.branded("Calibrated")
        }
    }

    private var profileDescription: String {
        switch profile {
        case .sensitive:
            AppInfo.branded("Keeps quiet voices and brief fragments; may accept more background speech.")
        case .balanced:
            AppInfo.branded("Suitable for meetings and clean recordings.")
        case .strict:
            AppInfo.branded("Requires clearer, sustained speech; it does not separate background voices that remain intelligible.")
        case .custom:
            AppInfo.branded("Manual control over speech detection and segmentation.")
        }
    }

    private func profileName(_ profile: AudioVADProfile) -> String {
        switch profile {
        case .sensitive: AppInfo.branded("Sensitive")
        case .balanced: AppInfo.branded("Balanced")
        case .strict: AppInfo.branded("Strict")
        case .custom: AppInfo.branded("Custom")
        }
    }

}
