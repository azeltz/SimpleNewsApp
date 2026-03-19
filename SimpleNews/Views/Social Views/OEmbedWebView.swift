//
//  OEmbedWebView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/16/26.
//

import SwiftUI
import WebKit

/// Self-sizing oEmbed view that wraps a WKWebView and adjusts its
/// frame height to match the rendered embed content.
struct OEmbedWebView: View {
    let embedHTML: String
    @State private var height: CGFloat = 1

    var body: some View {
        OEmbedWebViewRepresentable(embedHTML: embedHTML, height: $height)
            .frame(height: max(height, 1))
    }
}

// MARK: - UIViewRepresentable

private struct OEmbedWebViewRepresentable: UIViewRepresentable {
    let embedHTML: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "heightChanged")

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        let page = Self.wrapHTML(embedHTML)
        // Use a real base URL so external scripts (e.g. Twitter widgets.js) can load
        webView.loadHTMLString(page, baseURL: URL(string: "https://simplenews.app"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - HTML wrapper

    private static func wrapHTML(_ snippet: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
            <style>
                :root { color-scheme: light dark; }
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, system-ui, sans-serif;
                    display: flex;
                    justify-content: center;
                    padding: 0;
                    background-color: transparent;
                }
                .oembed-container {
                    width: 100%;
                    max-width: 600px;
                }
                /* Make iframes responsive (YouTube, Vimeo, etc.) */
                .oembed-container iframe {
                    width: 100% !important;
                    aspect-ratio: 16 / 9;
                    height: auto !important;
                }
                .oembed-container video,
                .oembed-container img {
                    max-width: 100%;
                    height: auto;
                }
                /* Twitter/X embeds */
                .twitter-tweet { margin: 0 auto !important; }
            </style>
        </head>
        <body>
            <div class="oembed-container">
                \(snippet)
            </div>
            <script>
                function reportHeight() {
                    var h = document.documentElement.scrollHeight;
                    if (h > 0) {
                        window.webkit.messageHandlers.heightChanged.postMessage(h);
                    }
                }
                // Observe DOM changes (e.g. Twitter widgets rendering async)
                var observer = new MutationObserver(function() {
                    reportHeight();
                });
                observer.observe(document.body, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    characterData: true
                });
                window.addEventListener('load', function() {
                    reportHeight();
                    setTimeout(reportHeight, 500);
                    setTimeout(reportHeight, 1500);
                    setTimeout(reportHeight, 3000);
                    setTimeout(reportHeight, 5000);
                });
                window.addEventListener('resize', reportHeight);
                reportHeight();
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat

        init(height: Binding<CGFloat>) {
            _height = height
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "heightChanged",
               let value = message.body as? CGFloat,
               value > 0 {
                DispatchQueue.main.async {
                    self.height = value
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
                return .cancel
            }
            return .allow
        }
    }
}
