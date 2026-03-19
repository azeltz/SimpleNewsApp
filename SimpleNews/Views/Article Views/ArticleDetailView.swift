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

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let customActivities: [UIActivity] = [
            CopyLinkActivity(),
            ExportPDFActivity(),
            ExportImageActivity()
        ]

        return UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: customActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ArticleDetailView: View {
    @Binding var article: Article
    let showImages: Bool
    let enableInLineView: Bool
    let hideArticleBodyImages: Bool
    let includeImageInExport: Bool
    let enableRichLinkPreviews: Bool
    let onToggleSaved: () -> Void
    var onImageDiscovered: ((String, URL) -> Void)? = nil

    @State private var showSafari: Bool = false
    @StateObject private var readerLoader = ReaderLoader()
    @StateObject private var readerController = ReaderController()
    @State private var readerHeight: CGFloat = 0
    @State private var showShareSheet: Bool = false
    @State private var cachedShareBody: String = ""
    @State private var cachedHeroImage: UIImage? = nil
    @State private var isPreparingShare: Bool = false
    @State private var oEmbedHTML: String?

    @Environment(\.openURL) private var openURL

    /// Derived from the binding so it always stays in sync.
    private var isSaved: Bool { article.isSaved }

    /// The article's hero/cover image URL used for deduplication.
    private var heroImageURL: URL? {
        article.imageURL ?? article.readerImageURL
    }

    /// Persistent data store for the article's domain if the user is logged in.
    private var subscriptionDataStore: WKWebsiteDataStore? {
        guard let host = article.url?.host else { return nil }
        return SubscriptionStore.shared.dataStoreForDomain(host)
    }

    // MARK: - Helpers

    private func cleanReaderText(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let filtered = lines.filter { line in
            guard !line.isEmpty else { return false }

            let lower = line.lowercased()

            // 1. Drop pure ISO timestamp / date lines
            if line.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2}"#,
                          options: .regularExpression) != nil {
                return false
            }

            // 2. Drop short lines that are just the host or similar
            if lower == "eurohoops.net" { return false }
            if lower.contains("eurohoops.net") && lower.count < 40 { return false }

            // 3. Drop sequences that look like "2026-02-20T... Eurohoops.net"
            if lower.contains("eurohoops.net"),
               line.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}"#,
                          options: .regularExpression) != nil {
                return false
            }

            return true
        }

        return filtered.joined(separator: "\n")
    }

    private func bodyText(for article: Article) -> String? {
        // 1. If feed content/description exists, always use that.
        if let content = article.content,
           !content.isEmpty,
           content != "ONLY AVAILABLE IN PAID PLANS" {
            return content
        }

        if let description = article.description,
           !description.isEmpty {
            return description
        }

        // 2. Only when BOTH are missing, fall back to cleaned readerHTML.
        if let html = readerLoader.readerHTML, !html.isEmpty {
            let text = plainText(from: html)
            let cleaned = cleanReaderText(text)
            if !cleaned.isEmpty { return cleaned }
        }

        return nil
    }
    
    /// Full text used for PDF / image / share exports.
    /// Prefer cleaned reader HTML when available so exports match the reader view.
    private func exportBodyText(for article: Article) -> String {
        // 1. If we have readerHTML, use the cleaned version (full article).
        if let html = readerLoader.readerHTML, !html.isEmpty {
            let text = plainText(from: html)
            let cleaned = cleanReaderText(text)
            if !cleaned.isEmpty { return cleaned }
        }

        // 2. Fall back to feed content/description.
        if let content = article.content,
           !content.isEmpty,
           content != "ONLY AVAILABLE IN PAID PLANS" {
            return content
        }

        if let description = article.description,
           !description.isEmpty {
            return description
        }

        // 3. Last resort: empty string.
        return ""
    }

    private var shareItems: [Any] {
        var items: [Any] = []

        if let url = article.url {
            items.append(url)
        }

        // Include the hero image for export activities when enabled
        if includeImageInExport, let hero = cachedHeroImage {
            items.append(hero)
        }

        items.append(cachedShareBody)
        items.append(article.title)

        let sourceString: String
        if let source = article.source, !source.isEmpty {
            sourceString = "Source: \(source)"
        } else if let host = article.url?.host {
            sourceString = "Source: \(host)"
        } else {
            sourceString = ""
        }
        items.append(sourceString)

        let timestampString: String
        if let publishedAt = article.publishedAt {
            timestampString = articleDateFormatter.string(from: publishedAt)
        } else {
            timestampString = ""
        }
        items.append(timestampString)

        return items
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showImages {
                    let headerURL = article.imageURL ?? article.readerImageURL
                    if let url = headerURL {
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
                        .frame(width: UIScreen.main.bounds.width - 32, height: 220)
                        .clipped()
                        .cornerRadius(12)
                    }
                }

                Text(article.title)
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.leading)

                if let publishedAt = article.publishedAt {
                    Text(articleDateFormatter.string(from: publishedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let source = article.source {
                    Text(source)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

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

                if let url = article.url {
                    // oEmbed rich preview (shown inline when available)
                    if let embedHTML = oEmbedHTML {
                        Divider()
                        OEmbedWebView(embedHTML: embedHTML)
                    }

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

                    // Skip inline reader when oEmbed is already shown
                    if enableInLineView && oEmbedHTML == nil {
                        if let html = readerLoader.readerHTML {
                            let cleanHTML = HTMLImageCleaner.cleaned(
                                html: html,
                                heroURL: heroImageURL,
                                hideAllImages: hideArticleBodyImages
                            )
                            ReaderHTMLView(
                                html: cleanHTML,
                                height: $readerHeight,
                                controller: readerController,
                                subscriptionDataStore: subscriptionDataStore,
                                onImageFound: { url in
                                    if article.imageURL == nil {
                                        article.readerImageURL = url
                                        onImageDiscovered?(article.id, url)
                                    }
                                }
                            )
                            .frame(height: readerHeight)
                        } else if readerLoader.isLoading {
                            ProgressView("Loading article…")
                        } else if readerLoader.extractionFailed {
                            // Readability failed (JS-rendered sites like Ynet).
                            // Show feed text and prompt to open in browser.
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Inline reader not available", systemImage: "doc.text.magnifyingglass")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                Text("This article's content could not be extracted. Use the buttons above to read the full article in Safari.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        } else if let error = readerLoader.error {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            if let baseURL = article.url {
                                let resolved = unwrapGoogleNewsRedirect(baseURL) ?? baseURL
                                if isGoogleNewsHost(resolved.host) {
                                    Text("Inline reader isn't available for this Google News redirect. Use 'Open in reader' instead.")
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    onToggleSaved()
                    article.isSaved.toggle()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        // Ensure hero image is downloaded before showing the share sheet
                        if includeImageInExport && cachedHeroImage == nil, let hero = heroImageURL {
                            isPreparingShare = true
                            cachedHeroImage = await downloadImage(from: hero)
                            isPreparingShare = false
                        }
                        showShareSheet = true
                    }
                } label: {
                    if isPreparingShare {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isPreparingShare)
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
            // Try oEmbed first when rich link previews are enabled
            if enableRichLinkPreviews, let baseURL = article.url {
                let resolved = unwrapGoogleNewsRedirect(baseURL) ?? baseURL
                oEmbedHTML = await OEmbedService.fetchHTML(for: resolved)
            }

            // Only load the full reader if oEmbed didn't produce a result
            if oEmbedHTML == nil, enableInLineView, let baseURL = article.url {
                let resolved = unwrapGoogleNewsRedirect(baseURL) ?? baseURL
                readerLoader.hideFirstImage = showImages
                await readerLoader.load(from: resolved)
            }

            cachedShareBody = exportBodyText(for: article)

            // Pre-download hero image for exports
            if includeImageInExport, let hero = heroImageURL {
                cachedHeroImage = await downloadImage(from: hero)
            }
        }
    }

    // MARK: - WKWebView-based exports

    private func withTemporaryLightMode(on webView: WKWebView, completion: @escaping () -> Void) {
        let oldStyle = webView.overrideUserInterfaceStyle
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
                Log.export.error("withTemporaryLightMode: failed to inject CSS: \(error)")
            }

            completion()

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
            Log.export.warning("exportAsPDF: reader not ready")
            return
        }

        // Build JS that inserts an optional hero image + title at the top
        let heroJS: String
        if includeImageInExport, let hero = heroImageURL {
            heroJS = """
            var heroImg = document.createElement('img');
            heroImg.src = \(jsonEscape(hero.absoluteString));
            heroImg.style.maxWidth = '100%';
            heroImg.style.height = 'auto';
            heroImg.style.display = 'block';
            heroImg.style.marginBottom = '12px';
            heroImg.style.borderRadius = '8px';
            document.body.insertBefore(heroImg, document.body.firstChild);
            """
        } else {
            heroJS = ""
        }

        let injectTitle = """
        (function() {
            var titleDiv = document.createElement('div');
            titleDiv.style.fontSize = '28px';
            titleDiv.style.fontWeight = 'bold';
            titleDiv.style.marginBottom = '16px';
            titleDiv.innerText = \(jsonEscape(article.title));
            document.body.insertBefore(titleDiv, document.body.firstChild);
            \(heroJS)
        })();
        """

        let contentSize = webView.scrollView.contentSize
        let pdfConfig = WKPDFConfiguration()
        pdfConfig.rect = CGRect(origin: .zero, size: contentSize)

        withTemporaryLightMode(on: webView) {
            webView.evaluateJavaScript(injectTitle) { _, error in
                if let error {
                    Log.export.error("exportAsPDF: failed to inject title: \(error)")
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
                            Log.export.error("exportAsPDF: failed to write PDF: \(error)")
                        }
                    case .failure(let error):
                        Log.export.error("exportAsPDF: failed to create PDF: \(error)")
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
        let trimmed = json.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return trimmed
    }

    private func exportAsImage() {
        let rawText: String
        if let html = readerLoader.readerHTML {
            rawText = plainText(from: html)
        } else {
            rawText = exportBodyText(for: article)
        }

        let body = clippedText(from: rawText, maxCharacters: 5000)
        let targetSize = CGSize(width: 1080, height: 1350)

        if includeImageInExport, let hero = heroImageURL {
            // Download the hero image and draw it at the top of the export
            Task {
                let heroImage = await downloadImage(from: hero)
                let image = UIImage.imageForText(
                    title: article.title,
                    body: body,
                    targetSize: targetSize,
                    heroImage: heroImage
                )
                presentShareSheet(for: [image])
            }
        } else {
            let image = UIImage.imageForText(
                title: article.title,
                body: body,
                targetSize: targetSize
            )
            presentShareSheet(for: [image])
        }
    }

    private func downloadImage(from url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

extension UIImage {
    static func imageForText(
        title: String,
        body: String,
        targetSize: CGSize,
        minFont: CGFloat = 10,
        maxFont: CGFloat = 32,
        heroImage: UIImage? = nil
    ) -> UIImage {

        let inset: CGFloat = 24
        let contentWidth = targetSize.width - inset * 2
        let heroGap: CGFloat = 16

        // Hero image: top-right corner, correct aspect ratio
        var heroRect: CGRect = .zero
        var heroBottomY: CGFloat = inset
        if let hero = heroImage {
            let maxW = contentWidth * 0.35
            let maxH: CGFloat = 300
            let aspect = hero.size.width / max(hero.size.height, 1)
            var drawW = maxW
            var drawH = drawW / aspect
            if drawH > maxH {
                drawH = maxH
                drawW = drawH * aspect
            }
            heroRect = CGRect(
                x: targetSize.width - inset - drawW,
                y: inset,
                width: drawW,
                height: drawH
            )
            heroBottomY = heroRect.maxY + heroGap
        }

        let titleFont = UIFont.boldSystemFont(ofSize: 50)
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .left
        titleParagraph.lineBreakMode = .byWordWrapping

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .paragraphStyle: titleParagraph,
            .foregroundColor: UIColor.black
        ]

        // Title width narrows when beside hero
        let titleWidth = heroRect == .zero ? contentWidth : contentWidth - heroRect.width - heroGap

        let titleBounding = (title as NSString).boundingRect(
            with: CGSize(width: titleWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: titleAttrs,
            context: nil
        )

        let titleHeight = titleBounding.height
        let spacing: CGFloat = 16
        let bodyTopY = inset + titleHeight + spacing
        let bodyMaxHeight = targetSize.height - bodyTopY - inset

        let bodyFont = UIFont.systemFont(ofSize: 18)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()

            // Draw hero image
            if let hero = heroImage {
                hero.draw(in: heroRect)
            }

            // Draw title
            let titleDrawRect = CGRect(
                x: inset,
                y: inset,
                width: titleWidth,
                height: ceil(titleHeight)
            )
            (title as NSString).draw(
                with: titleDrawRect,
                options: [.usesLineFragmentOrigin],
                attributes: titleAttrs,
                context: nil
            )

            // Draw body with Core Text wrapping around hero
            let bodyAttr = NSAttributedString(
                string: body,
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: UIColor.black
                ]
            )

            guard bodyMaxHeight > 0 else { return }

            let fullBodyRect = CGRect(x: inset, y: bodyTopY, width: contentWidth, height: bodyMaxHeight)

            let ctx = UIGraphicsGetCurrentContext()!
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: 0, y: targetSize.height)
            ctx.scaleBy(x: 1, y: -1)

            // CT flipped body rect
            let ctBodyRect = CGRect(
                x: fullBodyRect.minX,
                y: targetSize.height - fullBodyRect.maxY,
                width: fullBodyRect.width,
                height: fullBodyRect.height
            )

            let framePath = CGMutablePath()
            framePath.addRect(ctBodyRect)

            // Exclusion for hero image if it extends into the body area
            if heroRect != .zero && bodyTopY < heroBottomY {
                let exclUIKit = CGRect(
                    x: heroRect.minX - heroGap,
                    y: bodyTopY,
                    width: heroRect.width + heroGap,
                    height: heroBottomY - bodyTopY
                )
                let exclCT = CGRect(
                    x: exclUIKit.minX,
                    y: targetSize.height - exclUIKit.maxY,
                    width: exclUIKit.width,
                    height: exclUIKit.height
                )
                framePath.addRect(exclCT)
            }

            let framesetter = CTFramesetterCreateWithAttributedString(bodyAttr)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), framePath, nil)
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()
        }
    }
}

#if DEBUG
#Preview("Article Detail") {
    PreviewWrapper {
        ArticleDetailView(
            article: .constant(PreviewData.sampleArticle),
            showImages: true,
            enableInLineView: true,
            hideArticleBodyImages: false,
            includeImageInExport: true,
            enableRichLinkPreviews: true,
            onToggleSaved: {}
        )
    }
}
#endif
