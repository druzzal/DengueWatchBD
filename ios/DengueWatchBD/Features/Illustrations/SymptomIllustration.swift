import SwiftUI

/// One illustration per symptom, composed from the shared motifs.
///
/// The severity tint carries the same meaning as everywhere else in the app:
/// core symptoms in the series blue, warning signs and emergency signs on the
/// ordinal risk ramp. Colour is never the only cue — each drawing differs in
/// shape, and every use sits beside its label.
struct SymptomIllustration: View {
    let symptomID: String
    var group: Symptom.Group = .core
    var size: CGFloat = 56

    private var accent: Color {
        switch group {
        case .core: Palette.cases
        case .warning: Palette.riskTint(.high)
        case .severe: Palette.riskTint(.severe)
        }
    }

    private var wash: Color { accent.opacity(0.12) }

    var body: some View {
        ZStack {
            Circle().fill(wash)
            motif
                .padding(size * 0.16)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var motif: some View {
        switch symptomID {
        case "fever": fever
        case "headache": headache
        case "aches": aches
        case "rash": rash
        case "nausea": nausea
        case "abdominal": abdominal
        case "vomiting": vomiting
        case "bleeding": bleeding
        case "fatigue": fatigue
        case "fluid": fluid
        case "noUrine": noUrine
        case "faint": faint
        case "confusion": confusion
        case "heavyBleed": heavyBleed
        default: fallback
        }
    }

    // MARK: - Core symptoms

    private var fever: some View {
        ZStack {
            ThermometerShape().fill(accent.opacity(0.25))
            ThermometerShape().stroke(accent, lineWidth: size * 0.045)
            GeometryReader { geometry in
                let rect = CGRect(origin: .zero, size: geometry.size)
                Path { path in
                    path.addRoundedRect(in: CGRect(x: rect.n(46, 40).x, y: rect.n(46, 40).y,
                                                   width: rect.s(8), height: rect.s(34)),
                                        cornerSize: CGSize(width: rect.s(4), height: rect.s(4)))
                    path.addEllipse(in: CGRect(x: rect.n(41, 69).x, y: rect.n(41, 69).y,
                                               width: rect.s(18), height: rect.s(18)))
                }
                .fill(accent)
                // Heat rising off the bulb
                RadiatingLines(origin: CGPoint(x: 76, y: 30), count: 3,
                               innerRadius: 4, outerRadius: 15, arc: 60, startAngle: -75)
                    .stroke(accent.opacity(0.75), style: StrokeStyle(lineWidth: rect.s(4), lineCap: .round))
            }
        }
    }

    private var headache: some View {
        ZStack {
            HeadProfileShape().fill(accent.opacity(0.22))
            HeadProfileShape().stroke(accent, lineWidth: size * 0.045)
            GeometryReader { geometry in
                let rect = CGRect(origin: .zero, size: geometry.size)
                // Pain focused behind the eye
                Circle()
                    .fill(accent)
                    .frame(width: rect.s(11), height: rect.s(11))
                    .position(rect.n(40, 44))
                RadiatingLines(origin: CGPoint(x: 40, y: 44), count: 5,
                               innerRadius: 11, outerRadius: 21, arc: 200, startAngle: 100)
                    .stroke(accent, style: StrokeStyle(lineWidth: rect.s(3.5), lineCap: .round))
            }
        }
    }

    private var aches: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                // A long bone with a joint in the middle
                Path { path in
                    path.move(to: rect.n(26, 74))
                    path.addLine(to: rect.n(74, 26))
                }
                .stroke(accent, style: StrokeStyle(lineWidth: rect.s(11), lineCap: .round))

                Path { path in
                    for point in [(20, 68), (32, 80), (68, 20), (80, 32)] {
                        path.addEllipse(in: CGRect(
                            x: rect.n(CGFloat(point.0) - 8, CGFloat(point.1) - 8).x,
                            y: rect.n(CGFloat(point.0) - 8, CGFloat(point.1) - 8).y,
                            width: rect.s(16), height: rect.s(16)))
                    }
                }
                .fill(accent)

                Circle()
                    .fill(Palette.card)
                    .frame(width: rect.s(20), height: rect.s(20))
                    .position(rect.n(50, 50))
                Circle()
                    .stroke(accent, lineWidth: rect.s(4))
                    .frame(width: rect.s(20), height: rect.s(20))
                    .position(rect.n(50, 50))
                RadiatingLines(origin: CGPoint(x: 50, y: 50), count: 4,
                               innerRadius: 15, outerRadius: 24, arc: 270, startAngle: 45)
                    .stroke(accent.opacity(0.8), style: StrokeStyle(lineWidth: rect.s(3.5), lineCap: .round))
            }
        }
    }

    private var rash: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                // A circular patch, concentric with the wash behind it. Drawn
                // as a rounded square this was the only motif in the list that
                // read as a tile instead of a disc.
                Circle().fill(accent.opacity(0.18))
                Circle().stroke(accent, lineWidth: rect.s(4.5))
                // Scattered spots, deliberately irregular
                Path { path in
                    let spots: [(CGFloat, CGFloat, CGFloat)] = [
                        (32, 34, 6), (52, 28, 4.5), (68, 40, 5.5),
                        (38, 54, 5), (58, 58, 6.5), (30, 70, 4),
                        (50, 74, 5), (70, 66, 4.5)
                    ]
                    for spot in spots {
                        path.addEllipse(in: CGRect(
                            x: rect.n(spot.0 - spot.2, spot.1 - spot.2).x,
                            y: rect.n(spot.0 - spot.2, spot.1 - spot.2).y,
                            width: rect.s(spot.2 * 2), height: rect.s(spot.2 * 2)))
                    }
                }
                .fill(accent)
            }
            // Every other motif is a line drawing that sits comfortably inside
            // the circular wash. The rash patch is a filled square, whose
            // corners overran the circle and made this one row look like a
            // tile among discs. A square inscribed in a circle is ~0.71 of its
            // diameter, so it needs pulling in rather than merely padding.
            .scaleEffect(0.96)
        }
    }

    private var nausea: some View {
        ZStack {
            TorsoShape().fill(accent.opacity(0.18))
            TorsoShape().stroke(accent, lineWidth: size * 0.04)
            WaveLines(rows: 3, top: 62, spacing: 10, amplitude: 4)
                .stroke(accent, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
        }
    }

    // MARK: - Warning signs

    private var abdominal: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                TorsoShape().fill(accent.opacity(0.16))
                TorsoShape().stroke(accent, lineWidth: rect.s(4))
                Circle()
                    .fill(accent)
                    .frame(width: rect.s(16), height: rect.s(16))
                    .position(rect.n(50, 74))
                RadiatingLines(origin: CGPoint(x: 50, y: 74), count: 6,
                               innerRadius: 13, outerRadius: 22)
                    .stroke(accent, style: StrokeStyle(lineWidth: rect.s(3.5), lineCap: .round))
            }
        }
    }

    private var vomiting: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                HeadProfileShape()
                    .fill(accent.opacity(0.2))
                    .rotationEffect(.degrees(18), anchor: .center)
                HeadProfileShape()
                    .stroke(accent, lineWidth: rect.s(4))
                    .rotationEffect(.degrees(18), anchor: .center)
                Path { path in
                    for drop in [(74, 74, 5.0), (84, 62, 3.5), (68, 86, 3.0)] {
                        path.addEllipse(in: CGRect(
                            x: rect.n(CGFloat(drop.0) - CGFloat(drop.2), CGFloat(drop.1) - CGFloat(drop.2)).x,
                            y: rect.n(CGFloat(drop.0) - CGFloat(drop.2), CGFloat(drop.1) - CGFloat(drop.2)).y,
                            width: rect.s(CGFloat(drop.2) * 2), height: rect.s(CGFloat(drop.2) * 2)))
                    }
                }
                .fill(accent)
            }
        }
    }

    private var bleeding: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                HeadProfileShape().fill(accent.opacity(0.18))
                HeadProfileShape().stroke(accent, lineWidth: rect.s(4))
                // A drop falling from the nose
                DropletShape()
                    .fill(accent)
                    .frame(width: rect.s(18), height: rect.s(20))
                    .position(rect.n(26, 78))
            }
        }
    }

    private var fatigue: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                TorsoShape()
                    .fill(accent.opacity(0.16))
                    .rotationEffect(.degrees(-12), anchor: .bottom)
                TorsoShape()
                    .stroke(accent, lineWidth: rect.s(4))
                    .rotationEffect(.degrees(-12), anchor: .bottom)
                // Downward motion marks
                Path { path in
                    for x in [70.0, 80.0] {
                        path.move(to: rect.n(CGFloat(x), 34))
                        path.addLine(to: rect.n(CGFloat(x), 62))
                    }
                }
                .stroke(accent.opacity(0.7), style: StrokeStyle(lineWidth: rect.s(4), lineCap: .round))
            }
        }
    }

    private var fluid: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                TorsoShape().fill(accent.opacity(0.12))
                // Fluid filling the lower half
                TorsoShape()
                    .fill(accent.opacity(0.45))
                    .mask(Rectangle().padding(.top, geometry.size.height * 0.58))
                TorsoShape().stroke(accent, lineWidth: rect.s(4))
                WaveLines(rows: 1, top: 60, spacing: 0, amplitude: 5)
                    .stroke(accent, style: StrokeStyle(lineWidth: rect.s(4), lineCap: .round))
            }
        }
    }

    private var noUrine: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                DropletShape()
                    .fill(accent.opacity(0.2))
                    .frame(width: rect.s(58), height: rect.s(66))
                    .position(rect.n(50, 50))
                DropletShape()
                    .stroke(accent, lineWidth: rect.s(4.5))
                    .frame(width: rect.s(58), height: rect.s(66))
                    .position(rect.n(50, 50))
                // Struck through: the absence is the point
                Path { path in
                    path.move(to: rect.n(20, 82))
                    path.addLine(to: rect.n(80, 18))
                }
                .stroke(Palette.card, style: StrokeStyle(lineWidth: rect.s(11), lineCap: .round))
                Path { path in
                    path.move(to: rect.n(22, 80))
                    path.addLine(to: rect.n(78, 20))
                }
                .stroke(accent, style: StrokeStyle(lineWidth: rect.s(5), lineCap: .round))
            }
        }
    }

    // MARK: - Emergency signs

    private var faint: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                TorsoShape()
                    .fill(accent.opacity(0.16))
                    .rotationEffect(.degrees(-38), anchor: .bottomTrailing)
                TorsoShape()
                    .stroke(accent, lineWidth: rect.s(4))
                    .rotationEffect(.degrees(-38), anchor: .bottomTrailing)
                // Ground line — the figure is going down, not just leaning
                Path { path in
                    path.move(to: rect.n(12, 90))
                    path.addLine(to: rect.n(88, 90))
                }
                .stroke(accent, style: StrokeStyle(lineWidth: rect.s(5), lineCap: .round))
            }
        }
    }

    private var confusion: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                HeadProfileShape().fill(accent.opacity(0.18))
                HeadProfileShape().stroke(accent, lineWidth: rect.s(4))
                // A tangle where clear thought should be
                Path { path in
                    path.move(to: rect.n(36, 50))
                    path.addCurve(to: rect.n(58, 38),
                                  control1: rect.n(40, 34), control2: rect.n(58, 30))
                    path.addCurve(to: rect.n(38, 34),
                                  control1: rect.n(58, 46), control2: rect.n(34, 44))
                    path.addCurve(to: rect.n(60, 52),
                                  control1: rect.n(42, 24), control2: rect.n(64, 36))
                }
                .stroke(accent, style: StrokeStyle(lineWidth: rect.s(4), lineCap: .round))
            }
        }
    }

    private var heavyBleed: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                DropletShape()
                    .fill(accent)
                    .frame(width: rect.s(48), height: rect.s(56))
                    .position(rect.n(42, 44))
                DropletShape()
                    .fill(accent.opacity(0.6))
                    .frame(width: rect.s(30), height: rect.s(34))
                    .position(rect.n(72, 68))
                DropletShape()
                    .fill(accent.opacity(0.4))
                    .frame(width: rect.s(20), height: rect.s(23))
                    .position(rect.n(26, 80))
            }
        }
    }

    private var fallback: some View {
        Image(systemName: "staroflife.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(accent)
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 16) {
            ForEach(TriageEngine.symptoms) { symptom in
                VStack(spacing: 6) {
                    SymptomIllustration(symptomID: symptom.id, group: symptom.group, size: 76)
                    Text(symptom.id).font(.caption2)
                }
            }
        }
        .padding()
    }
}
