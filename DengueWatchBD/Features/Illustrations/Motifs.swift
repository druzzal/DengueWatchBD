import SwiftUI

/// Shared geometry for the symptom illustrations.
///
/// Everything is drawn in a normalised 100×100 space and scaled to the frame,
/// so a motif is identical at 44 pt in a list row and at 160 pt on the result
/// screen. Drawing them rather than shipping bitmaps keeps the app small, keeps
/// both colour schemes correct, and avoids any question of image licensing.
extension CGRect {
    /// Map a point given in 0…100 space onto this rect.
    func n(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: minX + width * x / 100, y: minY + height * y / 100)
    }

    func s(_ value: CGFloat) -> CGFloat { min(width, height) * value / 100 }
}

/// Head-and-shoulders silhouette used by the motifs that point at a body part.
struct TorsoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Head
        path.addEllipse(in: CGRect(
            x: rect.n(38, 12).x, y: rect.n(38, 12).y,
            width: rect.s(24), height: rect.s(26)
        ))
        // Neck and shoulders
        path.move(to: rect.n(44, 38))
        path.addLine(to: rect.n(44, 46))
        path.addCurve(to: rect.n(22, 62),
                      control1: rect.n(38, 48), control2: rect.n(26, 52))
        path.addLine(to: rect.n(18, 92))
        path.addLine(to: rect.n(82, 92))
        path.addLine(to: rect.n(78, 62))
        path.addCurve(to: rect.n(56, 46),
                      control1: rect.n(74, 52), control2: rect.n(62, 48))
        path.addLine(to: rect.n(56, 38))
        path.closeSubpath()
        return path
    }
}

/// A profile head, for the motifs about headache and consciousness.
struct HeadProfileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: rect.n(62, 88))
        path.addLine(to: rect.n(62, 70))
        path.addCurve(to: rect.n(78, 46),
                      control1: rect.n(74, 68), control2: rect.n(78, 58))
        path.addCurve(to: rect.n(50, 14),
                      control1: rect.n(78, 28), control2: rect.n(66, 14))
        path.addCurve(to: rect.n(24, 44),
                      control1: rect.n(34, 14), control2: rect.n(24, 28))
        path.addCurve(to: rect.n(30, 62),
                      control1: rect.n(24, 54), control2: rect.n(27, 58))
        path.addLine(to: rect.n(26, 68))
        path.addCurve(to: rect.n(34, 72),
                      control1: rect.n(24, 71), control2: rect.n(29, 72))
        path.addLine(to: rect.n(34, 80))
        path.addCurve(to: rect.n(46, 88),
                      control1: rect.n(34, 86), control2: rect.n(40, 88))
        path.closeSubpath()
        return path
    }
}

/// Radiating pain lines, drawn around a focus point.
struct RadiatingLines: Shape {
    var origin: CGPoint          // in 0…100 space
    var count: Int = 6
    var innerRadius: CGFloat = 14
    var outerRadius: CGFloat = 24
    var arc: CGFloat = 360
    var startAngle: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = rect.n(origin.x, origin.y)
        for index in 0..<count {
            let fraction = count == 1 ? 0 : CGFloat(index) / CGFloat(count - 1)
            let degrees = startAngle + fraction * arc
            let radians = degrees * .pi / 180
            let inner = CGPoint(x: centre.x + cos(radians) * rect.s(innerRadius),
                                y: centre.y + sin(radians) * rect.s(innerRadius))
            let outer = CGPoint(x: centre.x + cos(radians) * rect.s(outerRadius),
                                y: centre.y + sin(radians) * rect.s(outerRadius))
            path.move(to: inner)
            path.addLine(to: outer)
        }
        return path
    }
}

/// A teardrop, used for blood and fluid motifs.
struct DropletShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: rect.n(50, 8))
        path.addCurve(to: rect.n(84, 58),
                      control1: rect.n(62, 26), control2: rect.n(84, 40))
        path.addArc(center: rect.n(50, 58), radius: rect.s(34),
                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addCurve(to: rect.n(50, 8),
                      control1: rect.n(16, 40), control2: rect.n(38, 26))
        path.closeSubpath()
        return path
    }
}

/// Wavy lines for nausea and fluid build-up.
struct WaveLines: Shape {
    var rows: Int = 3
    var top: CGFloat = 40
    var spacing: CGFloat = 12
    var amplitude: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for row in 0..<rows {
            let y = top + CGFloat(row) * spacing
            path.move(to: rect.n(26, y))
            path.addCurve(to: rect.n(50, y),
                          control1: rect.n(32, y - amplitude), control2: rect.n(44, y + amplitude))
            path.addCurve(to: rect.n(74, y),
                          control1: rect.n(56, y - amplitude), control2: rect.n(68, y + amplitude))
        }
        return path
    }
}

/// Thermometer body for the fever motif.
struct ThermometerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bulb = CGRect(x: rect.n(38, 66).x, y: rect.n(38, 66).y,
                          width: rect.s(24), height: rect.s(24))
        path.addEllipse(in: bulb)
        path.addRoundedRect(in: CGRect(x: rect.n(44, 14).x, y: rect.n(44, 14).y,
                                       width: rect.s(12), height: rect.s(60)),
                            cornerSize: CGSize(width: rect.s(6), height: rect.s(6)))
        return path
    }
}
