# Liuwa / 六娃

An open-source macOS AI assistant with a screen-capture-invisible overlay. The overlay is invisible to screenshots, screen recordings, and screen sharing (Zoom, Meet, etc.), but remains fully interactive on your display.

Built on macOS public APIs only — no private frameworks, no root required.

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (M1+) — required for on-device Foundation Models
- Swift 6.2+ (included with Xcode 26 Command Line Tools)

## Quick Install

```bash
curl -fSL https://github.com/pengw0048/liuwa/releases/latest/download/Liuwa-app.zip \
  -o /tmp/Liuwa-app.zip && unzip -o /tmp/Liuwa-app.zip -d /Applications \
  && rm /tmp/Liuwa-app.zip && open /Applications/Liuwa.app
```

Downloads `Liuwa.app` to `/Applications` and launches it. Permissions are attributed to "Liuwa" (not Terminal).

## Build from Source

```bash
swift build && .build/debug/Liuwa

# Or as .app bundle:
./scripts/bundle.sh && open Liuwa.app
```

### Code Signing (recommended)

Without a stable signing identity, macOS requires re-granting permissions after every rebuild. Create a self-signed certificate once:

```bash
./scripts/create-cert.sh   # one-time, stored in login keychain
```

All subsequent `bundle.sh` runs sign with it automatically.

## Permissions

On first launch a setup window requires three permissions (System Settings > Privacy & Security):

- **Accessibility** — global hotkeys and reading on-screen text
- **Microphone** — speech transcription
- **Screen Recording** — screenshot capture

Closing the setup window without granting permissions quits the app.

## Hotkeys

All use **⌘⌥** (Cmd+Option). Configurable in settings (⌘⌥S).

| Key | Action |
|-----|--------|
| ⌘⌥O | Show/hide overlay |
| ⌘⌥G | Toggle ghost mode (invisible to capture) |
| ⌘⌥E | Toggle click-through |
| ⌘⌥T | Start/stop mic transcription |
| ⌘⌥Y | Start/stop system audio transcription |
| ⌘⌥W | Clear transcription |
| ⌘⌥1-4 | AI presets (Reply / Summarize / Solve / Improve) |
| ⌘⌥C | Clear AI conversation |
| ⌘⌥↑↓ | Scroll AI response |
| ⌘⌥X | Toggle screen text capture |
| ⌘⌥Z | Toggle screenshot capture |
| ⌘⌥D | Toggle document panel |
| ⌘⌥J/L | Previous/next document |
| ⌘⌥I/K | Scroll document up/down |
| ⌘⌥A | Toggle attach document to AI context |
| ⌘⌥S | Settings |
| ⌘⌥Q | Quit |

## Features

- **Invisible overlay** — hidden from screenshots, recordings, and screen sharing (macOS 26+).
- **Transcription** — mic and system audio, local (SpeechTranscriber), configurable language.
- **Screen context** — Accessibility text or screenshot/OCR for the LLM.
- **LLM** — Apple on-device or OpenAI / Anthropic / Gemini / Ollama ([AnyLanguageModel](https://github.com/mattt/AnyLanguageModel)).
- **Documents** — reference folder, ⌘⌥D to show panel, ⌘⌥J/L to switch file, optional attach to context.
- **Settings** — transparency, size, hotkeys, section ratios (⌘⌥S); saved to `~/.liuwa/config.json`.

## Project Structure

```
Sources/Liuwa/
  main.swift                 Entry point, duplicate instance check
  AppDelegate.swift          Permission setup, component wiring, hotkey dispatch
  GhostWindow.swift          NSWindow with sharingType=none
  OverlayController.swift    Overlay layout, sections, drag dividers
  OverlayConfig.swift        Settings, load/save ~/.liuwa/config.json
  SettingsWindow.swift       Settings dialog
  HotkeyManager.swift        CGEventTap global hotkeys
  TranscriptionManager.swift Mic transcription via SpeechTranscriber
  SystemAudioManager.swift   System audio via Core Audio Process Tap
  ScreenCaptureManager.swift Accessibility text + ScreenCaptureKit OCR
  LLMManager.swift           Foundation Models + remote LLM APIs
  DocumentManager.swift      Reference document loading
  Info.plist                 Bundle metadata and permission descriptions
scripts/
  bundle.sh                  Build and package .app bundle
  create-cert.sh             Create self-signed code signing certificate
```

## Name

**Liuwa** (六娃) is the sixth Calabash Brother (葫芦娃) whose power is **invisibility**. The app is named after him — an overlay invisible to screen capture, visible only to you.

## License

MIT
