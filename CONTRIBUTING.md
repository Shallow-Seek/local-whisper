# Contributing

Contribute focused fixes: transcription engines, grammar backends, mobile improvements, UI work, tests, and documentation.

## Development Setup

```bash
git clone https://github.com/gabrimatic/local-whisper.git
cd local-whisper
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
wh build   # builds the Swift UI app
```

Start the service:

```bash
wh start
wh log     # tail live output in another terminal
```

Requirements: Accessibility permission for the `wh` process (System Settings opens on first run) and Microphone access.

## Architecture

Python runs as a headless LaunchAgent service. Swift owns the macOS UI: menu bar, overlay, settings, and onboarding. They communicate over a Unix socket with newline-delimited JSON.

```
src/whisper_voice/
├── app.py                 # Headless service coordinator (7-mixin composition)
├── app_ipc.py             # IPCMixin: Swift socket push/pull, resync_audio routing
├── app_recording.py       # RecordingMixin: hotkey state machine
├── app_pipeline.py        # PipelineMixin: transcribe + grammar + replacements
├── app_commands.py        # CommandsMixin: wh whisper/listen/transcribe
├── app_switching.py       # SwitchingMixin: engine/backend switch with rollback
├── app_audio_health.py    # AudioHealthMixin: monitor heartbeat + post-wake resync
├── app_recovery.py        # RecoveryMixin: replay interrupted runs on startup
├── ipc_server.py          # Unix socket server for the Swift UI
├── cmd_server.py          # Unix socket server for the CLI
├── audio.py               # Recording + locked pre-buffer monitor stream
├── audio_processor.py     # VAD (+ hangover), noise reduction, adaptive gain
├── backup.py              # History persistence + disk-space guard
├── grammar.py             # Grammar backend factory wrapper
├── transcriber.py         # Engine routing
├── recovery.py            # processing.marker lifecycle
├── watchdog.py            # run_with_timeout per-stage wrapper
├── long_session.py        # Chunked long-session pipeline + JSONL persistence
├── dictation_commands.py  # "new line" / "period" / "scratch that" replacer
├── history_export.py      # wh export: Markdown / TXT / JSON renderers
├── stats.py               # wh stats: usage aggregation (raw-text trigger counts)
├── utils.py               # Helpers, logging, notifications
├── shortcuts.py           # Text transformation shortcuts
├── key_interceptor.py     # CGEvent tap
├── tts_processor.py       # TTS shortcut handler (⌥T)
├── cli/                   # wh CLI package
│   ├── main.py            # Dispatcher and top-level commands
│   ├── lifecycle.py       # status (+uptime/RSS/pending)/start/stop
│   ├── build.py           # build/restart
│   ├── settings.py        # engine/backend/replace (incl. `replace import`)
│   ├── editor.py          # interactive config TUI
│   ├── client.py          # command socket client
│   ├── doctor.py          # doctor / doctor --fix / doctor --report / update
│   ├── doctor_report.py   # redacted markdown report renderer
│   ├── history.py         # cmd_export / cmd_stats
│   └── constants.py       # shared constants
├── config/                # Config package (loader, schema, mutations)
│   ├── schema.py          # 17 dataclasses + DEFAULT_CONFIG TOML
│   ├── loader.py          # load_config, get_config, registry-driven validation
│   ├── toml_helpers.py    # TOML section read/write primitives
│   └── mutations.py       # add/remove replacement, update field
├── tts/
│   ├── base.py            # TTSProvider base
│   └── kokoro_tts.py      # Kokoro provider (MLX)
├── engines/
│   ├── base.py            # TranscriptionEngine base
│   ├── parakeet.py        # Parakeet-TDT v3 (default, MLX)
│   ├── qwen3_asr.py       # Qwen3-ASR (MLX, English only)
│   └── whisperkit.py      # WhisperKit (local server alternative)
└── backends/
    ├── base.py            # Backend base
    ├── modes.py           # Transformation modes
    ├── ollama/
    ├── lm_studio/
    └── apple_intelligence/
```

```
LocalWhisperUI/Sources/LocalWhisperUI/
├── AppMain.swift                  # @main entry, sleep/wake observer, onboarding presenter
├── AppState.swift                 # Observable state and IPC message handling
├── IPCClient.swift                # Unix socket connection
├── IPCMessages.swift              # Codable message types
├── MenuBarView.swift              # Menu bar dropdown
├── OverlayWindowController.swift  # Floating overlay panel
├── OverlayView.swift              # Recording, processing, and speaking pill
├── OnboardingView.swift           # First-launch and replay tutorial
├── SettingsView.swift             # Sidebar settings root
├── RecordingPanel.swift           # Trigger key and audio cleanup
├── TranscriptionPanel.swift       # Engine picker and per-engine parameters
├── GrammarPanel.swift             # Backend picker and local LLM settings
├── VoicePanel.swift               # TTS and dictation commands
├── VocabularyPanel.swift          # Replacements editor
├── OutputPanel.swift              # Overlay, sounds, notifications, paste, history
├── ShortcutsPanel.swift           # Text-transform keybindings
├── ActivityPanel.swift            # Usage stats
├── AdvancedPanel.swift            # Storage, logs, doctor, restart, update
├── AboutView.swift                # Version, credits, and replay tutorial
├── EngineSettingsSections.swift   # Shared engine setting controls
├── Theme.swift                    # Typography, spacing, tones, accents
├── SharedViews.swift              # Deferred fields, status pills, shared rows
└── Constants.swift                # App-wide constants
```

Key constraint: **lazy loading**. Backends, engines, and models initialize only when selected. Non-selected components stay uninitialized. If your change touches initialization paths, verify startup memory footprint has not increased.

Mobile lives in `src/flutter/local_whisper`. Flutter owns the shell, setup, history, modes, model management, settings, clipboard flow, and deterministic cleanup. Native iOS uses `ios/Runner/LocalSpeechBridge.swift` plus `ios/LocalWhisperKeyboard/`. Native Android uses `MainActivity.kt`, `LocalWhisperInputMethodService.kt`, `AndroidManifest.xml`, and Flutter-side sherpa-onnx transcription in `lib/src/sherpa_speech_service.dart`.

## New Grammar Backend

1. Create a folder under `src/whisper_voice/backends/<name>/` with `__init__.py` and `backend.py`.
2. Implement the `GrammarBackend` abstract class from `backends/base.py`.
3. Add an entry to `BACKEND_REGISTRY` in `backends/__init__.py`.
4. Done. The Grammar submenu, CLI, and Settings window all generate from the registry automatically.

Reference: `backends/ollama/`.

## New Transcription Engine

1. Create a file under `src/whisper_voice/engines/` implementing `TranscriptionEngine` from `engines/base.py`.
2. Add an entry to `ENGINE_REGISTRY` in `engines/__init__.py`.
3. Done. The Engine submenu, CLI, and Settings window all generate from the registry automatically.

Reference: `engines/whisperkit.py`.

## New TTS Provider

1. Create a file under `src/whisper_voice/tts/` implementing `TTSProvider` from `tts/base.py`.
2. Add an entry to `TTS_REGISTRY` in `tts/__init__.py`.
3. Done. The TTS voice picker and CLI generate from the registry automatically.

Reference: `tts/kokoro_tts.py`.

## Testing

```bash
pytest tests/                           # full unit + integration suite
pytest tests/test_flow.py -v            # end-to-end (requires a grammar backend)
pytest -m integration -v                # only live-service integration tests
cd LocalWhisperUI && swift build -c release
cd src/flutter/local_whisper && flutter analyze && flutter test
```

Manual verification:

1. Run `wh` and select a grammar backend from Settings
2. Double-tap Right Option to record
3. Speak a sentence with filler words ("um", "like", etc.)
4. Single-tap to stop
5. Verify the clipboard contains cleaned text
6. Check overlay showed the correct status transitions (recording, processing, copied)

If your change affects keyboard shortcuts, also test Ctrl+Shift+G/R/P on selected text.

If your change affects TTS, also test ⌥T on selected text.

## PR Checklist

- Keep one feature or fix per PR.
- Test the changed flow end-to-end before opening.
- Update `README.md` when visible behavior changes.
- Include migration notes for breaking config changes.
- Match existing code style; leave unrelated files alone.
- Preserve lazy loading. Eager backend or model initialization gets flagged in review.
- Test TTS when applicable (`⌥T` on selected text).

## Reporting Issues

Use the [bug report template](https://github.com/gabrimatic/local-whisper/issues/new?template=bug_report.yml). Include:

- Output of `wh version` and `wh status`
- Platform, OS version, and device/chip when relevant
- Selected transcription engine
- Grammar backend in use
- Steps to reproduce, expected vs. actual behavior
- Relevant lines from `wh log` if the issue involves processing or crashes

## Vulnerability Reporting

See [SECURITY.md](SECURITY.md). Do **not** open public issues for security vulnerabilities. Use GitHub's private vulnerability reporting.
