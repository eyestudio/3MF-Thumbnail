import AppKit
import QuickLookThumbnailing
import SceneKit

class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let fileURL = request.fileURL
        let maxSize = request.maximumSize
        let threeMF = ThreeMFFile(url: fileURL)

        // Try embedded thumbnail first
        if let imageData = try? threeMF.extractThumbnailData(),
           let image = NSImage(data: imageData),
           let imageRep = image.representations.first
        {
            let imageSize = CGSize(
                width: CGFloat(imageRep.pixelsWide),
                height: CGFloat(imageRep.pixelsHigh)
            )

            let scale = min(
                maxSize.width / imageSize.width,
                maxSize.height / imageSize.height
            )

            let thumbnailSize = CGSize(
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )

            let reply = QLThumbnailReply(contextSize: thumbnailSize) {
                image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                return true
            }
            handler(reply, nil)
            return
        }

        // Fallback: render 3D model
        if let modelData = try? threeMF.extractModelData() {
            let parser = ThreeMFMeshParser()
            if let scene = parser.parse(data: modelData) {
                let size = CGSize(width: maxSize.width, height: maxSize.height)
                let reply = QLThumbnailReply(contextSize: size) {
                    let renderer = SCNRenderer(device: nil, options: nil)
                    renderer.scene = scene
                    renderer.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
                    let snapshot = renderer.snapshot(
                        atTime: 0,
                        with: size,
                        antialiasingMode: .multisampling4X
                    )
                    snapshot.draw(in: CGRect(origin: .zero, size: size))
                    return true
                }
                handler(reply, nil)
                return
            }
        }

        // Last fallback: draw a simple placeholder
        let reply = QLThumbnailReply(contextSize: maxSize) {
            NSColor.systemBlue.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: CGRect(origin: .zero, size: maxSize), xRadius: 8, yRadius: 8).fill()
            let text = "3MF" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: maxSize.width * 0.25),
                .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (maxSize.width - textSize.width) / 2,
                y: (maxSize.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attrs)
            return true
        }
        handler(reply, nil)
    }
}
