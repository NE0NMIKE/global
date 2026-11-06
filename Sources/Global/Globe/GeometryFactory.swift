import SceneKit
import simd

/// Builds custom SceneKit geometry in globe space (see `GeoMath` for axes).
enum GeometryFactory {

    // MARK: - Sphere

    /// UV sphere whose texture mapping matches `GeoMath.unitVector`, so an
    /// equirectangular image (−180° at u = 0, +90° at v = 0) lines up exactly.
    static func sphere(radius: Float = 1, latSegments: Int = 96, lonSegments: Int = 192) -> SCNGeometry {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        positions.reserveCapacity((latSegments + 1) * (lonSegments + 1))

        for i in 0...latSegments {
            let v = Double(i) / Double(latSegments)
            let lat = 90 - v * 180
            for j in 0...lonSegments {
                let u = Double(j) / Double(lonSegments)
                let lon = -180 + u * 360
                let n = GeoMath.unitVector(GeoCoordinate(latitude: lat, longitude: lon))
                normals.append(SCNVector3(n.x, n.y, n.z))
                positions.append(SCNVector3(n.x * Double(radius), n.y * Double(radius), n.z * Double(radius)))
                uvs.append(CGPoint(x: u, y: v))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(latSegments * lonSegments * 6)
        let row = UInt32(lonSegments + 1)
        for i in 0..<UInt32(latSegments) {
            for j in 0..<UInt32(lonSegments) {
                let a = i * row + j, b = a + row
                // Counter-clockwise when viewed from outside.
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }

        return SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                     SCNGeometrySource(normals: normals),
                                     SCNGeometrySource(textureCoordinates: uvs)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    // MARK: - Ribbons (lines with real width)

    /// Turns lon/lat polylines into flat ribbons lying on a sphere of
    /// `radius`. SceneKit lines are always one device pixel wide, which is too
    /// thin on Retina, so linework is built as geometry instead.
    ///
    /// - Parameter maxStepDegrees: long segments are subdivided so they follow
    ///   the curvature of the sphere.
    static func ribbons(_ lines: [[SIMD2<Double>]], radius: Double, width: Double,
                        maxStepDegrees: Double = 1.5) -> SCNGeometry? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for line in lines {
            guard line.count >= 2 else { continue }
            var pts: [SIMD3<Double>] = []
            pts.reserveCapacity(line.count)
            var prev: SIMD3<Double>?
            for p in line {
                let v = GeoMath.unitVector(GeoCoordinate(latitude: p.y, longitude: p.x))
                if let a = prev {
                    let ang = GeoMath.deg(acos(max(-1, min(1, simd_dot(a, v)))))
                    if ang > maxStepDegrees {
                        let steps = Int(ceil(ang / maxStepDegrees))
                        for s in 1..<steps { pts.append(GeoMath.slerp(a, v, Double(s) / Double(steps))) }
                    }
                }
                pts.append(v)
                prev = v
            }
            appendRibbon(pts, radius: radius, width: width, positions: &positions, normals: &normals, indices: &indices)
        }
        return makeGeometry(positions: positions, normals: normals, uvs: nil, indices: indices)
    }

    /// Appends one ribbon through `pts` (unit vectors) as independent quads.
    private static func appendRibbon(_ pts: [SIMD3<Double>], radius: Double, width: Double,
                                     positions: inout [SIMD3<Float>], normals: inout [SIMD3<Float>],
                                     indices: inout [UInt32]) {
        guard pts.count >= 2 else { return }
        let hw = width / 2
        for k in 0..<(pts.count - 1) {
            let a = pts[k], b = pts[k + 1]
            let d = b - a
            if simd_length_squared(d) < 1e-14 { continue }
            let mid = simd_normalize(a + b)
            let side = simd_normalize(simd_cross(mid, d)) * hw
            // Extend each quad slightly along the segment so joints don't gap.
            let ext = simd_normalize(d) * hw * 0.9
            let a0 = (a - ext) * radius, b0 = (b + ext) * radius
            let base = UInt32(positions.count)
            for p in [a0 - side, a0 + side, b0 - side, b0 + side] {
                positions.append(SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)))
                let n = simd_normalize(p)
                normals.append(SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z)))
            }
            indices += [base, base + 2, base + 1, base + 1, base + 2, base + 3]
        }
    }

    /// Latitude/longitude grid every `step` degrees.
    static func graticuleLines(step: Double = 15) -> [[SIMD2<Double>]] {
        var lines: [[SIMD2<Double>]] = []
        var lon = -180.0
        while lon < 180 {
            lines.append(stride(from: -80.0, through: 80.0, by: 2).map { SIMD2(lon, $0) })
            lon += step
        }
        var lat = -75.0
        while lat <= 75 {
            lines.append(stride(from: -180.0, through: 180.0, by: 2).map { SIMD2($0, lat) })
            lat += step
        }
        return lines
    }

    // MARK: - Dots

    /// Dot-matrix land: rows of latitude with dot count proportional to the
    /// circumference, keeping only dots that fall on land.
    static func landDots(_ land: LandData, rows: Int = 180, dotRadius: Double = 0.0052,
                         radius: Double = 1.002) -> SCNGeometry? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        let spacing = 180.0 / Double(rows)
        for r in 0..<rows {
            let lat = -90 + spacing * (Double(r) + 0.5)
            let count = Int((cos(GeoMath.rad(lat)) * 360 / spacing).rounded())
            guard count > 0 else { continue }
            // Offset alternate rows by half a step for a hexagonal feel.
            let offset = r % 2 == 0 ? 0.0 : 0.5
            for k in 0..<count {
                let lon = -180 + (Double(k) + offset) * 360 / Double(count)
                let c = GeoCoordinate(latitude: lat, longitude: lon)
                guard land.isLand(c) else { continue }

                let n = GeoMath.unitVector(c)
                let φ = GeoMath.rad(lat), λ = GeoMath.rad(lon)
                let east = SIMD3(cos(λ), 0, -sin(λ)) * dotRadius
                let north = SIMD3(-sin(φ) * sin(λ), cos(φ), -sin(φ) * cos(λ)) * dotRadius
                let centre = n * radius
                let base = UInt32(positions.count)
                let corners: [(SIMD3<Double>, SIMD2<Float>)] = [
                    (centre - east - north, SIMD2(0, 1)),
                    (centre + east - north, SIMD2(1, 1)),
                    (centre - east + north, SIMD2(0, 0)),
                    (centre + east + north, SIMD2(1, 0)),
                ]
                for (p, uv) in corners {
                    positions.append(SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)))
                    normals.append(SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z)))
                    uvs.append(uv)
                }
                indices += [base, base + 1, base + 2, base + 2, base + 1, base + 3]
            }
        }
        return makeGeometry(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    // MARK: - Arc

    /// Points along the great circle from `a` to `b`, raised by `lift·sin(πt)`.
    static func arcPoints(from a: GeoCoordinate, to b: GeoCoordinate, lift: Double,
                          base: Double = 1.004, segments: Int = 160) -> [SIMD3<Double>] {
        let va = GeoMath.unitVector(a), vb = GeoMath.unitVector(b)
        return (0...segments).map { i in
            let t = Double(i) / Double(segments)
            return GeoMath.slerp(va, vb, t) * (base + lift * sin(.pi * t))
        }
    }

    /// Round tube along a polyline with u running 0 → 1 along its length.
    static func tube(_ pts: [SIMD3<Double>], radius: Double, sides: Int = 8) -> SCNGeometry? {
        guard pts.count >= 2 else { return nil }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for (i, p) in pts.enumerated() {
            let prev = pts[max(0, i - 1)], next = pts[min(pts.count - 1, i + 1)]
            let t = simd_normalize(next - prev)
            let up = simd_normalize(p)
            let side = simd_normalize(simd_cross(t, up))
            let upPerp = simd_normalize(simd_cross(side, t))
            for s in 0...sides {
                let θ = Double(s) / Double(sides) * 2 * .pi
                let n = side * cos(θ) + upPerp * sin(θ)
                let q = p + n * radius
                positions.append(SIMD3<Float>(Float(q.x), Float(q.y), Float(q.z)))
                normals.append(SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z)))
                uvs.append(SIMD2(Float(i) / Float(pts.count - 1), Float(s) / Float(sides)))
            }
        }
        let ring = UInt32(sides + 1)
        for i in 0..<UInt32(pts.count - 1) {
            for s in 0..<UInt32(sides) {
                let a = i * ring + s, b = a + ring
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        return makeGeometry(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    /// Dashed ribbon along an arc: `dash` and `gap` are fractions of the
    /// whole arc length.
    static func dashedRibbon(_ pts: [SIMD3<Double>], width: Double, dash: Double = 0.018,
                             gap: Double = 0.012) -> SCNGeometry? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let period = dash + gap
        var current: [SIMD3<Double>] = []
        for (i, p) in pts.enumerated() {
            let t = Double(i) / Double(pts.count - 1)
            let on = t.truncatingRemainder(dividingBy: period) < dash
            if on {
                current.append(p)
            } else if !current.isEmpty {
                current.append(p)
                appendRibbonRaw(current, width: width, positions: &positions, normals: &normals, indices: &indices)
                current = []
            }
        }
        if current.count >= 2 {
            appendRibbonRaw(current, width: width, positions: &positions, normals: &normals, indices: &indices)
        }
        return makeGeometry(positions: positions, normals: normals, uvs: nil, indices: indices)
    }

    /// Like `appendRibbon` but for points already at their final radius.
    private static func appendRibbonRaw(_ pts: [SIMD3<Double>], width: Double,
                                        positions: inout [SIMD3<Float>], normals: inout [SIMD3<Float>],
                                        indices: inout [UInt32]) {
        let r = simd_length(pts[0])
        appendRibbon(pts.map { simd_normalize($0) }, radius: r, width: width,
                     positions: &positions, normals: &normals, indices: &indices)
    }

    // MARK: - Flat ring (limb outline, in the camera plane)

    static func flatRing(radius: Double, width: Double, segments: Int = 256) -> SCNGeometry? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for i in 0...segments {
            let θ = Double(i) / Double(segments) * 2 * .pi
            for r in [radius, radius + width] {
                positions.append(SIMD3<Float>(Float(cos(θ) * r), Float(sin(θ) * r), 0))
                normals.append(SIMD3<Float>(0, 0, 1))
            }
        }
        for i in 0..<UInt32(segments) {
            let a = i * 2
            indices += [a, a + 2, a + 1, a + 1, a + 2, a + 3]
        }
        return makeGeometry(positions: positions, normals: normals, uvs: nil, indices: indices)
    }

    // MARK: - Assembly

    private static func makeGeometry(positions: [SIMD3<Float>], normals: [SIMD3<Float>],
                                     uvs: [SIMD2<Float>]?, indices: [UInt32]) -> SCNGeometry? {
        guard !positions.isEmpty, !indices.isEmpty else { return nil }
        var sources = [
            source(positions, semantic: .vertex),
            source(normals, semantic: .normal),
        ]
        if let uvs { sources.append(source(uvs, semantic: .texcoord)) }
        let element = SCNGeometryElement(data: Data(bytes: indices, count: indices.count * 4),
                                         primitiveType: .triangles,
                                         primitiveCount: indices.count / 3,
                                         bytesPerIndex: 4)
        return SCNGeometry(sources: sources, elements: [element])
    }

    private static func source(_ v: [SIMD3<Float>], semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        // SIMD3<Float> has a stride of 16 bytes; describe that layout directly.
        let data = v.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: v.count,
                                 usesFloatComponents: true, componentsPerVector: 3,
                                 bytesPerComponent: 4, dataOffset: 0,
                                 dataStride: MemoryLayout<SIMD3<Float>>.stride)
    }

    private static func source(_ v: [SIMD2<Float>], semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        let data = v.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: v.count,
                                 usesFloatComponents: true, componentsPerVector: 2,
                                 bytesPerComponent: 4, dataOffset: 0,
                                 dataStride: MemoryLayout<SIMD2<Float>>.stride)
    }
}
