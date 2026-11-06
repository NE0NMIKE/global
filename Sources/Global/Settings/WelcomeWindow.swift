import AppKit
import SwiftUI

/// First-launch setup: two names and the partner's city, in one short form.
/// Shown until "Start" succeeds; everything can be changed later in Settings.
struct WelcomeView: View {
    @ObservedObject var settings: AppSettings
    let done: () -> Void

    @State private var myName = ""
    @State private var partnerName = ""
    @State private var city = ""
    @State private var openAtLogin = true
    @State private var isWorking = false
    @State private var error: String?

    /// Apps run from a disk image or Downloads can't open at login and stop
    /// working once the download is deleted.
    private static var isInApplications: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            Text("Welcome to Global").font(.title.weight(.semibold))
            Text("Your desktop becomes a globe showing where you both are, how far apart you are and the time for each of you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !Self.isInApplications {
                Label("Drag Global into your Applications folder first, then open it from there.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                TextField("Your name", text: $myName)
                TextField("Partner’s name", text: $partnerName)
                TextField("Partner’s city", text: $city, prompt: Text("e.g. Tokyo"))
                    .onSubmit(start)
                Toggle("Open Global when I log in", isOn: $openAtLogin)
                    .disabled(!Self.isInApplications)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 190)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            Button(action: start) {
                HStack(spacing: 8) {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text("Start")
                }
                .frame(minWidth: 140)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canStart)

            Text("Your own city is found automatically: click Allow when macOS asks about Location. It never leaves this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 440)
        .onAppear {
            myName = settings.myName
            partnerName = settings.partnerName
            city = settings.partnerPlace?.city ?? ""
        }
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canStart: Bool {
        !isWorking && !trimmed(myName).isEmpty && !trimmed(partnerName).isEmpty && !trimmed(city).isEmpty
    }

    private func start() {
        guard canStart else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            let query = trimmed(city)
            let place: Place
            if let current = settings.partnerPlace, current.city == query {
                place = current
            } else {
                do {
                    place = try await CityLookup.place(for: query)
                } catch {
                    self.error = error.localizedDescription
                    return
                }
            }
            settings.myName = trimmed(myName)
            settings.partnerName = trimmed(partnerName)
            settings.partnerPlace = place
            if openAtLogin && Self.isInApplications { LaunchAtLogin.set(true) }
            settings.hasLaunchedBefore = true
            done()
        }
    }
}

@MainActor
final class WelcomeWindowController: NSWindowController {
    init(settings: AppSettings) {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: WelcomeView(settings: settings) { [weak self] in self?.close() })
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
