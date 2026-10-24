<div align="center">

# Youtube-no-ads

**A lightweight SwiftUI iPhone app that wraps YouTube in a `WKWebView` for a cleaner, calmer, data-friendly experience.**

![Platform](https://img.shields.io/badge/platform-iOS-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

</div>

---

## Overview

Youtube-no-ads is a small native iOS app whose entire UI is YouTube's own website, loaded inside a `WKWebView` and reshaped with injected CSS and JavaScript. There is no backend, no account system, and no third-party dependency: just SwiftUI, WebKit, and a handful of carefully written user scripts.

The goal is to make YouTube on a phone feel closer to a focused video player than a feed designed to keep you scrolling.

## Why I built it

YouTube's mobile experience gets in the way of simply watching videos:

- Playback stops the moment you lock the screen or switch apps, unless you pay for it.
- The mobile web layout wastes screen space on side menus and multi-column grids.
- On mobile data, YouTube happily streams high-quality video and loads dozens of thumbnails, Shorts, recommendations and comments you never asked for.
- The web version hides the fullscreen button on iPhone.

This project fixes those problems in one small app that I can read, understand and change completely.

## Features

| Feature | What it does |
| --- | --- |
| **Background playback** | Keeps audio and video going when the screen locks or you leave the app. |
| **Automatic data saver** | Detects cellular vs. Wi-Fi and applies savings only when you are on mobile data. |
| **Quality cap** | Limits video quality on cellular (240p by default) and hands control back to YouTube on Wi-Fi. |
| **Small thumbnails** | Swaps large thumbnails for compact ones, roughly 5x fewer bytes each. |
| **Hide heavy sections** | Hides Shorts shelves, the "up next" list, comments and hover previews on cellular. |
| **Autoplay off on cellular** | Turns autoplay off on mobile data, and restores it afterwards only if the app turned it off. |
| **Native fullscreen** | Brings back the fullscreen button and routes it to iOS's own fullscreen player. |
| **Single-column feed** | Removes the sidebar and shows one video per row, with thumbnails filling the screen. |
| **Seamless status bar** | A frosted strip behind the notch that matches YouTube's top bar, including its scrolled state. |
| **Pinch-zoom disabled** | Prevents accidental page zoom for an app-like feel. |

Every data-saver option is a simple constant you can change in one place.

## How it works

```
┌──────────────────────────── SwiftUI app ────────────────────────────┐
│                                                                     │
│  MyApp.swift        Configures the audio session (.playback) so      │
│                     media can continue in the background.            │
│                                                                     │
│  ContentView.swift  Hosts the web view and the top status-bar strip. │
│    ├─ NetworkMonitor    NWPathMonitor: Wi-Fi / Ethernet / Cellular   │
│    ├─ YouTubeWebView    WKWebView + Coordinator                      │
│    └─ User scripts      JavaScript/CSS injected into youtube.com     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

1. **Launch.** `MyApp` sets the audio session category to `.playback`, and `Info.plist` declares the `audio` background mode.
2. **Network detection.** `NetworkMonitor` (built on `NWPathMonitor`) reports whether the phone is on Wi-Fi, Ethernet or cellular only.
3. **Script injection.** Once the network type is known, the coordinator installs four `WKUserScript`s and loads `https://www.youtube.com`:
   - **Background playback script** makes the page always report that it is visible, swallows `visibilitychange` events, and resumes the video if it is paused right after the app is hidden.
   - **Fullscreen script** exposes the fullscreen button on iPhone and sends the video to the native player.
   - **Layout script** hides the sidebar, forces a one-column grid and locks the viewport.
   - **Data saver script** caps quality through the player API, rewrites thumbnail URLs, hides heavy sections and toggles autoplay, all controlled by a single `window.__dataSaver` flag.
4. **Live switching.** If you move between Wi-Fi and cellular mid-session, the flag is flipped and the current page updates immediately, with no reload needed.
5. **Background resume.** When the app resigns active, the web view records whether a video was playing. After it enters the background, the app requests a short background task and retries `play()` a few times so audio keeps going.

## Getting started

### Requirements

- A Mac with a recent version of **Xcode**
- An iPhone or the iOS Simulator

### Run it

```bash
git clone https://github.com/Arthurdotself/Youtube-no-ads.git
cd Youtube-no-ads
open "Untitled Project.xcodeproj"
```

1. Select the **MyApp** scheme and your device (or a simulator).
2. In *Signing & Capabilities*, choose your own development team.
3. Press **Run** (`⌘R`).

> **Tip:** Background playback and cellular detection only behave realistically on a real iPhone. To test the data saver on Wi-Fi or in the Simulator, set `forceDataSaver = true`.

## Configuration

All tunable options live at the top of `YouTubeWebView` in [`MyApp/ContentView.swift`](MyApp/ContentView.swift):

```swift
private static let maxQuality = "small"        // tiny=144p, small=240p, medium=360p, large=480p, hd720=720p
private static let smallThumbnails = true      // use compact thumbnails
private static let hideShorts = true           // hide Shorts shelves
private static let hideRecommendations = true  // hide the "up next" list
private static let hideComments = true         // hide comments
private static let forceDataSaver = false      // test the data saver on Wi-Fi
```

The soft edge of the status-bar strip is controlled by `seamBlend` in `ContentView`.

## Project structure

```
Youtube-no-ads/
├── MyApp/
│   ├── MyApp.swift          # App entry point and audio session setup
│   ├── ContentView.swift    # Web view, network monitor, injected scripts, UI strip
│   ├── Info.plist           # Declares the audio background mode
│   └── Assets.xcassets/
└── Untitled Project.xcodeproj
```

## Limitations

- This is a wrapper around youtube.com, so it depends on YouTube's current page structure. If YouTube changes its markup, some CSS selectors or player calls may need updating.
- Background playback relies on the page-visibility workarounds and on iOS granting background time, so behavior can vary between iOS versions.
- Use of YouTube is subject to YouTube's Terms of Service. This project is unofficial and not affiliated with or endorsed by Google or YouTube.

## Roadmap ideas

- Settings screen to change the data-saver options inside the app
- Per-network quality presets (for example, a different cap on 5G)
- Picture-in-picture controls
- Screenshots and a short demo GIF in this README

## Contributing

Issues and pull requests are welcome. If YouTube changes something and a script stops working, a PR with the updated selector is the most useful contribution.
