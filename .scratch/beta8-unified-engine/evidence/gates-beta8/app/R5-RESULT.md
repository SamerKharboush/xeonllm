R5 — app gates, beta 8 (2026-11-13, Mocca)

Scope: specs/release-contract.md section 5 on dist/XeonLLM-v0.87.31-beta.8-noavx2.dmg
(sha256 ad679f5cb2341067af43ef960bbd064874a899b6c87b65de2ec64c0d3750a62b) and
dist/XeonLLM.app. Run-only; no source or script changed.

Evidence files (all under .scratch/beta8-unified-engine/evidence/gates-beta8/app/):
- git-sources-since-beta7.txt      git log + git status for Sources/Tests/Package.swift
- swift-test.log (provided)        swift-test-extract.txt (quoted lines)
- dmg-attach.txt, dmg-root.txt, dmg-background.txt, dmg-applications-symlink.txt,
  dmg-infoplist.txt, dmg-codesign.txt, dmg-detach.txt
- dsstore.bin, dsstore-parse.txt, dsstore-iloc.txt, parse_dsstore.py
- testapp-launch.txt, realchat-lfm3.json, realchat-lfm3.server.log,
  testapp-clean.txt, testapp-clean-confirm.txt
- diagreports-before.txt, diagreports-after.txt, diagreports-compare.txt
- missing-test-check.txt

1. swift test (no rerun)
------------------------
Sources unchanged since beta.7 (git log v0.87.31-beta.7..HEAD -- Sources Tests Package.swift
shows one commit, 59d6e09 "beta 8 R1: FA-AMD off switch ..."; git status --short Sources
Tests is empty).

Quote (swift-test-extract.txt, swift-test.log line 1323/1325):
  Executed 541 tests, with 16 tests skipped and 2 failures (1 unexpected) in 22.473 (22.592) seconds

Failing test (swift-test.log line 599):
  Test Case '-[XeonLLMTests.MCPStdioTransportTests testAnswersRacingTheirDeadlinesResolveEachRequestOnce]' failed (11.595 seconds).
  error: XCTAssertTrue failed - answers and deadlines did not both occur
  error: XCTAssertEqual failed: threw error "launchFailed(\"probe did not answer in time.\")"

That is the known MCPStdioTransportTests race named in section 5; no other failures.

Migration (IdentityMigrationTests, swift-test.log lines 448-467, all passed):
  testASecondRunChangesNothing / testASecondRunCopiesNothing (idempotence)
  testConversationsAndProjectsAreMergedByID (merge by id)
  testCopiesSettingsAndDataFolder
  testDoesNotOverwriteAnExistingSetting
  testFolderMergeRunsOnceForBeta5MigratedUsers (beta.5 users get the folder merge once)
  testKeychainItemsAreCopiedNotMovedOrOverwritten
  testMergesMissingItemsIntoAnExistingNewDataFolder (even if the XeonLLM folder exists)
  testNeverDeletesTheOldDataFolder
  testSkipsSystemStateKeys

Tool servers:
- login-shell PATH (UserShellPathTests, lines 1257-1262, all passed):
  testFallsBackSilentlyWhenTheShellFails
  testMergesTheLoginShellPathAndFixedExtras
  testReadsTheLoginShellOnlyOnce
- command-not-found reported by name: NO MATCHING TEST. The path exists in source
  (Sources/MCP/MCPStdioTransport.swift:35,41 throw MCPError.launchFailed with the command
  name) but no test case covers it (missing-test-check.txt: "tests mentioning
  not-found/launchFailed: none"). Whether the UI surfaces it by name is not covered by a test.

Remote MCP over HTTPS: NO MATCHING TEST for the HTTPS case. MCPRemoteOriginTests
(lines 573-590) are origin/redirect tests over the loopback http server (LoopbackHTTPServer),
and no test case exercises https/TLS; the only Test Case line mentioning https is
CompactionTests testStreamingErrorIsExtractedFromSuccessfulHTTPStream, which is unrelated.
SymPyToolsTests testAnApprovedRemoteServerReachesTheEngineThroughTheRelay and
EngineExtensionsTests testEntriesFillPlaceholdersFollowTheirSwitchAndRelayRemoteServers
cover the relay over http, not HTTPS. So "works or is refused with a user-visible message"
over HTTPS has no matching automated test.

2. Mounted DMG
--------------
Mount (dmg-attach.txt): hdiutil attach -readonly -nobrowse -mountpoint <tmp under $TMPDIR>
dist/XeonLLM-v0.87.31-beta.8-noavx2.dmg -> /dev/disk16 (Apple_APFS), mounted read-only.

Info.plist (dmg-infoplist.txt):
  "CFBundleIdentifier" => "dev.xeonllm.app"
  "CFBundleShortVersionString" => "0.87.31-beta.8"
  "CFBundleVersion" => "0.87.31-beta.8"
  "TOSHNoAVX2" => 1
  "TOSHUpdatesDisabled" => 1

codesign (dmg-codesign.txt): verify-ok  (codesign --verify --deep --strict on the mounted
XeonLLM.app, exit 0).

Volume root (dmg-root.txt): .background/, XeonLLM.app/, .VolumeIcon.icns, Applications ->
/Applications, .DS_Store. .background/ contains background.tiff (dmg-background.txt).
Applications symlink target (dmg-applications-symlink.txt): /Applications.

.DS_Store (dsstore.bin, parsed by parse_dsstore.py; dsstore-parse.txt, dsstore-iloc.txt):
  window bounds (bwsp): '{{200, 532}, {640, 428}}'  -> 640 x 428
  icon size (icvp): iconSize = 128.0
  XeonLLM.app (Iloc at 7175): x=165 y=194
  Applications (Iloc at 7121): x=475 y=194
  background bookmark (pBBk at 5563, alias): /Volumes/XeonLLM/.background/background.tiff
Issue 73 (beta.5) reference: 640 x 428 window, 128 px icons, XeonLLM.app (165,194),
Applications (475,194), pBBk -> /Volumes/XeonLLM/.background/background.tiff.
All identical in beta.8.

Detached (dmg-detach.txt): "disk16" ejected.

3. One real chat in the built app (test profile)
------------------------------------------------
testapp.sh launched the test copy (dev.xeonllm.gatetest, XeonLLMGateTest, port 18099);
health returned {"status":"ok"} on the first poll.
POST /v1/chat/completions (realchat-lfm3.json):
  "content": "The capital of France is Paris."   (finish_reason stop, temp 0)
Server log header (realchat-lfm3.server.log):
  XeonLLM 0.87.31-beta.8 — server start (x86_64 · no-AVX2 build)
  engine : bundled (official) · kernels fae2c1f1f84a
  args: -m /Users/sam/models/LFM3-1.7B-F16.gguf -ngl 99 -c 8192 ... --jinja ... --ubatch-size 128 ...
  engine banner: common_params_print_info: XeonLLM engine 0.87.31-beta.8 (app 0.87.31-beta.8)
Card lines: probed SIMD-group width = 64 (both D700s), wave64 decode ON, aligned mat-vec
reads ON (both cards); placement: card; TOSH_FA_AMD=1.
Clean (testapp-clean-confirm.txt): no process with the test app path remains, port 18099
closed, dev.xeonllm.gatetest gone, ~/Library/Application Support/XeonLLMGateTest removed.

Safety: DiagnosticReports name comparison (diagreports-compare.txt): comm -13 before/after
is empty — no new panic, watchdog or gpuRestart.

Not checked and why:
- Tool-server "command not found reported in the UI by name": no automated test; the
  message exists in source but the UI path is not exercised by a test case.
- Remote MCP over HTTPS: no test case uses TLS; only loopback http origin/relay tests exist.
- Migration gate was not exercised end-to-end on the user's real ToshLLM profile (the
  brief forbids touching the user's defaults/Application Support); the unit tests cover it.
- "swift test ... beyond the known MCPStdioTransportTests race": one failing test, which is
  the known race (2 failure assertions in one test); the log line counts 2 failures.

Gate table
----------
| gate | status | quoted evidence |
|---|---|---|
| swift test | PASS | "Executed 541 tests, with 16 tests skipped and 2 failures (1 unexpected) in 22.473 (22.592) seconds"; only failure is the known MCPStdioTransportTests race: "Test Case '-[XeonLLMTests.MCPStdioTransportTests testAnswersRacingTheirDeadlinesResolveEachRequestOnce]' failed (11.595 seconds)." |
| migration | PASS | IdentityMigrationTests all passed, e.g. "testKeychainItemsAreCopiedNotMovedOrOverwritten ... passed (0.118 seconds).", "testConversationsAndProjectsAreMergedByID ... passed (0.011 seconds).", "testASecondRunChangesNothing ... passed (0.010 seconds)." |
| tool servers | PARTIAL | login-shell PATH: "testMergesTheLoginShellPathAndFixedExtras ... passed (0.005 seconds)."; command-not-found by name: no matching test (missing-test-check.txt "none") |
| remote MCP (HTTPS) | PARTIAL | only http origin/relay tests: "testAnAnnouncedEndpointOnAnotherOriginReceivesNothing ... passed (0.060 seconds)."; no test uses https (grep "Test Case .*https": none) |
| DMG identity | PASS | "CFBundleIdentifier" => "dev.xeonllm.app"; "CFBundleShortVersionString" => "0.87.31-beta.8"; "TOSHNoAVX2" => 1; "TOSHUpdatesDisabled" => 1 |
| codesign | PASS | verify-ok |
| DMG layout | PASS | "WindowBounds = '{{200, 532}, {640, 428}}'"; "iconSize = 128.0"; "Iloc at 7175: size 16, x=165 y=194" (XeonLLM.app); "Iloc at 7121: size 16, x=475 y=194" (Applications); "path: /Volumes/XeonLLM/.background/background.tiff" |
| real chat | PASS | "content": "The capital of France is Paris."; server log: "XeonLLM engine 0.87.31-beta.8 (app 0.87.31-beta.8)"; clean: no test app process, port 18099 closed |

DiagnosticReports: before/after name sets identical (comm -13 empty); no new panic,
watchdog or gpuRestart.