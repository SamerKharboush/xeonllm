// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ChatAdvancedSettingsSection: View {
    let destination: ChatSettingsDestination

    @EnvironmentObject private var loc: Localizer
    @AppStorage(SettingsKeys.chatAutoCompact) private var autoCompact = true
    @AppStorage(SettingsKeys.smoothTyping) private var smoothTyping = true
    @AppStorage(SettingsKeys.agentToolsEnabled) private var agentToolsEnabled = false
    @AppStorage(SettingsKeys.toolsRuntime) private var toolsRuntime = ""
    @AppStorage(SettingsKeys.jsSandboxEnabled) private var jsSandboxEnabled = false
    @AppStorage(SettingsKeys.sympyEnabled) private var sympyEnabled = false
    @AppStorage(SettingsKeys.scientificEnabled) private var scientificEnabled = false
    @AppStorage(SettingsKeys.mathAgentEnabled) private var mathAgentEnabled = false
    @AppStorage(SettingsKeys.mathToolsAllowed) private var mathToolsAllowed = true
    @AppStorage(SettingsKeys.memoryToolsEnabled) private var memoryToolsEnabled = true
    @AppStorage(SettingsKeys.chatMapToolEnabled) private var chatMapToolEnabled = true
    @AppStorage(SettingsKeys.chatRoadRouteEnabled) private var chatRoadRouteEnabled = true
    @AppStorage(SettingsKeys.mapStyle) private var mapStyle = ""
    @AppStorage(SettingsKeys.mapFolder) private var mapFolder = ""
    @AppStorage(SettingsKeys.toolResultLimit) private var toolResultLimit = ToolResultLimit.defaultCharacters
    @State private var blockedToolModels: [String] = ToolSupport.blockedModels
    @AppStorage(SettingsKeys.memoryArchiveHookURL) private var archiveHookURL = ""
    @AppStorage(SettingsKeys.memoryArchiveHookSecret) private var archiveHookSecret = ""
    @AppStorage(SettingsKeys.chatSystem) private var systemPrompt = ""
    @AppStorage(SettingsKeys.chatTopP) private var topP = 0.95
    @AppStorage(SettingsKeys.chatMinP) private var minP = 0.05
    @AppStorage(SettingsKeys.chatTopK) private var topK = 40
    @AppStorage(SettingsKeys.chatRepeatPenalty) private var repeatPenalty = 1.0
    @AppStorage(SettingsKeys.chatRepeatLastN) private var repeatLastN = 64
    @AppStorage(SettingsKeys.chatSeed) private var seed = -1
    @AppStorage(SettingsKeys.chatDynatempRange) private var dynatempRange = 0.0
    @AppStorage(SettingsKeys.chatDynatempExponent) private var dynatempExponent = 1.0
    @AppStorage(SettingsKeys.chatXTCProbability) private var xtcProbability = 0.0
    @AppStorage(SettingsKeys.chatXTCThreshold) private var xtcThreshold = 0.1
    @AppStorage(SettingsKeys.chatTypicalP) private var typicalP = 1.0
    @AppStorage(SettingsKeys.chatPresencePenalty) private var presencePenalty = 0.0
    @AppStorage(SettingsKeys.chatFrequencyPenalty) private var frequencyPenalty = 0.0
    @AppStorage(SettingsKeys.chatDryMultiplier) private var dryMultiplier = 0.0
    @AppStorage(SettingsKeys.chatDryBase) private var dryBase = 1.75
    @AppStorage(SettingsKeys.chatDryAllowedLength) private var dryAllowedLength = 2
    @AppStorage(SettingsKeys.chatDryPenaltyLastN) private var dryPenaltyLastN = 0
    @AppStorage(SettingsKeys.chatSamplers) private var samplers = ""
    @AppStorage(SettingsKeys.chatBackendSampling) private var backendSampling = false
    @AppStorage(SettingsKeys.chatCustomJSON) private var customJSON = ""
    @AppStorage(SettingsKeys.chatAgenticMaxTurns) private var agenticMaxTurns = 10
    @AppStorage(SettingsKeys.chatPasteLongTextLength) private var pasteLongTextLength = 2500
    @AppStorage(SettingsKeys.chatMaxImageMegapixels) private var maxImageMegapixels = 1.0
    @AppStorage(SettingsKeys.chatPDFAsImages) private var pdfAsImages = false
    @AppStorage(SettingsKeys.chatFontScale) private var chatFontScale = 1.0
    @State private var confirmDeleteAll = false
    @State private var promptExpanded = true
    @State private var samplingExpanded = true
    @State private var penaltiesExpanded = false
    @State private var dynamicExpanded = false
    @State private var dryExpanded = false
    @State private var agentsExpanded = false
    @State private var customExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if destination == .general {
            SettingsRowGroup {
                SettingsRow(icon: "arrow.down.right.and.arrow.up.left",
                            title: AppInfo.branded("Auto-compact long conversations"),
                            help: AppInfo.branded("When the conversation nears the context limit, older messages are summarized automatically so it can keep answering without losing the thread.")) {
                    SettingsToggle(isOn: $autoCompact)
                }
                SettingsRow(icon: "text.cursor",
                            title: AppInfo.branded("Smooth typing animation"),
                            help: AppInfo.branded("Animates the text appearing token by token. Turn it off if you prefer text to appear at once or notice flicker.")) {
                    SettingsToggle(isOn: $smoothTyping)
                }
                SettingsRow(icon: "textformat.size",
                            title: AppInfo.branded("Chat text size"),
                            help: AppInfo.branded("Size of the messages and the input field, leaving the rest of the interface alone. Also ⌘+ and ⌘− from the chat, and ⌘0 to go back to 100%.")) {
                    HStack(spacing: 12) {
                        Slider(value: $chatFontScale, in: ChatFont.range, step: ChatFont.step)
                            .frame(width: 180)
                        Text("\(Int((chatFontScale * 100).rounded()))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 56, alignment: .trailing)
                    }
                    .frame(width: Self.controlColumn, alignment: .trailing)
                }
                SettingsRow(icon: "clock.arrow.circlepath",
                            title: AppInfo.branded("History"),
                            help: AppInfo.branded("This cannot be undone. Export first from the menu next to the chat search box if you want a copy.")) {
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label(AppInfo.branded("Delete all…"), systemImage: "trash")
                    }
                    .glassButton()
                    .tint(.red)
                }
            }
            }

            if destination == .general {
                ChatSettingsGroup(title: AppInfo.branded("Global system prompt")) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(AppInfo.branded("Permanent instructions for the model…"),
                              text: $systemPrompt, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(5...10)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .workspaceFieldSurface()
                    Text(AppInfo.branded("Used when neither the conversation nor its project has its own prompt."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }

            if destination == .sampling {
                ChatSettingsGroup(title: AppInfo.branded("Sampling")) {
                VStack(alignment: .leading, spacing: 12) {
                    parameterSlider("Top P", value: $topP, range: 0...1,
                                    help: AppInfo.branded("Nucleus sampling: only the most likely tokens whose probabilities sum to P are considered. 1.0 disables it; lower trims the unlikely tail."))
                    parameterSlider("Min P", value: $minP, range: 0...1,
                                    help: AppInfo.branded("Drops tokens whose probability is below this fraction of the top token's. A steadier alternative to Top P."))
                    parameterSlider("Typical P", value: $typicalP, range: 0...1,
                                    help: AppInfo.branded("Typical sampling: keeps tokens with information near the average, trimming the too-predictable and too-rare. 1.0 disables it."))
                    integerStepper("Top K", value: $topK, range: 0...200,
                                   help: AppInfo.branded("Limits the choice to the K most likely tokens at each step. 0 disables it."))
                    numberField(AppInfo.branded("Seed"), value: $seed,
                                help: AppInfo.branded("Random seed. -1 picks a new one each time; set a number for reproducible answers with the same parameters."))
                    SettingsRow(icon: "list.number",
                                title: AppInfo.branded("Sampler order"),
                                help: AppInfo.branded("Order the samplers are applied in, separated by ';'. Leave empty for the engine's default order.")) {
                        DeferredSettingsTextField("", text: $samplers,
                                                  prompt: "top_k;typ_p;top_p;min_p;temperature",
                                                  width: Self.controlColumn)
                    }
                    SettingsRow(icon: "cpu",
                                title: AppInfo.branded("Backend sampling"),
                                help: AppInfo.branded("Runs sampling on the GPU instead of the CPU. Can be faster, but not every sampler (XTC, DRY) is supported on the backend.")) {
                        SettingsToggle(isOn: $backendSampling)
                    }
                }
            }
            }

            if destination == .sampling {
                ChatSettingsGroup(title: AppInfo.branded("Penalties")) {
                VStack(alignment: .leading, spacing: 12) {
                    parameterSlider(AppInfo.branded("Repeat"), value: $repeatPenalty, range: 0.5...2,
                                    help: AppInfo.branded("Penalizes repeating tokens already used. 1.0 disables it; above that reduces repetition, too high hurts coherence."))
                    parameterSlider(AppInfo.branded("Presence"), value: $presencePenalty, range: -2...2,
                                    help: AppInfo.branded("Penalizes a token for having appeared at all, regardless of count. Positive encourages new topics; negative repeats them."))
                    parameterSlider(AppInfo.branded("Frequency"), value: $frequencyPenalty, range: -2...2,
                                    help: AppInfo.branded("Penalizes a token in proportion to how many times it already appeared. Positive reduces filler; negative favors it."))
                    integerStepper(AppInfo.branded("Repeat window"),
                                   value: $repeatLastN, range: 0...4096, step: 16,
                                   help: AppInfo.branded("How many recent tokens the repetition penalties look at. 0 disables it."))
                }
            }
            }

            if destination == .sampling {
                ChatSettingsGroup(title: AppInfo.branded("Dynamic temperature and XTC")) {
                VStack(alignment: .leading, spacing: 12) {
                    parameterSlider(AppInfo.branded("Dynamic range"), value: $dynatempRange, range: 0...2,
                                    help: AppInfo.branded("Dynamic temperature: varies temperature per token by the model's certainty. 0 keeps it fixed."))
                    parameterSlider(AppInfo.branded("Dynamic exponent"), value: $dynatempExponent, range: 0.1...4,
                                    help: AppInfo.branded("Dynamic temperature curve: higher values focus the change on the most uncertain steps."))
                    parameterSlider(AppInfo.branded("XTC probability"), value: $xtcProbability, range: 0...1,
                                    help: AppInfo.branded("Chance of applying XTC at each step, which removes high-probability tokens for more creative output. 0 disables it."))
                    parameterSlider(AppInfo.branded("XTC threshold"), value: $xtcThreshold, range: 0...1,
                                    help: AppInfo.branded("Minimum probability threshold for XTC to consider removing a token. Only active when XTC probability > 0."))
                }
            }
            }

            if destination == .sampling {
                ChatSettingsGroup(title: "DRY") {
                VStack(alignment: .leading, spacing: 12) {
                    parameterSlider(AppInfo.branded("Multiplier"), value: $dryMultiplier, range: 0...2,
                                    help: AppInfo.branded("Strength of the DRY penalty, which breaks repetition of whole sequences. 0 disables it."))
                    parameterSlider(AppInfo.branded("Base"), value: $dryBase, range: 1...3,
                                    help: AppInfo.branded("Base of the DRY penalty's exponential growth with the length of the repeated sequence."))
                    integerStepper(AppInfo.branded("Allowed length"),
                                   value: $dryAllowedLength, range: 0...32,
                                   help: AppInfo.branded("Length of repeated sequence tolerated before DRY starts penalizing."))
                    integerStepper(AppInfo.branded("Window"), value: $dryPenaltyLastN,
                                   range: 0...32768, step: 64,
                                   help: AppInfo.branded("How many recent tokens DRY scans. 0 disables it."))
                }
            }
            }

            if destination == .agents {
                ChatSettingsGroup(title: AppInfo.branded("Tools")) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow(icon: "hammer",
                                title: AppInfo.branded("Local agent tools"),
                                help: AppInfo.branded("Lets the model read or edit files and run commands via tools. Every sensitive operation asks for permission.")) {
                        SettingsToggle(isOn: $agentToolsEnabled)
                    }
                    if agentToolsEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(AppInfo.branded("Tools can modify files or run commands; every sensitive operation requests permission."),
                                  systemImage: "exclamationmark.shield.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(AppInfo.branded("Revoke persistent permissions"),
                                   systemImage: "lock.rotation", action: ChatToolsService.revokeAllPermissions)
                                .glassButton()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        SettingsRow(icon: "shippingbox",
                                    title: AppInfo.branded("Isolate tools in"),
                                    help: AppInfo.branded("Runs the tools off your Mac, in a container or over SSH, so they cannot touch your files. Formats: docker:image, podman:image, docker-container:id, ssh:target. Empty runs them right here.")) {
                            DeferredSettingsTextField("", text: $toolsRuntime,
                                                      prompt: "docker:alpine", width: 220)
                        }
                    }
                    SettingsRow(icon: "curlybraces",
                                title: AppInfo.branded("JavaScript sandbox for agents"),
                                help: AppInfo.branded("Adds a tool that runs JavaScript in a sandbox for calculations or data transforms.")) {
                        SettingsToggle(isOn: $jsSandboxEnabled)
                    }
                    if SymPyToolsService.runtimeDirectory() != nil {
                        SettingsRow(icon: "function",
                                    title: AppInfo.branded("Symbolic math (SymPy)"),
                                    help: AppInfo.branded("Adds exact math tools: simplify, solve equations, differentiate, integrate, matrices and checking results. It ships inside the app, runs no code from the model and writes no files. Off, it uses nothing; on, the engine keeps a small helper process and SymPy loads only when used. Applies when the server restarts.")) {
                            SettingsToggle(isOn: $sympyEnabled)
                        }
                        SettingsRow(icon: "waveform.path.ecg",
                                    title: AppInfo.branded("Scientific computing (NumPy and SciPy)"),
                                    help: AppInfo.branded("Adds numerical tools: linear algebra, integration, optimization, curve fitting, FFT and filters, differential equations and statistics. It ships inside the app, runs no code from the model and neither reads nor writes files. Off, it uses nothing; on, the libraries load only when used and compute on a single thread so the model is not slowed down. Applies when the server restarts.")) {
                            SettingsToggle(isOn: $scientificEnabled)
                        }
                        if sympyEnabled || scientificEnabled {
                            SettingsRow(icon: "checkmark.shield",
                                        title: AppInfo.branded("Use the math tools without asking"),
                                        help: AppInfo.branded("The math tools only compute: they neither read nor write files nor run commands. This way the Xeon agent in the engine runs these turns with all its checks. Off, the chat asks before each call and runs the turn itself, with the same rules. It does not change the permissions of any other tool.")) {
                                SettingsToggle(isOn: $mathToolsAllowed)
                            }
                            SettingsRow(icon: "server.rack",
                                        title: AppInfo.branded("Answer with the tools over the API"),
                                        help: AppInfo.branded("The Xeon agent, the one this chat and the web chat use, also answers /v1/chat/completions clients that do not ask for it with the X-Xeon-Agent: on header, also remotely and without the app. Requests that bring tools of their own (VS Code, agents) or X-Xeon-Agent: off still go to the model as they are. Applies when the server restarts.")) {
                                SettingsToggle(isOn: $mathAgentEnabled)
                            }
                        }
                    }
                    integerStepper(AppInfo.branded("Maximum agent turns"),
                                   value: $agenticMaxTurns, range: 1...100,
                                   help: AppInfo.branded("Maximum tool→response rounds the agent chains in one turn before stopping."))
                    integerStepper(AppInfo.branded("Tool result limit"),
                                   icon: "scissors",
                                   value: $toolResultLimit, range: 0...200_000, step: 5_000,
                                   zeroLabel: AppInfo.branded("None"),
                                   help: AppInfo.branded("Characters of each tool result that reach the model. Longer results send the beginning and the end with a note of what was cut; the tool card still shows the whole result. Keeps one web page or large listing from filling the context. 0 sends it whole."))
                    if !blockedToolModels.isEmpty {
                        SettingsRow(icon: "hammer.slash",
                                    title: AppInfo.branded("Models without tools"),
                                    help: AppInfo.branded("Models that wrote a call in the wrong shape, so the engine stopped the answer and they stopped receiving tools. Remove one to offer them again.")) {
                            EmptyView()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(blockedToolModels, id: \.self) { model in
                                HStack(spacing: 8) {
                                    Text((model as NSString).lastPathComponent)
                                        .font(.callout)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(model)
                                    Spacer(minLength: 8)
                                    Button {
                                        ToolSupport.unblock(model)
                                        blockedToolModels = ToolSupport.blockedModels
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(AppInfo.branded("Offer tools to it again"))
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onAppear { blockedToolModels = ToolSupport.blockedModels }
            }

            if destination == .agents {
                ChatSettingsGroup(title: AppInfo.branded("Memory")) {
                    SettingsRow(icon: "brain.head.profile",
                                title: AppInfo.branded("Conversation memory"),
                                help: AppInfo.branded("Gives the model three tools to manage its own context: list the conversation, archive what is finished and recall it when it matters again. Turn it off if you use an external memory server and the model confuses the two.")) {
                        SettingsToggle(isOn: $memoryToolsEnabled)
                    }
                    if memoryToolsEnabled {
                        SettingsRow(icon: "paperplane",
                                    title: AppInfo.branded("Send archived turns to"),
                                    help: AppInfo.branded("Every time the model archives turns they are posted to this address as JSON, so an external index can keep them. Empty turns it off. Deliveries are stored on disk and retried, so a receiver that is down loses nothing and does not hold up the chat.")) {
                            DeferredSettingsTextField("", text: $archiveHookURL,
                                                      prompt: "https://127.0.0.1:8000/hook", width: 220)
                                .autocorrectionDisabled()
                        }
                        SettingsRow(icon: "key",
                                    title: AppInfo.branded("Receiver token (optional)"),
                                    help: AppInfo.branded("Sent as Authorization: Bearer with each delivery, for receivers that ask for one.")) {
                            DeferredSettingsTextField("", text: $archiveHookSecret, width: 220)
                                .autocorrectionDisabled()
                        }
                    }
                }
            }

            if destination == .agents {
                ChatSettingsGroup(title: AppInfo.branded("Map")) {
                    SettingsRow(icon: "map",
                                title: AppInfo.branded("Map in the chat"),
                                help: AppInfo.branded("Gives the model a tool to draw points, lines and areas on a map under its answer. What it draws is dashed and marked as approximate positions, since the model may estimate the coordinates; maps of data an agent returns, such as a GIS service's, are unchanged.")) {
                        SettingsToggle(isOn: $chatMapToolEnabled)
                    }
                    if chatMapToolEnabled {
                        SettingsRow(icon: "car",
                                    title: AppInfo.branded("Road routes (Apple Maps)"),
                                    help: AppInfo.branded("When you ask for a route by road, the app asks your permission to send the points to Apple Maps over the internet, and draws the real route with its distance and time. Without your permission, or with this off, the model draws a straight line and says so.")) {
                            SettingsToggle(isOn: $chatRoadRouteEnabled)
                        }
                    }
                    SettingsRow(icon: "square.3.layers.3d",
                                title: AppInfo.branded("Base map style"),
                                help: AppInfo.branded("Address of a MapLibre style (style.json) for the background of maps, in the app and in the web chat. Empty uses OpenFreeMap over the internet, and none draws a plain background without connecting. Road routes are always drawn on Apple Maps.")) {
                        DeferredSettingsTextField("", text: $mapStyle, prompt: "OpenFreeMap", width: 220)
                            .autocorrectionDisabled()
                    }
                    SettingsRow(icon: "externaldrive",
                                title: AppInfo.branded("Offline maps"),
                                subtitle: mapFolder.isEmpty ? nil : mapFolder,
                                help: AppInfo.branded("Folder with regions in PMTiles format, like the ones Protomaps publishes. When it holds any, the background of maps is drawn from them without internet, in the web chat too, and over the style. Place names need the fonts in an assets subfolder; without it the map shows no labels.")) {
                        HStack(spacing: 8) {
                            if !mapFolder.isEmpty {
                                Button(AppInfo.branded("Remove")) { mapFolder = "" }
                                    .glassButton()
                                    .help(AppInfo.branded("Goes back to the online map."))
                            }
                            Button(AppInfo.branded("Choose…")) { chooseMapFolder() }
                                .glassButton()
                                .help(AppInfo.branded("Choose the folder of regions."))
                        }
                    }
                }
            }

            if destination == .agents {
                ChatSettingsGroup(title: AppInfo.branded("Attachments")) {
                    integerStepper(AppInfo.branded("Paste text to file"),
                                   value: $pasteLongTextLength, range: 0...100_000, step: 500,
                                   zeroLabel: AppInfo.branded("Off"),
                                   help: AppInfo.branded("If you paste text longer than this (in characters), it becomes an attachment instead of filling the input box. 0 disables it."))
                    LabeledContent(AppInfo.branded("Maximum image size (MP)")) {
                        HStack(spacing: 8) {
                            DeferredNumberField("1", value: $maxImageMegapixels, width: 90)
                                .onChange(of: maxImageMegapixels) { _, value in
                                    let clamped = min(4, max(0.25, value))
                                    if clamped != value { maxImageMegapixels = clamped }
                                }
                            InfoTip(text: AppInfo.branded("Downsizes attached images to this megapixel maximum before sending, to save vision tokens (0.25–4)."))
                        }
                    }
                    SettingsRow(icon: "doc.richtext",
                                title: AppInfo.branded("PDF as images for vision models"),
                                help: AppInfo.branded("Sends each PDF page as an image to the vision model instead of extracting its text. Useful for scanned or diagram-heavy PDFs.")) {
                        SettingsToggle(isOn: $pdfAsImages)
                    }
                }
            }
            }

            if destination == .advanced {
                ChatSettingsGroup(title: AppInfo.branded("Custom request")) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(AppInfo.branded("JSON object that overrides parameters…"),
                              text: $customJSON, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(5...10)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .workspaceFieldSurface()
                    if customJSONInvalid {
                        Label(AppInfo.branded("Invalid JSON: it must be an object {…}. It will be ignored until fixed."),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Text(AppInfo.branded("Valid JSON overrides the parameters above for each request."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }

            if destination == .advanced {
                Button(AppInfo.branded("Reset advanced chat settings"),
                       systemImage: "arrow.counterclockwise", action: reset)
                    .buttonStyle(GlassPillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            AppInfo.branded("Delete all conversations?"),
            isPresented: $confirmDeleteAll, titleVisibility: .visible
        ) {
            Button(AppInfo.branded("Delete all"), role: .destructive) {
                // the chat window owns the store and can be closed while this one stays open
                if let store = ChatStore.live { store.deleteAll() } else { ChatStore.eraseStoredConversations() }
            }
            Button(AppInfo.branded("Cancel"), role: .cancel) {}
        } message: {
            Text(AppInfo.branded("This cannot be undone. Your projects and their prompts are kept."))
        }
    }

    private var customJSONInvalid: Bool {
        let trimmed = customJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] else { return true }
        return false
    }

    /// Every row ends its control in the same column, so sliders, steppers and
    /// fields do not each stop at a different place.
    private static let controlColumn: CGFloat = 250

    private func parameterSlider(_ title: String, icon: String = "dial.medium",
                                 value: Binding<Double>,
                                 range: ClosedRange<Double>, help: String) -> some View {
        SettingsRow(icon: icon, title: title, help: help) {
            HStack(spacing: 12) {
                Slider(value: value, in: range).frame(width: 180)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 56, alignment: .trailing)
            }
            .frame(width: Self.controlColumn, alignment: .trailing)
        }
    }

    private func integerStepper(_ title: String, icon: String = "number",
                                value: Binding<Int>, range: ClosedRange<Int>,
                                step: Int = 1, zeroLabel: String? = nil, help: String) -> some View {
        SettingsRow(icon: icon, title: title, help: help) {
            HStack(spacing: 10) {
                Text(value.wrappedValue == 0 ? (zeroLabel ?? "0") : value.wrappedValue.formatted())
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 56, alignment: .trailing)
                Stepper(title, value: value, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.regular)   // rows shrink their controls; steppers need the room
                    .fixedSize()
            }
            .frame(width: Self.controlColumn, alignment: .trailing)
        }
    }

    private func numberField(_ title: String, icon: String = "number",
                             value: Binding<Int>, help: String) -> some View {
        SettingsRow(icon: icon, title: title, help: help) {
            DeferredNumberField(title, value: value, width: 100)
                .frame(width: Self.controlColumn, alignment: .trailing)
        }
    }

    private func chooseMapFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = AppInfo.branded("Choose")
        if panel.runModal() == .OK, let url = panel.url { mapFolder = url.path }
    }

    private func reset() {
        topP = 0.95; minP = 0.05; topK = 40; repeatPenalty = 1; repeatLastN = 64; seed = -1
        dynatempRange = 0; dynatempExponent = 1; xtcProbability = 0; xtcThreshold = 0.1
        typicalP = 1; presencePenalty = 0; frequencyPenalty = 0; dryMultiplier = 0
        dryBase = 1.75; dryAllowedLength = 2; dryPenaltyLastN = 0; samplers = ""
        backendSampling = false; customJSON = ""; agenticMaxTurns = 10; pasteLongTextLength = 2500
        maxImageMegapixels = ProductDefaults.double(SettingsKeys.chatMaxImageMegapixels, or: 1)
        pdfAsImages = ProductDefaults.bool(SettingsKeys.chatPDFAsImages, or: false)
        autoCompact = true; smoothTyping = true; agentToolsEnabled = false; jsSandboxEnabled = false
        sympyEnabled = false; scientificEnabled = false; mathAgentEnabled = false; mathToolsAllowed = true
        memoryToolsEnabled = true; toolsRuntime = ""; toolResultLimit = ToolResultLimit.defaultCharacters
        archiveHookURL = ""; archiveHookSecret = ""
    }
}
