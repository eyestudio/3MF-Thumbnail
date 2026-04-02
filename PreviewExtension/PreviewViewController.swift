import AppKit
import os.log
import QuickLookUI
import SceneKit

private let logger = OSLog(subsystem: "me.zhanghai.3mf-thumbnail.PreviewExtension", category: "preview")

class PreviewViewController: NSViewController, QLPreviewingController {
    private var objects: [ThreeMFObject] = []
    private var currentIndex = 0
    private var sceneCache: [Int: SCNScene] = [:]

    // UI
    private var contentView: NSView!
    private var bottomBar: NSView!
    private var collectionView: NSCollectionView!
    private var scnView: SCNView?
    private var imageView: NSImageView?
    private var loadingIndicator: NSProgressIndicator?

    private let thumbSize: CGFloat = 64
    private let barHeight: CGFloat = 80
    private let parseQueue = DispatchQueue(label: "me.zhanghai.3mf-thumbnail.parse", qos: .userInitiated)

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        contentView = NSView(frame: NSRect(x: 0, y: barHeight, width: 800, height: 520))
        contentView.autoresizingMask = [.width, .height]

        bottomBar = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: barHeight))
        bottomBar.autoresizingMask = [.width, .maxYMargin]
        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = NSColor(white: 0, alpha: 0.3).cgColor

        // Collection view
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: thumbSize, height: thumbSize)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.register(
            ThumbnailCell.self,
            forItemWithIdentifier: ThumbnailCell.identifier
        )

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: barHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = collectionView
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        bottomBar.addSubview(scrollView)

        root.addSubview(contentView)
        root.addSubview(bottomBar)

        self.view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let bounds = view.bounds

        if bottomBar.isHidden {
            contentView.frame = bounds
        } else {
            bottomBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
            contentView.frame = NSRect(x: 0, y: barHeight, width: bounds.width, height: bounds.height - barHeight)
        }
    }

    func preparePreviewOfFile(
        at url: URL, completionHandler handler: @escaping (Error?) -> Void
    ) {
        let threeMF = ThreeMFFile(url: url)

        os_log("=== START preview for: %{public}@", log: logger, type: .error, url.lastPathComponent)

        do {
            objects = try threeMF.extractAllObjects()
            os_log("Objects count: %d", log: logger, type: .error, objects.count)
            for (i, obj) in objects.enumerated() {
                os_log("  [%d] name=%{public}@ thumb=%d model=%d",
                       log: logger, type: .error,
                       i, obj.name,
                       obj.thumbnailData?.count ?? 0,
                       obj.modelData?.count ?? 0)
            }

            if objects.isEmpty {
                handler(ThreeMFError.noModelFound)
                return
            }

            if objects.count <= 1 {
                bottomBar.isHidden = true
            } else {
                bottomBar.isHidden = false
            }

            collectionView.reloadData()

            let firstIndex = IndexPath(item: 0, section: 0)
            collectionView.selectItems(at: [firstIndex], scrollPosition: .centeredHorizontally)
            showObject(at: 0)

            os_log("completed OK, showing index %d", log: logger, type: .error, currentIndex)
            handler(nil)
        } catch {
            os_log("ERROR: %{public}@", log: logger, type: .error, error.localizedDescription)
            handler(error)
        }
    }

    // MARK: - Display

    private func showLoadingIndicator() {
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        spinner.startAnimation(nil)
        loadingIndicator = spinner
    }

    private func clearContent() {
        for sub in contentView.subviews {
            sub.removeFromSuperview()
        }
        scnView = nil
        imageView = nil
        loadingIndicator = nil
    }

    private func showObject(at index: Int) {
        guard index >= 0, index < objects.count else { return }
        currentIndex = index
        let object = objects[index]

        clearContent()

        if let thumbnailData = object.thumbnailData,
           let image = NSImage(data: thumbnailData)
        {
            os_log("Showing thumbnail at index %d", log: logger, type: .error, index)
            let view = NSImageView(frame: contentView.bounds)
            view.autoresizingMask = [.width, .height]
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            contentView.addSubview(view)
            imageView = view
            return
        }

        if let modelData = object.modelData {
            // Check cache first
            if let cachedScene = sceneCache[index] {
                showScene(cachedScene, at: index)
                return
            }

            // Parse async
            showLoadingIndicator()
            parseQueue.async { [weak self] in
                let parser = ThreeMFMeshParser()
                let scene = parser.parse(data: modelData)
                DispatchQueue.main.async {
                    guard let self = self, self.currentIndex == index else { return }
                    self.clearContent()
                    if let scene = scene {
                        self.sceneCache[index] = scene
                        self.showScene(scene, at: index)
                    } else {
                        os_log("Failed to parse model at index %d", log: logger, type: .error, index)
                    }
                }
            }
            return
        }
    }

    private func showScene(_ scene: SCNScene, at index: Int) {
        os_log("Showing 3D model at index %d", log: logger, type: .error, index)
        let view = SCNView(frame: contentView.bounds)
        view.autoresizingMask = [.width, .height]
        view.scene = scene
        view.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .white
        view.antialiasingMode = .multisampling4X
        contentView.addSubview(view)
        scnView = view
    }
}

// MARK: - NSCollectionView DataSource & Delegate

extension PreviewViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return objects.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: ThumbnailCell.identifier,
            for: indexPath
        ) as! ThumbnailCell

        let object = objects[indexPath.item]
        if let data = object.thumbnailData, let image = NSImage(data: data) {
            item.setThumbnail(image)
        } else if object.modelData != nil {
            // Show a cube icon placeholder; actual 3D snapshot is too expensive for cell rendering
            let cubeImage = NSImage(systemSymbolName: "cube", accessibilityDescription: "3D model")
            item.setThumbnail(cubeImage)

            // Try to render snapshot async if cached
            let index = indexPath.item
            if let scene = sceneCache[index] {
                renderSnapshot(scene: scene, for: item)
            } else if let modelData = object.modelData {
                parseQueue.async { [weak self] in
                    let parser = ThreeMFMeshParser()
                    guard let scene = parser.parse(data: modelData) else { return }
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.sceneCache[index] = scene
                        // Update cell if still visible
                        if let visibleItem = self.collectionView.item(at: indexPath) as? ThumbnailCell {
                            self.renderSnapshot(scene: scene, for: visibleItem)
                        }
                    }
                }
            }
        }
        item.setSelected(indexPath.item == currentIndex)
        return item
    }

    private func renderSnapshot(scene: SCNScene, for item: ThumbnailCell) {
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
        let snapshot = renderer.snapshot(
            atTime: 0,
            with: CGSize(width: thumbSize * 2, height: thumbSize * 2),
            antialiasingMode: .multisampling4X
        )
        item.setThumbnail(snapshot)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard let indexPath = indexPaths.first else { return }
        let previousIndex = currentIndex
        showObject(at: indexPath.item)

        if let oldItem = collectionView.item(at: IndexPath(item: previousIndex, section: 0)) as? ThumbnailCell {
            oldItem.setSelected(false)
        }
        if let newItem = collectionView.item(at: indexPath) as? ThumbnailCell {
            newItem.setSelected(true)
        }
    }
}

// MARK: - Thumbnail Cell

class ThumbnailCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailCell")

    private var thumbImageView: NSImageView!
    private var selectionBorder: NSView!

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true

        selectionBorder = NSView(frame: container.bounds)
        selectionBorder.autoresizingMask = [.width, .height]
        selectionBorder.wantsLayer = true
        selectionBorder.layer?.cornerRadius = 6
        selectionBorder.layer?.borderWidth = 2
        selectionBorder.layer?.borderColor = NSColor.controlAccentColor.cgColor
        selectionBorder.isHidden = true
        container.addSubview(selectionBorder)

        thumbImageView = NSImageView(frame: NSRect(x: 2, y: 2, width: 60, height: 60))
        thumbImageView.autoresizingMask = [.width, .height]
        thumbImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbImageView.wantsLayer = true
        thumbImageView.layer?.cornerRadius = 4
        thumbImageView.layer?.masksToBounds = true
        thumbImageView.layer?.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
        container.addSubview(thumbImageView)

        self.view = container
    }

    func setThumbnail(_ image: NSImage?) {
        thumbImageView.image = image
    }

    func setSelected(_ selected: Bool) {
        selectionBorder.isHidden = !selected
    }
}
