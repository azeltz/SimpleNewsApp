//
//  ArticleDetailView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import SwiftUI
import UIKit
import WebKit

func plainText(from html: String) -> String {
    guard let data = html.data(using: .utf8) else { return html }
    if let attributed = try? NSAttributedString(
        data: data,
        options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ],
        documentAttributes: nil
    ) {
        return attributed.string
    }
    return html
}

func clippedText(from fullText: String, maxCharacters: Int = 1000) -> String {
    guard fullText.count > maxCharacters else { return fullText }
    let idx = fullText.index(fullText.startIndex, offsetBy: maxCharacters)
    return String(fullText[..<idx]) + "…"
}

func isGoogleNewsHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    if host == "news.google.com" || host.hasSuffix(".news.google.com") { return true }
    if host.hasPrefix("news.google.") { return true }
    return false
}

func unwrapGoogleNewsRedirect(_ url: URL?) -> URL? {
    guard let url else { return nil }
    guard isGoogleNewsHost(url.host) else { return url }
    guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
    if let target = comps.queryItems?.first(where: { $0.name == "url" || $0.name == "u" })?.value,
       let unwrapped = URL(string: target) {
        return unwrapped
    }
    return url
}

fileprivate let articleDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

// Simple ShareSheet wrapper around UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let customActivities: [UIActivity] = [
            CopyLinkActivity()
        ]
        return UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: customActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ArticleDetailView: View {
    let article: Article
    let showImages: Bool
    let enableInLineView: Bool
    let onToggleSaved: () -> Void
    
    @State private var showSafari: Bool = false
    @State private var isSaved: Bool
    @StateObject private var readerLoader = ReaderLoader()
    @StateObject private var readerController = ReaderController()
    @State private var readerHeight: CGFloat = 0
    @State private var showShareSheet: Bool = false
    
    @Environment(\.openURL) private var openURL
    
    init(
        article: Article,
        showImages: Bool,
        enableInLineView: Bool,
        onToggleSaved: @escaping () -> Void
    ) {
        self.article = article
        self.showImages = showImages
        self.enableInLineView = enableInLineView
        self.onToggleSaved = onToggleSaved
        _isSaved = State(initialValue: article.isSaved)
    }
    
    // Helper to decide what text to show if reader is off or fails
    private func bodyText(for article: Article) -> String? {
        if let content = article.content,
           !content.isEmpty,
           content != "ONLY AVAILABLE IN PAID PLANS" {
            return content
        }
        
        if let description = article.description, !description.isEmpty {
            return description
        }
        
        return nil
    }
    
    // Items to share (URL preferred, fallback to text)
    private var shareItems: [Any] {
        var items: [Any] = []
        
        // URL for normal sharing + Copy Link
        if let url = article.url {
            items.append(url)
        }
        
        // Body text (for generic sharing)
        var body = ""
        if let text = bodyText(for: article) {
            body = text
        }
        items.append(body)
        items.append(article.title)
        
        return items
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header image
                if showImages, let url = article.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Color.gray.opacity(0.1)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.gray.opacity(0.1)
                        @unknown default:
                            Color.gray.opacity(0.1)
                        }
                    }
                    .frame(height: 220)
                    .clipped()
                    .cornerRadius(12)
                }
                
                // Title
                Text(article.title)
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.leading)
                
                // Date
                if let publishedAt = article.publishedAt {
                    Text(articleDateFormatter.string(from: publishedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Source
                if let source = article.source {
                    Text(source)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Tags
                if !article.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(article.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                )
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider()
                
                // Show summary if reader is disabled OR reader has not loaded/failed
                if !enableInLineView || readerLoader.readerHTML == nil {
                    if let text = bodyText(for: article) {
                        Text(text)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("No content available.")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Link actions + optional reader content
                if let url = article.url {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Read full article")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            Button {
                                showSafari = true
                            } label: {
                                Label("Open in reader", systemImage: "doc.text.magnifyingglass")
                                    .font(.subheadline)
                            }
                            
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open in browser", systemImage: "arrow.up.right.square")
                                    .font(.subheadline)
                            }
                        }
                        .tint(Color.blue)
                    }
                    
                    // Inline reader – only when enabled in settings
                    if enableInLineView {
                        if let html = readerLoader.readerHTML {
                            ReaderHTMLView(
                                html: html,
                                height: $readerHeight,
                                controller: readerController
                            )
                            .frame(height: readerHeight)
                        } else if readerLoader.isLoading {
                            ProgressView("Loading article…")
                        } else if let error = readerLoader.error {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            // If the resolved URL is still a Google News redirect, advise using Safari reader
                            if let baseURL = article.url {
                                let resolved = unwrapGoogleNewsRedirect(baseURL) ?? baseURL
                                if isGoogleNewsHost(resolved.host) {
                                    Text("Inline reader isn’t available for this Google News redirect. Use ‘Open in reader’ instead.")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(article.source ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    onToggleSaved()
                    isSaved.toggle()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }
                
                // Export menu (PDF / Image from WKWebView content)
                Menu {
                    Button("Export as PDF") {
                        exportAsPDF()
                    }
                    .disabled(!readerController.isLoaded)
                    
                    Button("Export as Image") {
                        exportAsImage()
                    }
                    .disabled(!readerController.isLoaded)
                } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
                }
                
                // Regular share (link + text + Copy Link)
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .tint(.blue)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
        .fullScreenCover(isPresented: $showSafari) {
            if let url = article.url {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .task {
            guard enableInLineView else { return }
            guard let baseURL = article.url else { return }
            let resolved = unwrapGoogleNewsRedirect(baseURL) ?? baseURL
            print("Inline reader loading:", resolved.absoluteString)
            await readerLoader.load(from: resolved)
        }
    }
    
    // MARK: - WKWebView-based exports
    
    /// Injects a temporary light-mode stylesheet, runs an async action, then removes the stylesheet.
    private func withTemporaryLightMode(on webView: WKWebView, completion: @escaping () -> Void) {
        // Remember old style
        let oldStyle = webView.overrideUserInterfaceStyle
        
        // Force light appearance
        webView.overrideUserInterfaceStyle = .light
        
        let injectCSS = """
        (function() {
            var existing = document.getElementById('simpleNews-light-export-style');
            if (existing) { return; }
            var style = document.createElement('style');
            style.id = 'simpleNews-light-export-style';
            style.innerHTML = `
                :root {
                    color-scheme: light;
                }
                body {
                    background-color: #ffffff !important;
                    color: #000000 !important;
                }
                body * {
                    background-color: transparent !important;
                    color: #000000 !important;
                }
                a {
                    color: #1a0dab !important;
                }
            `;
            document.head.appendChild(style);
        })();
        """
        
        webView.evaluateJavaScript(injectCSS) { _, error in
            if let error {
                print("withTemporaryLightMode: failed to inject CSS:", error)
            }
            
            // Run the export after CSS is applied
            completion()
            
            // Remove style & restore appearance after a short delay
            let removeCSS = """
            (function() {
                var style = document.getElementById('simpleNews-light-export-style');
                if (style && style.parentNode) {
                    style.parentNode.removeChild(style);
                }
            })();
            """
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                webView.evaluateJavaScript(removeCSS, completionHandler: nil)
                webView.overrideUserInterfaceStyle = oldStyle
            }
        }
    }
    
    private func exportAsPDF() {
        guard
            enableInLineView,
            readerController.isLoaded,
            let webView = readerController.webView
        else {
            print("exportAsPDF: reader not ready")
            return
        }
        
        // Inject title at top of body
        let injectTitle = """
        (function() {
            var titleDiv = document.createElement('div');
            titleDiv.style.fontSize = '28px';
            titleDiv.style.fontWeight = 'bold';
            titleDiv.style.marginBottom = '16px';
            titleDiv.innerText = \(jsonEscape(article.title));
            document.body.insertBefore(titleDiv, document.body.firstChild);
        })();
        """
        
        let contentSize = webView.scrollView.contentSize
        let pdfConfig = WKPDFConfiguration()
        pdfConfig.rect = CGRect(origin: .zero, size: contentSize)
        
        withTemporaryLightMode(on: webView) {
            webView.evaluateJavaScript(injectTitle) { _, error in
                if let error {
                    print("exportAsPDF: failed to inject title:", error)
                }
                
                webView.createPDF(configuration: pdfConfig) { result in
                    switch result {
                    case .success(let data):
                        let url = URL(fileURLWithPath: NSTemporaryDirectory())
                            .appendingPathComponent("article-\(UUID().uuidString).pdf")
                        do {
                            try data.write(to: url)
                            presentShareSheet(for: [url])
                        } catch {
                            print("exportAsPDF: failed to write PDF:", error)
                        }
                    case .failure(let error):
                        print("exportAsPDF: failed to create PDF:", error)
                    }
                }
            }
        }
    }

    func jsonEscape(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string], options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\(string)\""
        }
        // Extract just the string part (remove [ and ])
        let trimmed = json.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return trimmed
    }

    
    private func exportAsImage() {
        let rawText: String
        if let html = readerLoader.readerHTML {
            rawText = plainText(from: html)
        } else {
            rawText = bodyText(for: article) ?? ""
        }
        
        let body = clippedText(from: rawText, maxCharacters: 5000)
        let targetSize = CGSize(width: 1080, height: 1350)
        
        let image = UIImage.imageForText(
            title: article.title,
            body: body,
            targetSize: targetSize
        )
        
        presentShareSheet(for: [image])
    }
}

extension UIImage {
    static func imageForText(
        title: String,
        body: String,
        targetSize: CGSize,
        minFont: CGFloat = 10,
        maxFont: CGFloat = 32
    ) -> UIImage {
        
        let inset: CGFloat = 24
        
        // 1) Draw title at fixed large font
        let titleFont = UIFont.boldSystemFont(ofSize: 50)
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .left
        titleParagraph.lineBreakMode = .byWordWrapping
        
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .paragraphStyle: titleParagraph,
            .foregroundColor: UIColor.black
        ]
        
        // Measure title height
        let titleRect = CGRect(
            x: inset,
            y: inset,
            width: targetSize.width - inset * 2,
            height: targetSize.height // temp large
        )
        let titleBounding = (title as NSString).boundingRect(
            with: CGSize(width: titleRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: titleAttrs,
            context: nil
        )
        
        let titleHeight = titleBounding.height
        let spacing: CGFloat = 16
        
        // 2) Binary‑search body font to fit remaining space
        let bodyMaxHeight = targetSize.height - inset - titleHeight - spacing - inset
        
        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.alignment = .left
        bodyParagraph.lineBreakMode = .byWordWrapping
        
        var low = minFont
        var high = maxFont
        var bestFont = minFont
        
        while high - low > 0.5 {
            let mid = (low + high) / 2
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: mid),
                .paragraphStyle: bodyParagraph
            ]
            let bounding = (body as NSString).boundingRect(
                with: CGSize(width: titleRect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: attrs,
                context: nil
            )
            
            if bounding.height <= bodyMaxHeight {
                bestFont = mid
                low = mid
            } else {
                high = mid
            }
        }
        
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: bestFont),
            .paragraphStyle: bodyParagraph,
            .foregroundColor: UIColor.black
        ]
        
        // 3) Render
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            
            // Draw title
            (title as NSString).draw(
                with: titleRect,
                options: [.usesLineFragmentOrigin],
                attributes: titleAttrs,
                context: nil
            )
            
            // Draw body below
            let bodyY = inset + titleHeight + spacing
            let bodyRect = CGRect(
                x: inset,
                y: bodyY,
                width: targetSize.width - inset * 2,
                height: bodyMaxHeight
            )
            
            (body as NSString).draw(
                with: bodyRect,
                options: [.usesLineFragmentOrigin],
                attributes: bodyAttrs,
                context: nil
            )
        }
    }
}

