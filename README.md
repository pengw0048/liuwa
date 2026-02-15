# Liuwa / 六娃

An open-source macOS AI assistant with a screen-capture-invisible overlay window. The overlay is not visible in screenshots, screen recordings, or screen sharing (Zoom, Google Meet, etc.), but remains fully interactive on your physical display.

Built on macOS public APIs only — no private frameworks, no root required.

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (M1 or later) -- required for on-device Foundation Models (Apple AI)
- Swift 6.2+ (included with Xcode 26 Command Line Tools)

## Build & Run

Build as a macOS `.app` bundle (recommended — permissions are attributed to Liuwa instead of Terminal):

```bash
./scripts/bundle.sh          # builds release arm64 by default
open Liuwa.app               # double-click also works from Finder
```

Or run directly (note: permissions will be attributed to Terminal.app):

```bash
swift build
.build/debug/Liuwa
```

If you need to build to a specific directory (e.g. for corporate security tools that whitelist certain paths):

```bash
swift build --scratch-path /some/whitelisted/path
/some/whitelisted/path/debug/Liuwa
```

## Permissions

On first launch, Liuwa shows a setup window and requires all of the following before you can continue (System Settings > Privacy & Security):

- **Accessibility** — global hotkeys (CGEventTap) and reading on-screen text via the Accessibility API
- **Microphone** — speech transcription (macOS may also ask for **Speech Recognition** for the local model)
- **Screen Recording** — screenshot-based screen capture when Accessibility text is insufficient

Grant each permission (use the buttons in the setup window to open the right panes), then click **Continue**. Only after all three are granted does the app enter invisible overlay mode.

## Hotkeys

All hotkeys use **Cmd+Option** (⌘⌥) as modifier. Keys are configurable in the settings window (⌘⌥S).

Default bindings:

| Key | Action |
|-----|--------|
| ⌘⌥O | Show/hide overlay |
| ⌘⌥G | Toggle ghost mode (invisible to capture) |
| ⌘⌥E | Toggle click-through |
| ⌘⌥T | Start/stop microphone transcription |
| ⌘⌥Y | Start/stop system audio transcription |
| ⌘⌥1-4 | Send AI preset (Reply / Summarize / Solve / Improve) |
| ⌘⌥X | Cycle screen text capture (off / on) |
| ⌘⌥Z | Cycle screenshot capture (off / on) |
| ⌘⌥W | Clear transcription |
| ⌘⌥C | Clear AI conversation |
| ⌘⌥↑↓ | Scroll AI response |
| ⌘⌥D | Open documents panel |
| ⌘⌥J / ⌘⌥L | Previous/next document |
| ⌘⌥I / ⌘⌥K | Scroll document up/down |
| ⌘⌥A | Toggle attach document to AI context |
| ⌘⌥S | Open settings |
| ⌘⌥Q | Quit |

## Features

**Invisible overlay** -- The window uses `NSWindow.sharingType = .none`, which makes it invisible to all screen capture mechanisms on macOS 26+. It stays visible on your physical display and floats above all other windows.

**Speech transcription** -- Uses the macOS 26 `SpeechTranscriber` API for local, offline transcription of microphone input. No audio leaves your machine.

**System audio capture** -- Captures audio from other applications (e.g. meeting participants) via Core Audio Process Tap and transcribes it locally.

**Screen content extraction** -- Two modes: (1) Accessibility API reads text directly from the active window, (2) ScreenCaptureKit takes a screenshot with OCR via Apple Vision framework.

**LLM integration** -- Supports macOS 26 Foundation Models (~3B parameter on-device model) for fully offline operation, plus OpenAI, Anthropic (Claude), Google Gemini, and Ollama via [AnyLanguageModel](https://github.com/mattt/AnyLanguageModel). Switch providers in the settings window.

**Configurable UI** -- Transparency, width, font size, and hotkey bindings are all adjustable through a settings dialog with live preview.

## Configuration

All settings are configurable through the in-app settings window (⌘⌥S). Settings persist to `~/.liuwa/config.json`.

Supported LLM providers: Local (Apple Foundation Models), OpenAI, Anthropic (Claude), Google Gemini, Ollama. Select a provider and fill in the credentials in the settings window.

To load reference documents, place `.txt`, `.md`, `.json`, `.swift` or other text files in `~/Documents/Liuwa/` (configurable in settings). Press ⌘⌥D to open docs; use ⌘⌥J/L to switch documents and ⌘⌥I/K to scroll within the current document.

## Building release binaries

Build and package as `.app` bundle:

```bash
./scripts/bundle.sh release arm64     # Apple Silicon
./scripts/bundle.sh release x86_64    # Intel
```

The resulting `Liuwa.app` can be copied to `/Applications` or distributed as a zip.

## How the invisibility works

The overlay window uses `NSWindow.sharingType = .none`. On supported macOS versions this tells the window server to exclude the window from capture APIs (e.g. QuickTime, Zoom, Meet, OBS). The window remains visible on your physical display.

## Project structure

```
Sources/Liuwa/
  main.swift                 -- App entry point
  AppDelegate.swift          -- Launch, permission setup window, wires components
  GhostWindow.swift          -- NSWindow subclass with sharingType=none
  OverlayController.swift    -- Overlay panel layout and content management
  OverlayConfig.swift        -- User settings, load/save from ~/.liuwa/config.json
  SettingsWindow.swift       -- Settings dialog UI
  HotkeyManager.swift        -- CGEventTap global hotkeys
  TranscriptionManager.swift -- Microphone transcription via SpeechTranscriber
  SystemAudioManager.swift   -- System audio capture via Core Audio Process Tap
  ScreenCaptureManager.swift -- Accessibility API + ScreenCaptureKit OCR
  LLMManager.swift           -- Foundation Models (local) + remote API
  DocumentManager.swift      -- Reference document loading
  Info.plist                 -- Privacy permission descriptions
scripts/
  bundle.sh                  -- Build and package as Liuwa.app
```

## What does Liuwa mean?

**Liuwa** (六娃) is the sixth of the seven Calabash Brothers (葫芦娃) in the classic Chinese animated series. The sixth brother’s power is **invisibility** — he can become invisible at will. The app is named after him because its main trick is an overlay that is invisible to screen capture and screen sharing, while still visible and usable on your own screen.

## License

MIT
