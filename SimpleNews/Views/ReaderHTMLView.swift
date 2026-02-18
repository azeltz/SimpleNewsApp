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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false   // parent ScrollView will scroll
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(html, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ReaderHTMLView

        init(_ parent: ReaderHTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, error in
                guard error == nil, let height = result as? CGFloat else { return }
                DispatchQueue.main.async {
                    self.parent.height = height
                }
            }
        }
    }
}

