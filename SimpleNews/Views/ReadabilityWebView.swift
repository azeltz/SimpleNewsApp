//
//  ReadabilityWebView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/17/26.
//

//Don't think i need this tbh

import SwiftUI
import WebKit
import Readability
import ReadabilityUI

struct ReadabilityWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        // Create coordinator with initial reader style
        let coordinator = ReadabilityWebCoordinator(
            initialStyle: ReaderStyle(theme: .light, fontSize: .size5)
        )

        context.coordinator.coordinator = coordinator

        // Prepare configuration for a readable web view
        Task {
            do {
                let configuration = try await coordinator.createReadableWebViewConfiguration()
                await MainActor.run {
                    let webView = WKWebView(frame: .zero, configuration: configuration)
                    webView.navigationDelegate = context.coordinator
                    context.coordinator.webView = webView

                    // Load the URL
                    webView.load(URLRequest(url: url))

                    // Start listening for reader HTML and availability in the background
                    context.coordinator.startReaderTasks()
                }
            } catch {
                // If configuration fails, fall back to a default WKWebView
                await MainActor.run {
                    let webView = WKWebView()
                    webView.load(URLRequest(url: url))
                    context.coordinator.webView = webView
                }
            }
        }

        // Temporary empty webView; will be replaced once configuration is ready
        let placeholder = WKWebView()
        context.coordinator.webView = placeholder
        return placeholder
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op; we load once in makeUIView
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ReadabilityWebView
        var coordinator: ReadabilityWebCoordinator?
        var webView: WKWebView?

        init(_ parent: ReadabilityWebView) {
            self.parent = parent
        }

        func startReaderTasks() {
            guard let coordinator, let webView else { return }

            // Apply reader HTML when available
            Task {
                for await html in coordinator.contentParsed {
                    do {
                        try await webView.showReaderContent(with: html)
                        try await webView.set(theme: .light)
                        try await webView.set(fontSize: .size5)
                    } catch {
                        // Ignore styling errors for now
                    }
                }
            }

            // Optionally observe availabilityChanged if you want a toggle button
            Task {
                for await _ in coordinator.availabilityChanged {
                    // You could update some SwiftUI state here to show/hide a "Reader" toggle
                }
            }
        }
    }
}
