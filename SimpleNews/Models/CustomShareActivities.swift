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

    // iPad: configure popover source
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

// MARK: - Text → Image helper

/// Renders a white image with a large title, source line, and big body text.
func imageFrom(text: String, title: String?, source: String?) -> UIImage {
    let size = CGSize(width: 1080, height: 1350)
    let renderer = UIGraphicsImageRenderer(size: size)

    return renderer.image { _ in
        // Background
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        let titleFont = UIFont.boldSystemFont(ofSize: 40)
        let sourceFont = UIFont.systemFont(ofSize: 20)
        let bodyFont   = UIFont.systemFont(ofSize: 26)

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

        // Source (smaller, below title)
        if let source, !source.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: sourceFont,
                .foregroundColor: UIColor.darkGray
            ]
            let rect = CGRect(x: 32, y: y, width: size.width - 64, height: .greatestFiniteMagnitude)
            let str = NSAttributedString(string: source, attributes: attrs)
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
        if strings.count > 2 { sourceText = strings[2] } // optional source
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

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            let titleFont  = UIFont.boldSystemFont(ofSize: 24)  // bigger title
            let sourceFont = UIFont.systemFont(ofSize: 14)
            let bodyFont   = UIFont.systemFont(ofSize: 14)

            let insetRect = pageRect.insetBy(dx: 32, dy: 32)
            var y = insetRect.minY

            // Title
            if let titleText {
                let titleAttr = NSAttributedString(
                    string: titleText,
                    attributes: [
                        .font: titleFont,
                        .foregroundColor: UIColor.black
                    ]
                )
                let bounds = titleAttr.boundingRect(
                    with: CGSize(width: insetRect.width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                titleAttr.draw(in: CGRect(x: insetRect.minX,
                                          y: y,
                                          width: insetRect.width,
                                          height: ceil(bounds.height)))
                y += ceil(bounds.height) + 4
            }

            // Source – black text
            if let sourceText, !sourceText.isEmpty {
                let sourceAttr = NSAttributedString(
                    string: sourceText,
                    attributes: [
                        .font: sourceFont,
                        .foregroundColor: UIColor.black
                    ]
                )
                let bounds = sourceAttr.boundingRect(
                    with: CGSize(width: insetRect.width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                sourceAttr.draw(in: CGRect(x: insetRect.minX,
                                           y: y,
                                           width: insetRect.width,
                                           height: ceil(bounds.height)))
                y += ceil(bounds.height) + 16
            } else {
                y += 8
            }

            // Body
            let bodyAttr = NSAttributedString(
                string: bodyText,
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: UIColor.black
                ]
            )
            bodyAttr.draw(in: CGRect(x: insetRect.minX,
                                     y: y,
                                     width: insetRect.width,
                                     height: insetRect.maxY - y))
        }

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("article-\(UUID().uuidString).pdf")

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
        if strings.count > 2 { sourceText = strings[2] } // optional source
    }

    override func perform() {
        print("ExportImageActivity.perform called, bodyText = \(bodyText != nil)")

        guard let bodyText else {
            print("ExportImageActivity: missing bodyText")
            activityDidFinish(false)
            return
        }

        let image = imageFrom(text: bodyText, title: titleText, source: sourceText)
        print("ExportImageActivity: generated image size = \(image.size)")
        presentShareSheet(for: [image])
        activityDidFinish(true)
    }
}
