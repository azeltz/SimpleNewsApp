//
//  CustomShareActivities.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/18/26.
//

import UIKit

// MARK: - Global helper to present a secondary share sheet

private func topViewController(from root: UIViewController?) -> UIViewController? {
    guard let root = root else { return nil }

    if let nav = root as? UINavigationController {
        return topViewController(from: nav.visibleViewController)
    }
    if let tab = root as? UITabBarController {
        return topViewController(from: tab.selectedViewController)
    }
    if let presented = root.presentedViewController {
        return topViewController(from: presented)
    }
    return root
}

func presentShareSheet(for items: [Any]) {
    Log.export.debug("presentShareSheet called")

    guard
        let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
        let keyWindow = scene.windows.first(where: { $0.isKeyWindow }),
        let root = keyWindow.rootViewController,
        let top = topViewController(from: root)
    else {
        Log.export.error("presentShareSheet: could not resolve top view controller")
        return
    }

    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

    if let pop = controller.popoverPresentationController {
        pop.sourceView = top.view
        pop.sourceRect = CGRect(x: top.view.bounds.midX,
                                y: top.view.bounds.midY,
                                width: 0,
                                height: 0)
        pop.permittedArrowDirections = []
    }

    top.present(controller, animated: true) {
        Log.export.debug("presentShareSheet: presented secondary share sheet")
    }
}

// MARK: - Filename helper

/// Sanitizes a string to be filesystem-safe (removes/replaces illegal characters)
func sanitizeFilename(_ input: String, maxLength: Int = 50) -> String {
    let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    let sanitized = input
        .components(separatedBy: invalidChars)
        .joined(separator: "-")
        .replacingOccurrences(of: " ", with: "-")
    
    let trimmed = String(sanitized.prefix(maxLength))
    return trimmed.isEmpty ? "article" : trimmed
}

// MARK: - Text → Image helper

/// Renders a white image with a large title, source+timestamp line, and big body text.
/// When a hero image is provided it is drawn in the top-right corner at correct aspect
/// ratio with the title/body text wrapping around it.
func imageFrom(text: String, title: String?, sourceLine: String?, heroImage: UIImage? = nil) -> UIImage {
    let size = CGSize(width: 1080, height: 1350)
    let inset: CGFloat = 32
    let contentWidth = size.width - inset * 2
    let renderer = UIGraphicsImageRenderer(size: size)

    return renderer.image { _ in
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        let titleFont = UIFont.boldSystemFont(ofSize: 40)
        let metaFont  = UIFont.systemFont(ofSize: 20)
        let bodyFont  = UIFont.systemFont(ofSize: 26)

        // Hero image: top-right corner, correct aspect ratio
        let heroGap: CGFloat = 16
        var heroRect: CGRect = .zero
        var heroBottomY: CGFloat = inset // where the hero image ends vertically
        if let hero = heroImage {
            let maxW: CGFloat = contentWidth * 0.35
            let maxH: CGFloat = 280
            let aspect = hero.size.width / max(hero.size.height, 1)
            var drawW = maxW
            var drawH = drawW / aspect
            if drawH > maxH {
                drawH = maxH
                drawW = drawH * aspect
            }
            heroRect = CGRect(
                x: size.width - inset - drawW,
                y: inset,
                width: drawW,
                height: drawH
            )
            hero.draw(in: heroRect)
            heroBottomY = heroRect.maxY + heroGap
        }

        var y: CGFloat = inset

        // Helper: available text width at current y (narrower while beside hero)
        func textWidth(at yPos: CGFloat) -> CGFloat {
            if heroRect != .zero && yPos < heroBottomY {
                return contentWidth - heroRect.width - heroGap
            }
            return contentWidth
        }

        // Title
        if let title, !title.isEmpty {
            let tw = textWidth(at: y)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]
            let str = NSAttributedString(string: title, attributes: attrs)
            let bounds = str.boundingRect(
                with: CGSize(width: tw, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            str.draw(in: CGRect(x: inset, y: y, width: tw, height: ceil(bounds.height)))
            y += ceil(bounds.height) + 8
        }

        // Source + timestamp
        if let sourceLine, !sourceLine.isEmpty {
            let tw = textWidth(at: y)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: metaFont,
                .foregroundColor: UIColor.darkGray
            ]
            let str = NSAttributedString(string: sourceLine, attributes: attrs)
            let bounds = str.boundingRect(
                with: CGSize(width: tw, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            str.draw(in: CGRect(x: inset, y: y, width: tw, height: ceil(bounds.height)))
            y += ceil(bounds.height) + 24
        } else {
            y += 16
        }

        // Body – use Core Text to wrap around hero image
        let bodyAttr = NSAttributedString(
            string: text,
            attributes: [
                .font: bodyFont,
                .foregroundColor: UIColor.black
            ]
        )

        let bodyBottom = size.height - inset
        let bodyHeight = bodyBottom - y
        guard bodyHeight > 0 else { return }

        // Full body rect in UIKit coordinates
        let fullBodyRect = CGRect(x: inset, y: y, width: contentWidth, height: bodyHeight)

        // Convert to Core Text flipped coordinates
        let ctBodyRect = CGRect(
            x: fullBodyRect.minX,
            y: size.height - fullBodyRect.maxY,
            width: fullBodyRect.width,
            height: fullBodyRect.height
        )

        // Exclusion zone for hero image remainder (portion that overlaps body area)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)

        let framePath = CGMutablePath()
        framePath.addRect(ctBodyRect)

        if heroRect != .zero && y < heroBottomY {
            // Exclusion rect in CT flipped coords
            let exclUIKit = CGRect(
                x: heroRect.minX - heroGap,
                y: y,
                width: heroRect.width + heroGap,
                height: heroBottomY - y
            )
            let exclCT = CGRect(
                x: exclUIKit.minX,
                y: size.height - exclUIKit.maxY,
                width: exclUIKit.width,
                height: exclUIKit.height
            )
            framePath.addRect(exclCT)
        }

        let framesetter = CTFramesetterCreateWithAttributedString(bodyAttr)
        let frameAttrs: [CFString: Any] = [
            kCTFrameClippingPathsAttributeName: [] as CFArray
        ]
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), framePath, frameAttrs as CFDictionary)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }
}

// MARK: - Copy link activity

final class CopyLinkActivity: UIActivity {
    private var url: URL?

    override var activityTitle: String? { "Copy Link" }
    override var activityImage: UIImage? { UIImage(systemName: "link") }
    override class var activityCategory: UIActivity.Category { .action }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        activityItems.contains { $0 is URL }
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        url = activityItems.first { $0 is URL } as? URL
    }

    override func perform() {
        Log.export.debug("CopyLinkActivity.perform called")

        if let url {
            UIPasteboard.general.string = url.absoluteString
            activityDidFinish(true)
        } else {
            activityDidFinish(false)
        }
    }
}

// MARK: - Export as PDF

final class ExportPDFActivity: UIActivity {
    private var bodyText: String?
    private var titleText: String?
    private var sourceText: String?
    private var timestampText: String?
    private var heroImage: UIImage?

    override var activityTitle: String? { "Export as PDF" }
    override var activityImage: UIImage? { UIImage(systemName: "doc.richtext") }
    override class var activityCategory: UIActivity.Category { .action }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        activityItems.contains { $0 is String }
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        heroImage = activityItems.first { $0 is UIImage } as? UIImage
        let strings = activityItems.compactMap { $0 as? String }
        if strings.count > 0 { bodyText = strings[0] }
        if strings.count > 1 { titleText = strings[1] }
        if strings.count > 2 { sourceText = strings[2] }
        if strings.count > 3 { timestampText = strings[3] }
    }

    override func perform() {
        Log.export.debug("ExportPDFActivity.perform called")

        guard let bodyText else {
            Log.export.warning("ExportPDFActivity: missing bodyText")
            activityDidFinish(false)
            return
        }

        let meta: [CFString: Any] = [
            kCGPDFContextCreator: "SimpleNews",
            kCGPDFContextTitle: titleText ?? "Article"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = meta as [String: Any]

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let inset: CGFloat = 32
        let insetRect = pageRect.insetBy(dx: inset, dy: inset)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { ctx in
            let titleFont  = UIFont.boldSystemFont(ofSize: 24)
            let metaFont   = UIFont.systemFont(ofSize: 14)
            let bodyFont   = UIFont.systemFont(ofSize: 14)
            let pageNumFont = UIFont.systemFont(ofSize: 10)

            // Prebuild header attributed strings
            var headerTitleAttr: NSAttributedString?
            if let titleText {
                headerTitleAttr = NSAttributedString(
                    string: titleText,
                    attributes: [
                        .font: titleFont,
                        .foregroundColor: UIColor.black
                    ]
                )
            }

            let metaLine: String
            if let source = sourceText, !source.isEmpty {
                if let ts = timestampText, !ts.isEmpty {
                    metaLine = "\(source)   •   \(ts)"
                } else {
                    metaLine = source
                }
            } else if let ts = timestampText, !ts.isEmpty {
                metaLine = ts
            } else {
                metaLine = ""
            }

            var headerMetaAttr: NSAttributedString?
            if !metaLine.isEmpty {
                headerMetaAttr = NSAttributedString(
                    string: metaLine,
                    attributes: [
                        .font: metaFont,
                        .foregroundColor: UIColor.black
                    ]
                )
            }

            // Body attributed string & framesetter
            let bodyAttr = NSAttributedString(
                string: bodyText,
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: UIColor.black
                ]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(bodyAttr)
            var currentLocation: CFIndex = 0
            var pageNumber = 1

            let capturedHeroImage = self.heroImage
            let heroGap: CGFloat = 8
            var pdfHeroRect: CGRect = .zero
            var pdfHeroBottomY: CGFloat = insetRect.minY

            // Compute hero image rect once (top-right corner of first page)
            if let hero = capturedHeroImage {
                let maxW = insetRect.width * 0.35
                let maxH: CGFloat = 160
                let aspect = hero.size.width / max(hero.size.height, 1)
                var drawW = maxW
                var drawH = drawW / aspect
                if drawH > maxH {
                    drawH = maxH
                    drawW = drawH * aspect
                }
                pdfHeroRect = CGRect(
                    x: insetRect.maxX - drawW,
                    y: insetRect.minY,
                    width: drawW,
                    height: drawH
                )
                pdfHeroBottomY = pdfHeroRect.maxY + heroGap
            }

            func drawHeader(in context: CGContext, isFirstPage: Bool) -> CGFloat {
                var y = insetRect.minY

                // Draw hero image in top-right corner on first page only
                if isFirstPage, let hero = capturedHeroImage {
                    hero.draw(in: pdfHeroRect)
                }

                let textWidth: CGFloat = isFirstPage && pdfHeroRect != .zero
                    ? insetRect.width - pdfHeroRect.width - heroGap
                    : insetRect.width

                if let titleAttr = headerTitleAttr {
                    let bounds = titleAttr.boundingRect(
                        with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    titleAttr.draw(
                        in: CGRect(x: insetRect.minX,
                                   y: y,
                                   width: textWidth,
                                   height: ceil(bounds.height))
                    )
                    y += ceil(bounds.height) + 4
                }

                if let metaAttr = headerMetaAttr {
                    let bounds = metaAttr.boundingRect(
                        with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    metaAttr.draw(
                        in: CGRect(x: insetRect.minX,
                                   y: y,
                                   width: textWidth,
                                   height: ceil(bounds.height))
                    )
                    y += ceil(bounds.height) + 16
                } else {
                    y += 8
                }

                // Ensure body starts below the hero image on page 1
                if isFirstPage && y < pdfHeroBottomY {
                    // Don't push y down — let Core Text wrap around via exclusion
                }

                return y
            }

            func drawPageNumber(_ num: Int, in context: CGContext) {
                let pageNumStr = "\(num)"
                let pageNumAttr = NSAttributedString(
                    string: pageNumStr,
                    attributes: [
                        .font: pageNumFont,
                        .foregroundColor: UIColor.darkGray
                    ]
                )
                let size = pageNumAttr.size()
                let x = (pageRect.width - size.width) / 2
                let y = pageRect.height - inset + 8  // 8pt below inset
                pageNumAttr.draw(at: CGPoint(x: x, y: y))
            }

            while currentLocation < bodyAttr.length {
                ctx.beginPage()

                // Draw header in UIKit coordinates
                let headerBottomY = drawHeader(in: ctx.cgContext, isFirstPage: pageNumber == 1)

                // Draw page number at bottom
                drawPageNumber(pageNumber, in: ctx.cgContext)

                // Flip context for Core Text
                let cg = ctx.cgContext
                cg.saveGState()
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: pageRect.height)
                cg.scaleBy(x: 1.0, y: -1.0)

                // Frame rect in flipped coordinates
                let frameHeight = insetRect.maxY - headerBottomY
                let frameRect = CGRect(
                    x: insetRect.minX,
                    y: pageRect.height - headerBottomY - frameHeight,
                    width: insetRect.width,
                    height: frameHeight
                )

                let framePath = CGMutablePath()
                framePath.addRect(frameRect)

                // On the first page, add an exclusion rect for the hero image
                // so body text wraps around it
                if pageNumber == 1 && pdfHeroRect != .zero && headerBottomY < pdfHeroBottomY {
                    let exclHeight = pdfHeroBottomY - headerBottomY
                    let exclUIKit = CGRect(
                        x: pdfHeroRect.minX - heroGap,
                        y: headerBottomY,
                        width: pdfHeroRect.width + heroGap,
                        height: exclHeight
                    )
                    // Convert to CT flipped coords
                    let exclCT = CGRect(
                        x: exclUIKit.minX,
                        y: pageRect.height - exclUIKit.maxY,
                        width: exclUIKit.width,
                        height: exclUIKit.height
                    )
                    framePath.addRect(exclCT)
                }

                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: currentLocation, length: 0),
                    framePath,
                    nil
                )

                CTFrameDraw(frame, cg)
                cg.restoreGState()

                let visibleRange = CTFrameGetVisibleStringRange(frame)
                if visibleRange.length == 0 { break }
                currentLocation += visibleRange.length
                pageNumber += 1
            }
        }

        // Filename: title + timestamp
        let ts = Int(Date().timeIntervalSince1970)
        let baseName = sanitizeFilename(titleText ?? "article")
        let filename = "\(baseName)-\(ts).pdf"
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(filename)

        do {
            try data.write(to: url)
            Log.export.debug("ExportPDFActivity: wrote PDF")
            presentShareSheet(for: [url])
            activityDidFinish(true)
        } catch {
            Log.export.error("ExportPDFActivity: failed to write PDF: \(error)")
            activityDidFinish(false)
        }
    }
}

// MARK: - Export as Image

final class ExportImageActivity: UIActivity {
    private var bodyText: String?
    private var titleText: String?
    private var sourceText: String?
    private var timestampText: String?
    private var heroImage: UIImage?

    override var activityTitle: String? { "Export as Image" }
    override var activityImage: UIImage? { UIImage(systemName: "photo") }
    override class var activityCategory: UIActivity.Category { .action }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        activityItems.contains { $0 is String }
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        heroImage = activityItems.first { $0 is UIImage } as? UIImage
        let strings = activityItems.compactMap { $0 as? String }
        if strings.count > 0 { bodyText = strings[0] }
        if strings.count > 1 { titleText = strings[1] }
        if strings.count > 2 { sourceText = strings[2] }
        if strings.count > 3 { timestampText = strings[3] }
    }

    override func perform() {
        Log.export.debug("ExportImageActivity.perform called")

        guard let bodyText else {
            Log.export.warning("ExportImageActivity: missing bodyText")
            activityDidFinish(false)
            return
        }

        let metaLine: String
        if let source = sourceText, !source.isEmpty {
            if let ts = timestampText, !ts.isEmpty {
                metaLine = "\(source)   •   \(ts)"
            } else {
                metaLine = source
            }
        } else if let ts = timestampText, !ts.isEmpty {
            metaLine = ts
        } else {
            metaLine = ""
        }

        let image = imageFrom(text: bodyText, title: titleText, sourceLine: metaLine, heroImage: heroImage)
        Log.export.debug("ExportImageActivity: generated image")
        
        // Generate filename from title + timestamp
        let timestamp = Int(Date().timeIntervalSince1970)
        let baseName = sanitizeFilename(titleText ?? "article")
        let filename = "\(baseName)-\(timestamp).png"
        
        // Save to temp directory for sharing
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        if let pngData = image.pngData() {
            do {
                try pngData.write(to: tempURL)
                Log.export.debug("ExportImageActivity: wrote image")
                presentShareSheet(for: [tempURL])
            } catch {
                Log.export.error("ExportImageActivity: failed to write image: \(error)")
                presentShareSheet(for: [image])
            }
        } else {
            presentShareSheet(for: [image])
        }
        
        activityDidFinish(true)
    }
}
