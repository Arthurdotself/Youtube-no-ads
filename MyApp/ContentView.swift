import SwiftUI
import WebKit

struct ContentView: View {
    var body: some View {
        YouTubeWebView(url: URL(string: "https://www.youtube.com"))
            .preferredColorScheme(.dark)
    }
}

private struct YouTubeWebView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.ignoresViewportScaleLimits = false
        configuration.userContentController.addUserScript(sidebarStyleScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.overrideUserInterfaceStyle = .dark
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false

        if let url {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

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
}

#Preview {
    ContentView()
}
