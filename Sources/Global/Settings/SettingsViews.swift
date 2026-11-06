import CoreLocation
import SwiftUI

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var appModel: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        VStack(spacing: 0) {
            PairSummaryCard(model: appModel)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            form
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private var form: some View {
        Form {
            Section("People") {
                TextField("Your name", text: $settings.myName)
                TextField("Partner’s name", text: $settings.partnerName)
                CityField(label: "Partner’s city", place: $settings.partnerPlace)
                Toggle("Show “Since” date", isOn: Binding(
                    get: { settings.sinceDate != nil },
                    set: { settings.sinceDate = $0 ? (settings.sinceDate ?? Date()) : nil }))
                if settings.sinceDate != nil {
                    DatePicker("Since", selection: Binding(
                        get: { settings.sinceDate ?? Date() },
                        set: { settings.sinceDate = $0 }), displayedComponents: .date)
                }
            }

            Section("Behaviour") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        launchError = LaunchAtLogin.set(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }))
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                } else if LaunchAtLogin.needsApproval {
                    Text("Approve Global in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Pause animation", isOn: $settings.paused)
                Toggle("Pause on battery and in Low Power Mode", isOn: $settings.pauseOnBattery)
                Picker("Frame rate", selection: $settings.frameRate) {
                    Text("15 fps").tag(15)
                    Text("20 fps").tag(20)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A city typed by name, then looked up once for its coordinates and time
/// zone (see `CityLookup`). The previous place is kept until a lookup succeeds.
struct CityField: View {
    let label: String
    @Binding var place: Place?
    /// Shown under the field while no city is set.
    var emptyNote = "Not set"

    @State private var query = ""
    @State private var isSearching = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(label, text: $query, prompt: Text("e.g. Tokyo"))
                    .onSubmit(find)
                if isSearching {
                    ProgressView().controlSize(.small)
                }
                Button("Find", action: find)
                    .disabled(trimmed.isEmpty || isSearching || trimmed == place?.city)
            }
            Group {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if let p = place {
                    Text("Showing \(p.city) · \(Format.coordinates(p.coordinate)) · \(p.timeZoneID)")
                        .foregroundStyle(.secondary)
                } else {
                    Text(emptyNote).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .onAppear { query = place?.city ?? "" }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func find() {
        let q = trimmed
        guard !q.isEmpty, !isSearching else { return }
        isSearching = true
        error = nil
        Task {
            do {
                let found = try await CityLookup.place(for: q)
                place = found
                query = found.city
            } catch {
                self.error = error.localizedDescription
            }
            isSearching = false
        }
    }
}

/// Glass card summarising the two people.
struct PairSummaryCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let m = model.renderModel
        let km = GeoMath.distanceKm(m.me.coordinate, m.partner.coordinate)
        HStack(spacing: 16) {
            Image(systemName: m.style.symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(m.me.title)  ·  \(m.partner.title)")
                    .font(.headline)
                Text("\(Format.distance(km: km, useMiles: m.useMiles)) · \(InfoContent.timeDifference(partner: m.partner, me: m.me, now: Date()))")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(16)
        .glassCard()
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Style") {
                StylePicker(selection: $settings.style)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { a in
                        Label(a.title, systemImage: a.symbol).tag(a)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Motion") {
                Picker("Motion", selection: $settings.motion) {
                    ForEach(MotionMode.allCases) { m in
                        Label(m.title, systemImage: m.symbol).tag(m)
                    }
                }
                LabeledContent("Speed") {
                    Slider(value: $settings.motionSpeed, in: 0.25...3) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                }
                LabeledContent("Globe size") {
                    Slider(value: $settings.globeScale, in: 0.35...0.9) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "circle").imageScale(.small)
                    } maximumValueLabel: {
                        Image(systemName: "circle").imageScale(.large)
                    }
                }
            }

            Section("Show") {
                Toggle("Info panel", isOn: $settings.showInfoPanel)
                Toggle("Name tags on the globe", isOn: $settings.showGlobeTags)
                Toggle("Distance", isOn: $settings.showDistance)
                Toggle("Local times", isOn: $settings.showLocalTimes)
                Toggle("Day & night (real sun position)", isOn: $settings.showDayNight)
            }

            Section("Units") {
                Picker("Distance", selection: $settings.useMiles) {
                    Text("Kilometres").tag(false)
                    Text("Miles").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("24-hour clock", isOn: $settings.use24Hour)
            }
        }
        .formStyle(.grouped)
    }
}

/// Four selectable style tiles.
struct StylePicker: View {
    @Binding var selection: GlobeStyle

    var body: some View {
        HStack(spacing: 10) {
            ForEach(GlobeStyle.allCases) { style in
                let selected = style == selection
                Button {
                    selection = style
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: style.symbol)
                            .font(.system(size: 26, weight: .light))
                            .frame(height: 32)
                        Text(style.title).font(.callout.weight(selected ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08),
                                          lineWidth: selected ? 2 : 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Location

struct LocationSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var location: LocationService

    var body: some View {
        Form {
            Section {
                LabeledContent("Permission") {
                    Text(location.authorisationDescription)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(location.isAuthorised ? Color.secondary : Color.orange)
                }
                if let p = location.place {
                    LabeledContent("Current place") {
                        Text(p.city.isEmpty ? "Unknown city" : p.city)
                    }
                    LabeledContent("Coordinates") {
                        Text(Format.coordinates(p.coordinate)).monospacedDigit()
                    }
                } else {
                    LabeledContent("Current place") { Text("Not located yet").foregroundStyle(.secondary) }
                }
                if let err = location.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    if location.authorization == .denied {
                        Button("Open Privacy Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    if location.authorization == .notDetermined && location.lastError != nil {
                        Button("Open Privacy Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    Button("Locate Now") { location.requestNow() }
                }
            } footer: {
                FooterText("Your Mac finds its own city, rounded to about 11 km, and it never leaves this Mac. Macs locate using nearby Wi‑Fi, so it only updates while awake and online; the last known place is shown otherwise. Your partner’s city is set in General.")
            }

            Section {
                CityField(label: "Your city", place: $settings.myPlace,
                          emptyNote: "Optional. Used only when Location is off or unavailable.")
            } header: {
                Text("Without Location")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            Text("Global").font(.title.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("An animated globe wallpaper for two.")
            Divider().frame(width: 220)
            VStack(spacing: 4) {
                Text("Earth imagery: NASA Visible Earth (Blue Marble, Black Marble)")
                Text("Coastlines and borders: Natural Earth")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

/// Leading-aligned caption for form section footers (macOS centres or
/// trails them by default).
struct FooterText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}
