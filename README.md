# Liuwa

An open-source macOS AI assistant with a screen-capture-invisible overlay window. The overlay is not visible in screenshots, screen recordings, or screen sharing (Zoom, Google Meet, etc.), but remains fully interactive on your physical display.

Built on macOS public APIs only -- no private frameworks, no root required.

## Requirements

- macOS 26 (Tahoe) or later
- Swift 6.2+ (included with Xcode 26 Command Line Tools)

## Build & Run

```bash
swift build
swift run Liuwa
```

Or build and run separately:

```bash
swift build
.build/arm64-apple-macosx/debug/Liuwa
```

If you need to build to a specific directory (e.g. for corporate security tools that whitelist certain paths):

```bash
swift build --scratch-path /some/whitelisted/path
/some/whitelisted/path/arm64-apple-macosx/debug/Liuwa
```

## Permissions

On first launch, macOS will prompt for the following (System Settings > Privacy & Security):

- **Accessibility** -- required for global hotkeys (CGEventTap) and reading on-screen text via the Accessibility API
- **Microphone** -- for speech transcription
- **Speech Recognition** -- for the local SpeechTranscriber model
- **Screen Recording** -- for screenshot-based screen capture (only used when Accessibility text extraction is insufficient)

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
| ⌘⌥C | Clear AI conversation |
| ⌘⌥↑↓ | Scroll AI response |
| ⌘⌥D | Open documents panel |
| ⌘⌥S | Open settings |
| ⌘⌥Q | Quit |

## Features

**Invisible overlay** -- The window uses `NSWindow.sharingType = .none`, which makes it invisible to all screen capture mechanisms on macOS 26+. It stays visible on your physical display and floats above all other windows.

**Speech transcription** -- Uses the macOS 26 `SpeechTranscriber` API for local, offline transcription of microphone input. No audio leaves your machine.

**System audio capture** -- Captures audio from other applications (e.g. meeting participants) via Core Audio Process Tap and transcribes it locally.

**Screen content extraction** -- Two modes: (1) Accessibility API reads text directly from the active window, (2) ScreenCaptureKit takes a screenshot with OCR via Apple Vision framework.

**LLM integration** -- Supports macOS 26 Foundation Models (~3B parameter on-device model) for fully offline operation, or any OpenAI-compatible remote API (GPT-4o, Claude, etc.) for higher quality responses.

**Configurable UI** -- Transparency, width, font size, and hotkey bindings are all adjustable through a settings dialog with live preview.

## Configuration

Settings are stored at `~/.liuwa/config.json` and can be edited through the in-app settings window (⌘⌥S). You can also edit the file directly:

```bash
mkdir -p ~/.liuwa
cp config.example.json ~/.liuwa/config.json
```

To load reference documents (shown via ⌘⌥D), place `.txt`, `.md`, `.json`, or `.swift` files in `~/Documents/Liuwa/` (configurable in settings).

## How the invisibility works

macOS windows have a `sharingType` property. Setting it to `.none` tells the window server to exclude the window from all capture APIs, including ScreenCaptureKit (used by QuickTime, Zoom, Meet, OBS, and most modern tools) and the legacy `CGWindowListCreateImage` API.

This is a public, documented API. See [RESEARCH.md](RESEARCH.md) for detailed findings and test results.

## Project structure

```
Sources/Liuwa/
  main.swift                 -- App entry point
  AppDelegate.swift          -- Initializes and wires all components
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
```

## License

MIT
