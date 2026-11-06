import CoreGraphics
import Foundation

/// Natural Earth land polygons (public domain), used by the dot-matrix and
/// line-art styles. Loaded once and shared.
final class LandData {
    /// Each ring is a closed list of (lon, lat) points in degrees.
    let rings: [[SIMD2<Double>]]
    /// Country border polylines (open), (lon, lat) in degrees.
    let borders: [[SIMD2<Double>]]

    /// Equirectangular land mask: `mask[y * width + x] > 0` means land.
    /// Row 0 is latitude +90°, column 0 is longitude −180°.
    let mask: [UInt8]
    let maskWidth: Int
    let maskHeight: Int

    static let shared: LandData = {
        var rings: [[SIMD2<Double>]] = []
        var borders: [[SIMD2<Double>]] = []
        do {
            let data = try Data(contentsOf: try ResourceLocator.url(for: "GeoData/ne_50m_land.geojson"))
            rings = try LandData.parseLines(data)
        } catch {
            Log.error("Land data unavailable: \(error)")
        }
        do {
            let data = try Data(contentsOf: try ResourceLocator.url(for: "GeoData/ne_50m_borders.geojson"))
            borders = try LandData.parseLines(data)
        } catch {
            Log.error("Border data unavailable: \(error)")
        }
        return LandData(rings: rings, borders: borders)
    }()

    init(rings: [[SIMD2<Double>]], borders: [[SIMD2<Double>]] = [], maskWidth: Int = 4096) {
        self.rings = rings
        self.borders = borders
        self.maskWidth = maskWidth
        self.maskHeight = maskWidth / 2
        self.mask = LandData.rasterise(rings, width: maskWidth, height: maskWidth / 2)
    }

    /// Whether a coordinate is on land, according to the raster mask.
    func isLand(_ c: GeoCoordinate) -> Bool {
        guard !mask.isEmpty else { return false }
        var x = Int(((c.longitude + 180) / 360) * Double(maskWidth))
        var y = Int(((90 - c.latitude) / 180) * Double(maskHeight))
        x = min(max(x, 0), maskWidth - 1)
        y = min(max(y, 0), maskHeight - 1)
        return mask[y * maskWidth + x] > 127
    }

    // MARK: - Parsing

    /// Extracts polygon outer rings and line strings from a GeoJSON FeatureCollection.
    static func parseLines(_ data: Data) throws -> [[SIMD2<Double>]] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var rings: [[SIMD2<Double>]] = []

        func ring(_ any: Any) -> [SIMD2<Double>] {
            guard let pts = any as? [[Double]] else { return [] }
            return pts.compactMap { $0.count >= 2 ? SIMD2($0[0], $0[1]) : nil }
        }

        for feature in features {
            guard let geom = feature["geometry"] as? [String: Any],
                  let type = geom["type"] as? String,
                  let coords = geom["coordinates"] else { continue }
            switch type {
            case "Polygon":
                // Only the outer ring matters at this scale (holes are lakes).
                if let polys = coords as? [Any], let outer = polys.first { rings.append(ring(outer)) }
            case "MultiPolygon":
                for poly in (coords as? [Any]) ?? [] {
                    if let p = poly as? [Any], let outer = p.first { rings.append(ring(outer)) }
                }
            case "LineString":
                rings.append(ring(coords))
            case "MultiLineString":
                for line in (coords as? [Any]) ?? [] { rings.append(ring(line)) }
            default:
                continue
            }
        }
        return rings.filter { $0.count >= 2 }
    }

    // MARK: - Rasterising

    private static func rasterise(_ rings: [[SIMD2<Double>]], width: Int, height: Int) -> [UInt8] {
        guard !rings.isEmpty else { return [] }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let space = CGColorSpaceCreateDeviceGray()
        pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width, space: space,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            // Flip so row 0 in memory is +90° latitude.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setFillColor(gray: 1, alpha: 1)
            let sx = Double(width) / 360, sy = Double(height) / 180
            let path = CGMutablePath()
            for ring in rings {
                path.move(to: CGPoint(x: (ring[0].x + 180) * sx, y: (90 - ring[0].y) * sy))
                for p in ring.dropFirst() {
                    path.addLine(to: CGPoint(x: (p.x + 180) * sx, y: (90 - p.y) * sy))
                }
                path.closeSubpath()
            }
            ctx.addPath(path)
            ctx.fillPath(using: .winding)
        }
        return pixels
    }
}
