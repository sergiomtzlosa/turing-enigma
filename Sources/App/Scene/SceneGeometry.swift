import AppKit
import SceneKit
import simd

enum SceneAxis {
    case x, y, z
}

enum Geo {
    static func box(
        _ width: CGFloat,
        _ height: CGFloat,
        _ length: CGFloat,
        chamfer: CGFloat = 0,
        material: SCNMaterial,
        name: String? = nil
    ) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: chamfer)
        geometry.materials = [material]
        geometry.chamferSegmentCount = chamfer > 0 ? 4 : 1
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.castsShadow = true
        return node
    }

    static func cylinder(
        radius: CGFloat,
        height: CGFloat,
        material: SCNMaterial,
        axis: SceneAxis = .y,
        radialSegments: Int = 48,
        name: String? = nil
    ) -> SCNNode {
        let geometry = SCNCylinder(radius: radius, height: height)
        geometry.radialSegmentCount = radialSegments
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = name
        switch axis {
        case .y: break
        case .x: node.eulerAngles.z = .pi / 2
        case .z: node.eulerAngles.x = .pi / 2
        }
        node.castsShadow = true
        return node
    }

    static func torus(
        ringRadius: CGFloat,
        pipeRadius: CGFloat,
        material: SCNMaterial,
        radialSegments: Int = 48,
        pipeSegments: Int = 16,
        name: String? = nil
    ) -> SCNNode {
        let geometry = SCNTorus(ringRadius: ringRadius, pipeRadius: pipeRadius)
        geometry.ringSegmentCount = radialSegments
        geometry.pipeSegmentCount = pipeSegments
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.castsShadow = true
        return node
    }

    static func plane(width: CGFloat, height: CGFloat, material: SCNMaterial, name: String? = nil) -> SCNNode {
        let geometry = SCNPlane(width: width, height: height)
        geometry.materials = [material]
        geometry.cornerRadius = 0
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.castsShadow = false
        return node
    }

    static func sphere(radius: CGFloat, material: SCNMaterial, name: String? = nil) -> SCNNode {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 32
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.castsShadow = true
        return node
    }

    static func screw(radius: CGFloat = 0.004, length: CGFloat = 0.003, material: SCNMaterial? = nil) -> SCNNode {
        let library = MaterialLibrary.shared
        let body = cylinder(radius: radius, height: length, material: material ?? library.darkSteel, axis: .y, radialSegments: 20)
        let slot = box(radius * 1.35, length * 0.22, radius * 0.28, material: library.blackSlotMaterial(), name: nil)
        slot.position.y = length / 2 + 0.0002
        body.addChildNode(slot)
        return body
    }

    static func rivet(radius: CGFloat = 0.005) -> SCNNode {
        let library = MaterialLibrary.shared
        let head = sphere(radius: radius, material: library.brass)
        head.scale.y = 0.45
        return head
    }

    static func decalNode(image: NSImage, width: CGFloat, height: CGFloat, key: String, doubleSided: Bool = true) -> SCNNode {
        let material = MaterialLibrary.shared.decal(image, key: key)
        material.isDoubleSided = doubleSided
        let node = plane(width: width, height: height, material: material)
        node.castsShadow = false
        node.renderingOrder = 10
        return node
    }

    static func letterNode(_ letter: Character, size: CGFloat, color: NSColor = NSColor(calibratedWhite: 0.055, alpha: 1)) -> SCNNode {
        let material = MaterialLibrary.shared.letter(letter, color: color)
        let node = plane(width: size, height: size, material: material)
        node.castsShadow = false
        node.renderingOrder = 12
        return node
    }

    static func textNode(
        text: String,
        width: CGFloat,
        height: CGFloat,
        font: NSFont,
        color: NSColor,
        background: NSColor? = nil,
        alignment: NSTextAlignment = .center
    ) -> SCNNode {
        let size = CGSize(width: max(256, width * 1400), height: max(64, height * 1400))
        let image = TextureFactory.textDecal(
            text,
            size: size,
            font: font,
            color: color,
            background: background,
            alignment: alignment,
            padding: 8
        )
        let key = "text-\(text)-\(width)-\(height)-\(font.fontName)-\(color.description)-\(alignment.rawValue)"
        return decalNode(image: image, width: width, height: height, key: key)
    }

    static func nameplateNode(title: String, subtitle: String, width: CGFloat) -> SCNNode {
        let material = MaterialLibrary.shared.nameplate(title, subtitle: subtitle)
        let node = plane(width: width, height: width * 0.25, material: material)
        node.castsShadow = false
        node.renderingOrder = 9
        return node
    }

    static func cable(
        points: [SCNVector3],
        radius: CGFloat,
        material: SCNMaterial,
        radialSegments: Int = 8,
        samplesPerSegment: Int = 10
    ) -> SCNNode {
        let sampled = catmullRom(points: points, samplesPerSegment: samplesPerSegment)
        guard sampled.count >= 2 else { return SCNNode() }
        let simdPoints = sampled.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity(simdPoints.count * radialSegments)
        normals.reserveCapacity(simdPoints.count * radialSegments)
        texcoords.reserveCapacity(simdPoints.count * radialSegments)

        var previousNormal = SIMD3<Float>(0, 1, 0)
        for index in simdPoints.indices {
            let current = simdPoints[index]
            let tangent: SIMD3<Float>
            if index == 0 {
                tangent = simd_normalize(simdPoints[1] - current)
            } else if index == simdPoints.count - 1 {
                tangent = simd_normalize(current - simdPoints[index - 1])
            } else {
                tangent = simd_normalize(simdPoints[index + 1] - simdPoints[index - 1])
            }
            var normal = previousNormal - tangent * simd_dot(previousNormal, tangent)
            if simd_length(normal) < 0.001 {
                normal = simd_cross(tangent, SIMD3<Float>(0, 0, 1))
            }
            normal = simd_normalize(normal)
            let binormal = simd_normalize(simd_cross(tangent, normal))
            previousNormal = normal
            for segment in 0..<radialSegments {
                let angle = Float(segment) / Float(radialSegments) * 2 * .pi
                let offset = normal * cos(angle) * Float(radius) + binormal * sin(angle) * Float(radius)
                let point = current + offset
                vertices.append(SCNVector3(x: CGFloat(point.x), y: CGFloat(point.y), z: CGFloat(point.z)))
                normals.append(SCNVector3(x: CGFloat(normal.x), y: CGFloat(normal.y), z: CGFloat(normal.z)))
                texcoords.append(CGPoint(x: CGFloat(index) / CGFloat(simdPoints.count - 1), y: CGFloat(segment) / CGFloat(radialSegments)))
            }
        }

        for ring in 0..<(simdPoints.count - 1) {
            for segment in 0..<radialSegments {
                let nextSegment = (segment + 1) % radialSegments
                let a = UInt32(ring * radialSegments + segment)
                let b = UInt32(ring * radialSegments + nextSegment)
                let c = UInt32((ring + 1) * radialSegments + nextSegment)
                let d = UInt32((ring + 1) * radialSegments + segment)
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let texSource = SCNGeometrySource(textureCoordinates: texcoords)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource, normalSource, texSource], elements: [element])
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.castsShadow = true
        return node
    }

    private static func catmullRom(points: [SCNVector3], samplesPerSegment: Int) -> [SCNVector3] {
        guard points.count >= 2 else { return points }
        let p = [points[0]] + points + [points[points.count - 1]]
        var result: [SCNVector3] = []
        let samples = max(2, samplesPerSegment)
        for i in 0..<(p.count - 3) {
            let p0 = p[i], p1 = p[i + 1], p2 = p[i + 2], p3 = p[i + 3]
            for step in 0..<samples {
                let t = CGFloat(step) / CGFloat(samples)
                let t2 = t * t
                let t3 = t2 * t
                let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                let z = 0.5 * ((2 * p1.z) + (-p0.z + p2.z) * t + (2 * p0.z - 5 * p1.z + 4 * p2.z - p3.z) * t2 + (-p0.z + 3 * p1.z - 3 * p2.z + p3.z) * t3)
                result.append(SCNVector3(x: x, y: y, z: z))
            }
        }
        result.append(points[points.count - 1])
        return result
    }
}

private extension MaterialLibrary {
    func blackSlotMaterial() -> SCNMaterial {
        if let existing = coloredMaterials["slot-black"] { return existing }
        let material = makePBR(diffuse: NSColor(calibratedWhite: 0.015, alpha: 1), roughness: 0.8, metalness: 0.1)
        coloredMaterials["slot-black"] = material
        return material
    }
}
