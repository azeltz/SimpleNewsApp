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
    print("presentShareSheet called with items: \(items)")

    guard
        let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
        let keyWindow = scene.windows.first(where: { $0.isKeyWindow }),
        let root = keyWindow.rootViewController,
        let top = topViewController(from: root)
    else {
        print("presentShareSheet: could not resolve top view controller")
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
        print("presentShareSheet: presented secondary share sheet from \(type(of: top))")
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
func imageFrom(text: String, title: String?, sourceLine: String?) -> UIImage {
    let size = CGSize(width: 1080, height: 1350)
    let renderer = UIGraphicsImageRenderer(size: size)

    return renderer.image { _ in
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        let titleFont = UIFont.boldSystemFont(ofSize: 40)
        let metaFont  = UIFont.systemFont(ofSize: 20)
        let bodyFont  = UIFont.systemFont(ofSize: 26)

        var y: CGFloat = 40

        // Title
        if let title, !title.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]
            let rect = CGRect(x: 32, y: y, width: size.width - 64, height: .greatestFiniteMagnitude)
            let str = NSAttributedString(string: title, attributes: attrs)
            let bounds = str.boundingRect(
                with: rect.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            str.draw(in: CGRect(x: 32, y: y, width: rect.width, height: ceil(bounds.height)))
            y += ceil(bounds.height) + 8
        }

        // Source + timestamp
        if let sourceLine, !sourceLine.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: metaFont,
                .foregroundColor: UIColor.darkGray
            ]
            let rect = CGRect(x: 32, y: y, width: size.width - 64, height: .greatestFiniteMagnitude)
            let str = NSAttributedString(string: sourceLine, attributes: attrs)
            let bounds = str.boundingRect(
                with: rect.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            str.draw(in: CGRect(x: 32, y: y, width: rect.width, height: ceil(bounds.height)))
            y += ceil(bounds.height) + 24
        } else {
            y += 16
        }

        // Body
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black
        ]
        let bodyRect = CGRect(x: 32, y: y, width: size.width - 64, height: size.height - y - 40)
        let bodyStr = NSAttributedString(string: text, attributes: bodyAttrs)
        bodyStr.draw(
            with: bodyRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
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
        print("CopyLinkActivity.perform called, url = \(String(describing: url))")

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

    override var activityTitle: String? { "Export as PDF" }
    override var activityImage: UIImage? { UIImage(systemName: "doc.richtext") }
    override class var activityCategory: UIActivity.Category { .action }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        activityItems.contains { $0 is String }
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        let strings = activityItems.compactMap { $0 as? String }
        if strings.count > 0 { bodyText = strings[0] }
        if strings.count > 1 { titleText = strings[1] }
        if strings.count > 2 { sourceText = strings[2] }
        if strings.count > 3 { timestampText = strings[3] }
    }

    override func perform() {
        print("ExportPDFActivity.perform called, bodyText = \(bodyText != nil)")

        guard let bodyText else {
            print("ExportPDFActivity: missing bodyText")
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

            func drawHeader(in context: CGContext) -> CGFloat {
                var y = insetRect.minY

                if let titleAttr = headerTitleAttr {
                    let bounds = titleAttr.boundingRect(
                        with: CGSize(width: insetRect.width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    titleAttr.draw(
                        in: CGRect(x: insetRect.minX,
                                   y: y,
                                   width: insetRect.width,
                                   height: ceil(bounds.height))
                    )
                    y += ceil(bounds.height) + 4
                }

                if let metaAttr = headerMetaAttr {
                    let bounds = metaAttr.boundingRect(
                        with: CGSize(width: insetRect.width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    metaAttr.draw(
                        in: CGRect(x: insetRect.minX,
                                   y: y,
                                   width: insetRect.width,
                                   height: ceil(bounds.height))
                    )
                    y += ceil(bounds.height) + 16
                } else {
                    y += 8
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
                let headerBottomY = drawHeader(in: ctx.cgContext)

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
                let path = CGPath(rect: frameRect, transform: nil)

                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: currentLocation, length: 0),
                    path,
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
            print("ExportPDFActivity: wrote PDF to \(url)")
            presentShareSheet(for: [url])
            activityDidFinish(true)
        } catch {
            print("ExportPDFActivity: failed to write PDF: \(error)")
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

    override var activityTitle: String? { "Export as Image" }
    override var activityImage: UIImage? { UIImage(systemName: "photo") }
    override class var activityCategory: UIActivity.Category { .action }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        activityItems.contains { $0 is String }
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        let strings = activityItems.compactMap { $0 as? String }
        if strings.count > 0 { bodyText = strings[0] }
        if strings.count > 1 { titleText = strings[1] }
        if strings.count > 2 { sourceText = strings[2] }
        if strings.count > 3 { timestampText = strings[3] }
    }

    override func perform() {
        print("ExportImageActivity.perform called, bodyText = \(bodyText != nil)")

        guard let bodyText else {
            print("ExportImageActivity: missing bodyText")
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

        let image = imageFrom(text: bodyText, title: titleText, sourceLine: metaLine)
        print("ExportImageActivity: generated image size = \(image.size)")
        
        // Generate filename from title + timestamp
        let timestamp = Int(Date().timeIntervalSince1970)
        let baseName = sanitizeFilename(titleText ?? "article")
        let filename = "\(baseName)-\(timestamp).png"
        
        // Save to temp directory for sharing
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        if let pngData = image.pngData() {
            do {
                try pngData.write(to: tempURL)
                print("ExportImageActivity: wrote image to \(tempURL)")
                presentShareSheet(for: [tempURL])
            } catch {
                print("ExportImageActivity: failed to write image: \(error)")
                presentShareSheet(for: [image])
            }
        } else {
            presentShareSheet(for: [image])
        }
        
        activityDidFinish(true)
    }
}
