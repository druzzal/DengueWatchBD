import SwiftUI
import MapKit
import CoreLocation

struct CareView: View {
    @Environment(LocalizationManager.self) private var loc
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(LocationManager.self) private var location

    @State private var search = NearbyHospitalSearch()
    @State private var divisionFilter: Division?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if sizeClass == .regular {
                        ScreenTitle(text: loc.t("care.title"))
                    }
                    emergencyCard
                    nearbyCard
                    directoryCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .readableColumn()
            }
            .background(Palette.plane)
            .columnAlignedTitle(loc.t("care.title"), isWide: sizeClass == .regular)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LanguageToggle() }
            }
            .task {
                if location.isAuthorized { location.startUpdatingCoarse() }
            }
        }
    }

    // MARK: - Emergency numbers

    private var emergencyCard: some View {
        CardSection(loc.t("care.sos.title")) {
            VStack(spacing: 0) {
                ForEach(Array(EmergencyNumber.all.enumerated()), id: \.element.id) { index, number in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(loc.t(number.nameKey))
                                .typo(.subheadline).fontWeight(.semibold)
                            Text(loc.t(number.detailKey))
                                .typo(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if let url = URL(string: "tel://\(number.dial)") {
                            Link(destination: url) {
                                Label(loc.t("care.call"), systemImage: "phone.fill")
                                    .typo(.caption).fontWeight(.semibold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .frame(minHeight: Hit.minimum - 14)
                                    .background {
                                        if number.isEmergency {
                                            Capsule().fill(Palette.riskTint(.severe))
                                        } else {
                                            Capsule().fill(Palette.accent.opacity(0.12))
                                                .overlay(Capsule().strokeBorder(
                                                    Palette.accent.opacity(0.35), lineWidth: 1))
                                        }
                                    }
                                    .foregroundStyle(number.isEmergency ? .white : Palette.accent)
                            }
                        }
                    }
                    .padding(.vertical, 11)

                    if index < EmergencyNumber.all.count - 1 {
                        Divider().overlay(Palette.hairline)
                    }
                }
            }
            Text(loc.t("care.sos.footer"))
                .typo(.micro).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Live nearby search

    private var nearbyCard: some View {
        CardSection(loc.t("care.nearby.title"), subtitle: loc.t("care.nearby.subtitle")) {
            switch search.state {
            case .idle:
                Button {
                    Task { await runSearch() }
                } label: {
                    Label(loc.t("care.nearby.search"), systemImage: "location.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

            case .searching:
                RowsSkeleton(count: 3)
                    .accessibilityLabel(loc.t("care.nearby.searching"))

            case .needsPermission:
                LocationPermissionCard()

            case .empty:
                EmptyStateView(symbol: "mappin.slash",
                               title: loc.t("care.nearby.empty"))

            case .failed:
                ErrorStateView(title: loc.t("care.nearby.empty"),
                               retry: { Task { await runSearch() } })

            case .results(let hospitals):
                VStack(spacing: 0) {
                    ForEach(Array(hospitals.prefix(8).enumerated()), id: \.element.id) { index, hospital in
                        nearbyRow(hospital)
                        if index < min(hospitals.count, 8) - 1 {
                            Divider().overlay(Palette.hairline)
                        }
                    }
                }
                Button {
                    Task { await runSearch() }
                } label: {
                    Label(loc.t("care.nearby.search"), systemImage: "arrow.clockwise").typo(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
            }
        }
    }

    private func nearbyRow(_ hospital: NearbyHospital) -> some View {
        FacilityRow(
            name: hospital.name,
            subtitle: hospital.address,
            distanceText: hospital.distance.map {
                loc.t("care.nearby.distance", loc.decimal($0 / 1000))
            },
            onDirections: { MapsLauncher.directions(to: hospital.mapItem) },
            onCall: hospital.phone.flatMap { phone in
                URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })").map { url in
                    { UIApplication.shared.open(url) }
                }
            }
        )
    }

    private func runSearch() async {
        if !location.isAuthorized {
            location.requestWhenInUse()
        }
        location.startUpdatingCoarse()
        await search.search(around: location.lastKnownLocation)
    }

    // MARK: - Curated directory

    private var directoryCard: some View {
        CardSection(loc.t("care.dghs.title"), subtitle: loc.t("care.dghs.subtitle")) {
            Menu {
                Button(loc.t("care.division.all")) { divisionFilter = nil }
                ForEach(Division.allCases) { division in
                    Button(division.displayName(loc.language)) { divisionFilter = division }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(divisionFilter?.displayName(loc.language) ?? loc.t("care.division.all"))
                        .typo(.caption).fontWeight(.medium)
                }
                .foregroundStyle(Palette.accent)
            }

            let hospitals = HospitalDirectory.hospitals(in: divisionFilter)
            VStack(spacing: 0) {
                ForEach(Array(hospitals.enumerated()), id: \.element.id) { index, hospital in
                    Button {
                        if let url = MapsLauncher.search(query: hospital.mapQuery) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(hospital.name(for: loc.language))
                                    .typo(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Text(hospital.city(for: loc.language))
                                    .typo(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "map")
                                .typo(.caption)
                                .foregroundStyle(Palette.accent)
                                .padding(.top, 2)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < hospitals.count - 1 { Divider().overlay(Palette.hairline) }
                }
            }

            InlineNote(symbol: "exclamationmark.triangle",
                       detail: loc.t("care.dghs.footer"))
        }
    }
}
