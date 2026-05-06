# Security Policy

## Privacy by Design

Privacy is a core constraint, not a feature toggle.

- **Audio and transcript processing is local.** Recording, transcription, grammar correction, and text-to-speech run on-device or against localhost services after setup.
- **Setup can use the network.** Setup, model downloads, `wh update`, and `wh doctor --fix` can fetch packages, models, or repository updates.
- **No telemetry or analytics.** Local Whisper does not send usage analytics.
- **Audio stays on device.** Recordings save to `~/.whisper/` and are not uploaded by the app.
- **Local service boundaries.** WhisperKit uses localhost port 50060 when selected, Ollama uses 11434, and LM Studio uses 1234.

## Permissions

Two macOS permissions, nothing more:

| Permission | Why | Scope |
|------------|-----|-------|
| **Microphone** | Record voice for transcription | Active only during recording |
| **Accessibility** | Detect global hotkey and keyboard shortcuts | Monitors key events for hotkey, TTS shortcut, and text shortcuts |

No other permissions. The app does not access contacts, location, camera, or any other system resource.

## Trust Boundaries

| Boundary | Trust Level | Notes |
|----------|-------------|-------|
| User audio | Trusted | Captured locally, stays on device |
| Parakeet-TDT v3 | Trusted | Runs in-process through MLX |
| Qwen3-ASR | Trusted | Runs in-process through MLX |
| WhisperKit server | Trusted | Runs on localhost if selected |
| Kokoro TTS | Trusted | In-process MLX, no network |
| Grammar backends | Trusted | All run on localhost or on-device |
| Config file (`~/.whisper/config.toml`) | Trusted | User-controlled, local filesystem |
| Backup directory (`~/.whisper/`) | Trusted | Local, user-readable only |

Runtime audio/transcript processing has no cloud trust boundary. Install and update paths can contact package, model, or repository hosts.

## Audio Lifecycle

1. Recording is captured to a temporary WAV file in `~/.whisper/`
2. Audio is passed to the transcription engine (Parakeet-TDT v3 in-process by default, Qwen3-ASR in-process if selected, or WhisperKit on localhost if selected)
3. Transcription text is sent to the selected grammar backend (if enabled)
4. Result is copied to clipboard (or pasted at cursor if auto-paste is enabled)
5. Audio is retained in `~/.whisper/` for backup

After setup and model installation, audio and transcript text stay on the local machine or localhost services.

## Vulnerability Reporting

Report vulnerabilities responsibly:

1. **Do not open a public issue.** Vulnerabilities stay private until a fix ships.
2. Use [GitHub's private vulnerability reporting](https://github.com/gabrimatic/local-whisper/security/advisories/new) to submit.
3. Include:
   - Steps to reproduce
   - Demonstrated impact
   - Suggested fix (if any)

Reports without reproduction steps or demonstrated impact are deprioritized.

Expect acknowledgment within 48 hours.

## Out of Scope

These are not considered vulnerabilities:

- Issues requiring physical access to the machine
- Issues requiring the user to have already granted Accessibility or Microphone permission to a malicious process
- Prompt injection via grammar backend responses (the app copies text to clipboard; it does not execute it)

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.6.x   | Yes       |
| 1.5.x   | Security fixes only |
| Older   | No        |
