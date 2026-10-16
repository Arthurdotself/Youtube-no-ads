import Network
import SwiftUI
import WebKit

struct ContentView: View {
    /// Shows a small test panel at the bottom with the network type, the data saver mode
    /// and the quality YouTube is actually playing. Set to false to hide it.
    private let showDebugOverlay = true

    @State private var status = DebugStatus()

    var body: some View {
        YouTubeWebView(
            url: URL(string: "https://www.youtube.com"),
            onStatus: { status = $0 }
        )
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottomLeading) {
            if showDebugOverlay {
                Text(status.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(6)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Debug status

private struct DebugStatus {
    var network = "Detecting..."
    var dataSaverOn = false
    var capLabel = ""
    var playing = "no video"

    var text: String {
        let mode = dataSaverOn
            ? "DATA SAVER ON (max \(capLabel))"
            : "NORMAL (quality auto)"
        return "Network: \(network)\nMode: \(mode)\nPlaying: \(playing)"
    }
}

private func qualityLabel(_ name: String) -> String {
    let labels = [
        "tiny": "144p",
        "small": "240p",
        "medium": "360p",
        "large": "480p",
        "hd720": "720p",
        "hd1080": "1080p",
        "hd1440": "1440p",
        "hd2160": "2160p",
        "highres": "4K+"
    ]
    if let label = labels[name] {
        return "\(label) (\(name))"
    }
    return name
}

// MARK: - Network monitor

/// Tells us what kind of network the phone is on.
private nonisolated final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    /// Called on the main queue with `true` when on cellular only, plus a readable network name.
    var onUpdate: ((Bool, String) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.usesInterfaceType(.wifi)
            let wired = path.usesInterfaceType(.wiredEthernet)
            let cellular = path.usesInterfaceType(.cellular)

            let onCellular = cellular && !wifi && !wired

            let name: String
            if path.status != .satisfied {
                name = "No connection"
            } else if wifi {
                name = "Wi-Fi"
            } else if wired {
                name = "Ethernet"
            } else if cellular {
                name = "Cellular"
            } else {
                name = "Other"
            }

            DispatchQueue.main.async {
                self?.onUpdate?(onCellular, name)
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - Web view

private struct YouTubeWebView: UIViewRepresentable {
    let url: URL?
    let onStatus: (DebugStatus) -> Void

    // MARK: Data saver settings (only used while on cellular)

    /// Highest video quality used while on mobile data. Lower = less data.
    /// Options: "tiny" (144p), "small" (240p), "medium" (360p), "large" (480p), "hd720" (720p)
    private static let maxQuality = "small"

    /// Swap the big video thumbnails for small ones (about 5x fewer bytes per thumbnail).
    private static let smallThumbnails = true

    /// Hide the "Shorts" rows, which are made of many extra thumbnails and short videos.
    private static let hideShorts = true

    /// Hide the "up next" list beside / under the video (dozens of thumbnails).
    private static let hideRecommendations = true

    /// Hide the comments section (avatars and a lot of extra requests).
    private static let hideComments = true

    /// Set to true to test the data saver on Wi-Fi or in the Simulator.
    private static let forceDataSaver = false

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.ignoresViewportScaleLimits = false
        // Lets the YouTube fullscreen button use the web Fullscreen API where WebKit supports it.
        configuration.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.overrideUserInterfaceStyle = .dark
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false

        // The coordinator installs the scripts and loads the page once it knows
        // whether we're on cellular or Wi-Fi.
        context.coordinator.attach(to: webView)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: Coordinator

    final class Coordinator {
        private let parent: YouTubeWebView
        private weak var webView: WKWebView?
        private let monitor = NetworkMonitor()
        private var status = DebugStatus()
        private var hasLoaded = false

        init(parent: YouTubeWebView) {
            self.parent = parent
            status.capLabel = qualityLabel(YouTubeWebView.maxQuality)
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            monitor.onUpdate = { [weak self] onCellular, name in
                self?.networkChanged(onCellular: onCellular, name: name)
            }
            monitor.start()
            startPollingQuality()
        }

        private func networkChanged(onCellular: Bool, name: String) {
            guard let webView else { return }

            let enabled = onCellular || YouTubeWebView.forceDataSaver
            let changed = enabled != status.dataSaverOn
            status.dataSaverOn = enabled
            status.network = name
            parent.onStatus(status)

            if !hasLoaded {
                hasLoaded = true
                parent.installScripts(on: webView.configuration.userContentController, dataSaver: enabled)
                if let url = parent.url {
                    webView.load(URLRequest(url: url))
                }
            } else if changed {
                // Future page loads get the new setting, and the current page is updated right away.
                parent.installScripts(on: webView.configuration.userContentController, dataSaver: enabled)
                webView.evaluateJavaScript(
                    "window.__dataSaver = \(enabled); if (window.__dataSaverApply) { window.__dataSaverApply(); }",
                    completionHandler: nil
                )
            }
        }

        /// Asks the page once per second which quality the player is really using.
        private func startPollingQuality() {
            Task { [weak self] in
                while let self {
                    await self.pollQuality()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        private func pollQuality() async {
            guard let webView else { return }

            let script = """
            (function () {
                var p = document.getElementById('movie_player');
                if (!p || typeof p.getPlaybackQuality !== 'function') { return 'no video'; }
                return p.getPlaybackQuality();
            })()
            """

            let result = try? await webView.evaluateJavaScript(script)
            let name = (result as? String) ?? "no video"
            let label = name == "no video" ? name : qualityLabel(name)

            if label != status.playing {
                status.playing = label
                parent.onStatus(status)
            }
        }
    }

    // MARK: Scripts

    private func installScripts(on controller: WKUserContentController, dataSaver: Bool) {
        controller.removeAllUserScripts()
        controller.addUserScript(fullscreenScript)
        controller.addUserScript(sidebarStyleScript)
        controller.addUserScript(dataSaverScript(enabled: dataSaver))
    }

    /// iPhone WebKit doesn't offer the web Fullscreen API for normal page elements, so YouTube hides
    /// its fullscreen button. This makes the button appear and sends the video to iOS's own
    /// fullscreen player instead. If the real API exists, nothing is changed.
    private var fullscreenScript: WKUserScript {
        let source = """
        (function () {
            if (document.fullscreenEnabled || document.webkitFullscreenEnabled) { return; }

            function enterNativeFullscreen() {
                var video = document.querySelector('video');
                if (video && typeof video.webkitEnterFullscreen === 'function') {
                    video.webkitEnterFullscreen();
                    return Promise.resolve();
                }
                return Promise.reject(new TypeError('No video available for fullscreen'));
            }

            try {
                Object.defineProperty(document, 'fullscreenEnabled', { get: function () { return true; }, configurable: true });
                Object.defineProperty(document, 'webkitFullscreenEnabled', { get: function () { return true; }, configurable: true });
            } catch (e) {}

            Element.prototype.requestFullscreen = enterNativeFullscreen;
            Element.prototype.webkitRequestFullscreen = enterNativeFullscreen;
            Element.prototype.webkitRequestFullScreen = enterNativeFullscreen;
        })();
        """

        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    private var sidebarStyleScript: WKUserScript {
        let source = """
        const viewport = document.querySelector('meta[name="viewport"]') || document.createElement('meta');
        viewport.name = 'viewport';
        viewport.content = 'width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no';
        document.head.appendChild(viewport);

        const style = document.createElement('style');
        style.textContent = `
            html,
            body {
                touch-action: pan-y !important;
            }

            #guide,
            ytd-mini-guide-renderer {
                display: none !important;
            }

            #content,
            #page-manager {
                margin-left: 0 !important;
                width: 100% !important;
            }
        `;
        document.head.appendChild(style);

        document.addEventListener('gesturestart', event => event.preventDefault(), { passive: false });
        document.addEventListener('gesturechange', event => event.preventDefault(), { passive: false });
        document.addEventListener('touchmove', event => {
            if (event.touches.length > 1) {
                event.preventDefault();
            }
        }, { passive: false });
        """

        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    /// Caps the video quality, shrinks thumbnails, hides heavy page sections and turns off autoplay,
    /// but only while `window.__dataSaver` is true (on cellular). On Wi-Fi it undoes what it can.
    private func dataSaverScript(enabled: Bool) -> WKUserScript {
        let source = """
        (function () {
            var QUALITY = '\(Self.maxQuality)';
            var SMALL_THUMBNAILS = \(Self.smallThumbnails);
            var HIDE_SHORTS = \(Self.hideShorts);
            var HIDE_RECOMMENDATIONS = \(Self.hideRecommendations);
            var HIDE_COMMENTS = \(Self.hideComments);

            var lastVideo = null;
            var attempts = 0;

            window.__dataSaver = \(enabled);

            // Page sections that cost a lot of data. Switched on and off with the data saver.
            var css = 'ytd-video-preview { display: none !important; }';
            if (HIDE_SHORTS) {
                css += 'ytd-reel-shelf-renderer, ytd-rich-shelf-renderer[is-shorts] { display: none !important; }';
            }
            if (HIDE_RECOMMENDATIONS) {
                css += 'ytd-watch-next-secondary-results-renderer { display: none !important; }';
            }
            if (HIDE_COMMENTS) {
                css += 'ytd-comments#comments, #comments { display: none !important; }';
            }
            var style = document.createElement('style');
            style.textContent = css;
            document.head.appendChild(style);

            // Small thumbnails: swap the large image for the 320x180 version.
            var THUMBNAIL = /^https:\\/\\/i\\.ytimg\\.com\\/vi(?:_webp)?\\/([^\\/]+)\\//;

            function shrinkThumbnail(img) {
                if (!SMALL_THUMBNAILS || !window.__dataSaver) { return; }
                var src = img.getAttribute('src');
                if (!src) { return; }
                var match = src.match(THUMBNAIL);
                if (!match) { return; }
                var small = 'https://i.ytimg.com/vi/' + match[1] + '/mqdefault.jpg';
                if (src !== small) { img.setAttribute('src', small); }
            }

            function shrinkIn(node) {
                if (!node || node.nodeType !== 1) { return; }
                if (node.tagName === 'IMG') { shrinkThumbnail(node); }
                if (node.querySelectorAll) {
                    node.querySelectorAll('img').forEach(shrinkThumbnail);
                }
            }

            if (SMALL_THUMBNAILS) {
                new MutationObserver(function (mutations) {
                    if (!window.__dataSaver) { return; }
                    mutations.forEach(function (mutation) {
                        if (mutation.type === 'attributes') {
                            shrinkThumbnail(mutation.target);
                        } else {
                            mutation.addedNodes.forEach(shrinkIn);
                        }
                    });
                }).observe(document.documentElement, {
                    subtree: true,
                    childList: true,
                    attributes: true,
                    attributeFilter: ['src']
                });
            }

            function getPlayer() {
                var player = document.getElementById('movie_player');
                if (player && typeof player.setPlaybackQualityRange === 'function') {
                    return player;
                }
                return null;
            }

            function limitQuality() {
                try {
                    var player = getPlayer();
                    if (!player) { return; }

                    var id = player.getVideoData ? player.getVideoData().video_id : '';
                    if (id !== lastVideo) {
                        lastVideo = id;
                        attempts = 0;
                    }
                    if (attempts >= 5) { return; }

                    if (player.getPlaybackQuality() !== QUALITY) {
                        attempts++;
                        player.setPlaybackQualityRange(QUALITY, QUALITY);
                        player.setPlaybackQuality(QUALITY);
                        localStorage.setItem('__ds_applied', '1');
                    }
                } catch (e) {}
            }

            // Back on Wi-Fi: let YouTube choose the quality again.
            function restoreQuality() {
                try {
                    if (localStorage.getItem('__ds_applied') !== '1') { return; }
                    var player = getPlayer();
                    if (player) {
                        player.setPlaybackQualityRange('tiny', 'highres');
                    }
                    localStorage.removeItem('yt-player-quality');
                    localStorage.removeItem('__ds_applied');
                } catch (e) {}
            }

            function handleAutoplay() {
                try {
                    var toggle = document.querySelector('.ytp-autonav-toggle-button');
                    if (!toggle) { return; }
                    var isOn = toggle.getAttribute('aria-checked') === 'true';

                    if (window.__dataSaver) {
                        if (isOn) {
                            toggle.click();
                            localStorage.setItem('__ds_autoplay_off', '1');
                        }
                    } else if (localStorage.getItem('__ds_autoplay_off') === '1') {
                        // Only turn it back on if we were the ones who turned it off.
                        if (!isOn) { toggle.click(); }
                        localStorage.removeItem('__ds_autoplay_off');
                    }
                } catch (e) {}
            }

            function tick() {
                style.media = window.__dataSaver ? 'all' : 'not all';
                if (window.__dataSaver) {
                    limitQuality();
                } else {
                    restoreQuality();
                }
                handleAutoplay();
            }

            window.__dataSaverApply = function () {
                attempts = 0;
                tick();
            };

            setInterval(tick, 1000);
            window.addEventListener('yt-navigate-finish', tick);
            tick();
        })();
        """

        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
}

#Preview {
    ContentView()
}
