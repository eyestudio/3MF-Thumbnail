import Foundation
import SceneKit

/// Parses 3MF model XML and builds a SceneKit scene.
class ThreeMFMeshParser: NSObject, XMLParserDelegate {
    private var vertices: [SCNVector3] = []
    private var triangleIndices: [(Int, Int, Int)] = []
    private var currentElement: String = ""
    private var inMesh = false

    /// Parses 3MF model XML data and returns an SCNScene.
    func parse(data: Data) -> SCNScene? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse(), !vertices.isEmpty, !triangleIndices.isEmpty else {
            return nil
        }
        return buildScene()
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "mesh":
            inMesh = true
        case "vertex" where inMesh:
            if let xStr = attributeDict["x"], let x = Double(xStr),
               let yStr = attributeDict["y"], let y = Double(yStr),
               let zStr = attributeDict["z"], let z = Double(zStr)
            {
                vertices.append(SCNVector3(x, y, z))
            }
        case "triangle" where inMesh:
            if let v1Str = attributeDict["v1"], let v1 = Int(v1Str),
               let v2Str = attributeDict["v2"], let v2 = Int(v2Str),
               let v3Str = attributeDict["v3"], let v3 = Int(v3Str)
            {
                triangleIndices.append((v1, v2, v3))
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        if localName == "mesh" {
            inMesh = false
        }
    }

    // MARK: - SceneKit Scene Construction

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        // Build geometry
        let vertexSource = SCNGeometrySource(vertices: vertices)

        var indices: [Int32] = []
        for (v1, v2, v3) in triangleIndices {
            indices.append(Int32(v1))
            indices.append(Int32(v2))
            indices.append(Int32(v3))
        }

        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: triangleIndices.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])

        // Compute normals for better lighting
        // SceneKit can auto-generate normals if we don't provide them

        // Material
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(red: 0.8, green: 0.8, blue: 0.85, alpha: 1.0)
        material.specular.contents = NSColor.white
        material.shininess = 0.3
        material.lightingModel = .physicallyBased
        material.metalness.contents = 0.1
        material.roughness.contents = 0.6
        geometry.materials = [material]

        let modelNode = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(modelNode)

        // Center the model
        let (minBound, maxBound) = modelNode.boundingBox
        let center = SCNVector3(
            (minBound.x + maxBound.x) / 2,
            (minBound.y + maxBound.y) / 2,
            (minBound.z + maxBound.z) / 2
        )
        modelNode.position = SCNVector3(-center.x, -center.y, -center.z)

        // Container node for the centered model
        let containerNode = SCNNode()
        containerNode.addChildNode(modelNode)
        scene.rootNode.addChildNode(containerNode)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true

        let size = SCNVector3(
            maxBound.x - minBound.x,
            maxBound.y - minBound.y,
            maxBound.z - minBound.z
        )
        let maxDimension = max(size.x, max(size.y, size.z))
        let cameraDistance = Float(maxDimension) * 2.0
        cameraNode.position = SCNVector3(cameraDistance * 0.7, cameraDistance * 0.5, cameraDistance)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        // Lighting
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 800
        keyLight.light?.color = NSColor.white
        keyLight.light?.castsShadow = true
        keyLight.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 400
        fillLight.light?.color = NSColor(white: 0.9, alpha: 1.0)
        fillLight.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fillLight)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 300
        ambientLight.light?.color = NSColor(white: 0.8, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        scene.background.contents = NSColor.white

        return scene
    }
}
