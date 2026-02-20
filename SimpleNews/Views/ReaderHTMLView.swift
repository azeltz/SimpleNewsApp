//
//  ReaderHTMLView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/17/26.
//

import SwiftUI
import WebKit

struct ReaderHTMLView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    @ObservedObject var controller: ReaderController

    /// Called when we successfully detect a main image URL from the loaded HTML.
    /// You can use this to update the Article / view model.
    var onImageFound: ((URL) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        // Expose this instance to the controller (on main queue)
        DispatchQueue.main.async {
            controller.webView = webView
            controller.isLoaded = false
        }

        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Simple guard to avoid endless reloads
        if !uiView.isLoading && uiView.url == nil {
            uiView.loadHTMLString(html, baseURL: nil)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ReaderHTMLView

        init(_ parent: ReaderHTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear

            DispatchQueue.main.async {
                self.parent.controller.isLoaded = true
                print("Reader loaded: isLoaded = \(self.parent.controller.isLoaded)")
            }

            // Update intrinsic height from content
            webView.evaluateJavaScript("document.body.scrollHeight") { result, error in
                guard error == nil, let height = result as? CGFloat else { return }
                DispatchQueue.main.async {
                    self.parent.height = height
                }
            }

            // Try to detect a main image from the article HTML
            webView.evaluateJavaScript("""
            (function() {
                // Prefer og:image if present
                var og = document.querySelector('meta[property="og:image"]');
                if (og && og.content) { return og.content; }

                // Otherwise, first reasonably large <img>
                var imgs = document.images;
                var best = null;
                for (var i = 0; i < imgs.length; i++) {
                    var img = imgs[i];
                    var w = img.naturalWidth || img.width;
                    var h = img.naturalHeight || img.height;
                    if (w >= 200 && h >= 150) { // simple heuristic
                        best = img;
                        break;
                    }
                }
                return best ? best.src : null;
            })();
            """) { result, error in
                guard error == nil,
                      let src = result as? String,
                      let url = URL(string: src) else {
                    return
                }

                DispatchQueue.main.async {
                    print("ReaderHTMLView: found image URL from reader HTML: \(url.absoluteString)")
                    self.parent.onImageFound?(url)
                }
            }
        }
    }
}
