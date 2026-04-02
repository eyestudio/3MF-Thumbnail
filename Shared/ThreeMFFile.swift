import Foundation
import ZIPFoundation

/// Represents a single 3D object found inside a 3MF archive.
struct ThreeMFObject {
    let name: String
    let thumbnailData: Data?
    let modelData: Data?
}

/// Represents a parsed 3MF file.
struct ThreeMFFile {
    let archiveURL: URL

    init(url: URL) {
        self.archiveURL = url
    }

    // MARK: - Single extraction (for Thumbnail Extension)

    /// Extracts the first available thumbnail image data.
    func extractThumbnailData() throws -> Data? {
        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            throw ThreeMFError.cannotOpenArchive
        }
        return try extractThumbnailFromArchive(archive)
    }

    /// Extracts the primary 3D model XML data.
    func extractModelData() throws -> Data? {
        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            throw ThreeMFError.cannotOpenArchive
        }
        return try extractFirstModelFromArchive(archive)
    }

    // MARK: - Multi-object extraction (for Preview Extension)

    /// Extracts all objects (thumbnails + model data) from the 3MF archive.
    func extractAllObjects() throws -> [ThreeMFObject] {
        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            throw ThreeMFError.cannotOpenArchive
        }

        var objects: [ThreeMFObject] = []

        // Collect image entries with size info
        struct ImageEntry {
            let path: String
            let size: Int
        }

        var imageEntries: [ImageEntry] = []
        var modelPaths: [String] = []

        for entry in archive {
            let path = entry.path
            let lower = path.lowercased()

            if lower.hasSuffix(".model") {
                modelPaths.append(path)
            } else if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") {
                imageEntries.append(ImageEntry(path: path, size: Int(entry.uncompressedSize)))
            }
        }

        modelPaths.sort()

        // Filter and deduplicate thumbnails
        let filteredThumbnails = Self.filterThumbnails(imageEntries.map { ($0.path, $0.size) })

        // Add thumbnails first (quick preview)
        for (index, entry) in filteredThumbnails.enumerated() {
            let name = filteredThumbnails.count == 1
                ? "Thumbnail"
                : "Thumbnail \(index + 1)"
            let data = try extractEntry(archive: archive, path: entry.path)
            objects.append(ThreeMFObject(name: name, thumbnailData: data, modelData: nil))
        }

        // Then add 3D models
        // Skip small reference/index files (< 10KB, typically just XML references)
        let meshModelPaths = modelPaths.filter { path in
            guard let entry = archive[path] else { return false }
            return entry.uncompressedSize >= 10000
        }
        for (index, path) in meshModelPaths.enumerated() {
            let name = meshModelPaths.count == 1
                ? "3D Model"
                : "3D Model \(index + 1)"
            let data = try extractEntry(archive: archive, path: path)
            objects.append(ThreeMFObject(name: name, thumbnailData: nil, modelData: data))
        }

        // If no structured objects found, try relationship-based thumbnail
        if objects.isEmpty {
            if let relsEntry = archive["_rels/.rels"] {
                var relsData = Data()
                _ = try archive.extract(relsEntry) { chunk in
                    relsData.append(chunk)
                }
                if let thumbnailPath = parseThumbnailRelationship(from: relsData),
                   let entry = archive[thumbnailPath]
                {
                    var data = Data()
                    _ = try archive.extract(entry) { chunk in
                        data.append(chunk)
                    }
                    objects.append(ThreeMFObject(
                        name: "Thumbnail",
                        thumbnailData: data,
                        modelData: nil
                    ))
                }
            }
        }

        return objects
    }

    /// Filters thumbnails into ordered groups: thumbnail_middle → Model Pictures → plate_*.png.
    static func filterThumbnails(_ entries: [( path: String, size: Int )]) -> [(path: String, size: Int)] {
        var thumbnailMiddle: (path: String, size: Int)?
        var modelPictures: [(path: String, size: Int)] = []
        var plateThumbnails: [(path: String, size: Int)] = []

        for entry in entries {
            let lower = entry.path.lowercased()
            let filename = (entry.path as NSString).lastPathComponent.lowercased()

            // thumbnail_middle.png — main preview thumbnail
            if filename == "thumbnail_middle.png" {
                thumbnailMiddle = entry
                continue
            }

            // Model Pictures — user-added reference images
            if lower.contains("model pictures/") {
                modelPictures.append(entry)
                continue
            }

            // Skip: *_small.png, pick_*.png, top_*.png, plate_no_light_*.png, other auxiliary
            if filename.contains("_small.") || filename.hasPrefix("pick_")
                || filename.hasPrefix("top_") || filename.hasPrefix("plate_no_light_") {
                continue
            }

            if filename.hasPrefix("plate_") {
                plateThumbnails.append(entry)
            }
        }

        var result: [(path: String, size: Int)] = []

        // 1. thumbnail_middle.png (first position)
        if let middle = thumbnailMiddle {
            result.append(middle)
        }

        // 2. Model Pictures (sorted by path)
        result.append(contentsOf: modelPictures.sorted { $0.path < $1.path })

        // 3. Plate thumbnails (one per plate, sorted by path)
        result.append(contentsOf: plateThumbnails.sorted { $0.path < $1.path })

        return result
    }

    // MARK: - Private

    private func extractThumbnailFromArchive(_ archive: Archive) throws -> Data? {
        // Use the same filtering logic as preview — pick the first image in priority order
        var imageEntries: [(path: String, size: Int)] = []
        for entry in archive {
            let lower = entry.path.lowercased()
            if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") {
                imageEntries.append((path: entry.path, size: Int(entry.uncompressedSize)))
            }
        }

        let filtered = Self.filterThumbnails(imageEntries)
        if let first = filtered.first {
            return try extractEntry(archive: archive, path: first.path)
        }

        // Fallback: parse _rels/.rels
        if let relsEntry = archive["_rels/.rels"] {
            var relsData = Data()
            _ = try archive.extract(relsEntry) { chunk in
                relsData.append(chunk)
            }
            if let thumbnailPath = parseThumbnailRelationship(from: relsData) {
                return try? extractEntry(archive: archive, path: thumbnailPath)
            }
        }

        return nil
    }

    private func extractFirstModelFromArchive(_ archive: Archive) throws -> Data? {
        let modelPaths = [
            "3D/3dmodel.model",
            "3d/3dmodel.model",
        ]

        for path in modelPaths {
            if let data = try? extractEntry(archive: archive, path: path) {
                return data
            }
        }

        // Fallback: find any .model file
        for entry in archive {
            if entry.path.lowercased().hasSuffix(".model") {
                return try extractEntry(archive: archive, path: entry.path)
            }
        }

        return nil
    }

    private func extractEntry(archive: Archive, path: String) throws -> Data? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    private func parseThumbnailRelationship(from relsData: Data) -> String? {
        let parser = RelsXMLParser(data: relsData)
        return parser.parseThumbnailTarget()
    }
}

enum ThreeMFError: Error, LocalizedError {
    case cannotOpenArchive
    case noThumbnailFound
    case noModelFound
    case invalidModelData

    var errorDescription: String? {
        switch self {
        case .cannotOpenArchive: return "Cannot open 3MF archive"
        case .noThumbnailFound: return "No thumbnail found in 3MF file"
        case .noModelFound: return "No 3D model found in 3MF file"
        case .invalidModelData: return "Invalid 3D model data"
        }
    }
}

// MARK: - OPC Relationships Parser

private class RelsXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var thumbnailTarget: String?

    private static let thumbnailRelType =
        "http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"

    init(data: Data) {
        self.data = data
    }

    func parseThumbnailTarget() -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return thumbnailTarget
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "Relationship",
           let type = attributeDict["Type"],
           type == Self.thumbnailRelType,
           let target = attributeDict["Target"]
        {
            thumbnailTarget = target.hasPrefix("/") ? String(target.dropFirst()) : target
        }
    }
}
