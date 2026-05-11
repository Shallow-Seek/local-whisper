# Security Policy

## Privacy by Design

Privacy is a core constraint, not a feature toggle.

- **Audio and transcript processing is local.** Recording, transcription, grammar correction, and text-to-speech run on-device, on localhost, or on a private LAN server you configure after setup.
- **Setup can use the network.** Setup, model downloads, `wh update`, and `wh doctor --fix` can fetch packages, models, or repository updates.
- **No telemetry or analytics.** Local Whisper does not send usage analytics.
- **Audio stays on device.** Recordings save to `~/.whisper/` and are not uploaded by the app.
- **Local service boundaries.** WhisperKit uses localhost port 50060 when selected, Ollama uses 11434, and LM Studio uses 1234.

## Permissions

macOS needs two permissions:

| Permission | Why | Scope |
|------------|-----|-------|
| **Microphone** | Record voice for transcription | Active only during recording |
| **Accessibility** | Detect global hotkey and keyboard shortcuts | Monitors key events for hotkey, TTS shortcut, and text shortcuts |

No other permissions are requested. The app does not access contacts, location, camera, or other system resources.

## Trust Boundaries

| Boundary | Trust Level | Notes |
|----------|-------------|-------|
| Your audio | Trusted | Captured locally, stays on device |
| Parakeet-TDT v3 | Trusted | Runs in-process through MLX |
| Qwen3-ASR | Trusted | Runs in-process through MLX |
| WhisperKit server | Trusted | Runs on localhost if selected |
| Kokoro TTS | Trusted | In-process MLX after model download |
| Grammar backends | Trusted | All run on localhost or on-device |
| Config file (`~/.whisper/config.toml`) | Trusted | Local filesystem |
| Backup directory (`~/.whisper/`) | Trusted | Local, owner-readable only |

Runtime audio/transcript processing has no cloud trust boundary. Install and update paths can contact package, model, or repository hosts.

## Audio Lifecycle

1. Recording is captured to a temporary WAV file in `~/.whisper/`
2. Audio is passed to the transcription engine (Parakeet-TDT v3 in-process by default, Qwen3-ASR in-process if selected, or WhisperKit on localhost if selected)
3. Local Whisper sends transcription text to the selected grammar backend when grammar is enabled
4. Local Whisper copies the result to clipboard or pastes at the cursor when auto-paste is enabled
5. Audio is retained in `~/.whisper/` for backup

After setup and model installation, audio and transcript text stay on the local machine, localhost services, or a private LAN server you configure for LM Studio.

## Vulnerability Reporting

Report vulnerabilities privately:

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
- Issues that require you to grant Accessibility or Microphone permission to a malicious process
- Prompt injection via grammar backend responses (the app copies text to clipboard; it does not execute it)

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.6.x   | Yes       |
| 1.5.x   | Security fixes only |
| Older   | No        |
