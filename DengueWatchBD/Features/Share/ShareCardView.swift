import SwiftUI

/// A single surveillance figure, drawn for sharing rather than for reading in
/// the app.
///
/// Fixed size and fixed colours on purpose. This is rasterised to a PNG that
/// will be seen on someone else's phone in a chat thread, so it must not
/// inherit the sender's Dark Mode, Dynamic Type setting or accent colour —
/// three things every other view in this app deliberately does inherit.
struct ShareCardView: View {
    /// 4:5 is the tallest a feed will show without cropping, which is what
    /// Facebook, Instagram and WhatsApp status all favour.
    static let size = CGSize(width: 1080, height: 1350)

    let areaName: String
    let riskLabel: String
    let riskTint: Color
    let incidence: String
    let incidenceUnit: String
    let weeklyChange: String?
    let weeklyChangeIsUp: Bool
    let seasonCases: String
    let seasonCasesLabel: String
    let sourceLine: String
    let appName: String
    let tagline: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(appName.uppercased())
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.75))

            Spacer(minLength: 60)

            Text(areaName)
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(2)

            HStack(spacing: 20) {
                Circle().fill(riskTint).frame(width: 34, height: 34)
                Text(riskLabel.uppercased())
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(riskTint)
            }
            .padding(.top, 26)

            if let weeklyChange {
                HStack(spacing: 14) {
                    Image(systemName: weeklyChangeIsUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 40, weight: .bold))
                    Text(weeklyChange)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 28)
            }

            Spacer(minLength: 40)

            HStack(spacing: 0) {
                figure(incidence, unit: incidenceUnit)
                Rectangle().fill(.white.opacity(0.18))
                    .frame(width: 1, height: 108)
                    .padding(.horizontal, 44)
                figure(seasonCases, unit: seasonCasesLabel)
            }

            Spacer(minLength: 50)

            // Attribution is not decoration: a number shared out of the app
            // without its source and date is a rumour.
            Text(sourceLine)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
            Text(tagline)
                .font(.system(size: 26, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.top, 6)
        }
        .padding(72)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
        .background {
            LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.13),
                                    Color(red: 0.12, green: 0.15, blue: 0.21)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // A faint wash of the risk colour, so the card reads at a glance in
            // a feed even before the words are.
            RadialGradient(colors: [riskTint.opacity(0.22), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 900)
        }
        .environment(\.colorScheme, .dark)
    }

    private func figure(_ value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
