import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct DistributionManifest: Codable {
    let schemaVersion: Int
    let product: String
    let version: String
    let archiveURL: URL
    let archiveSHA256: String
    let releaseNotes: String
}

@main
struct Mac3LauncherApp: App {
    @StateObject private var launcher = LauncherStore()

    var body: some Scene {
        WindowGroup("mac3 Launcher") {
            ContentView()
                .environmentObject(launcher)
                .frame(minWidth: 620, minHeight: 450)
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @EnvironmentObject private var launcher: LauncherStore
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("mac3 Launcher").font(.largeTitle.bold())
                Text(launcher.hasImportedGameData
                     ? "Grand Theft Auto III is ready to play."
                     : "Set up your original GTA III files once, then play without Steam.")
                    .foregroundStyle(.secondary)
            }

            if launcher.hasImportedGameData { installedView } else { setupView }

            VStack(alignment: .leading, spacing: 8) {
                if launcher.isBusy { ProgressView() }
                Text(launcher.status)
                    .font(.callout)
                    .foregroundStyle(launcher.hasError ? .red : .secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            Text("mac3 keeps its imported game data, engine, and verified updates inside this app, so the completed mac3.app is portable. Do not use the legacy in-game Terminal updater.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [9]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: launcher.acceptDrop)
    }

    private var setupView: some View {
        GroupBox("First-time setup") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose or drag in your original Grand Theft Auto III.app. mac3 imports its game data and streamed audio once, then stores the complete playable game inside this mac3.app.")
                    .foregroundStyle(.secondary)
                if let candidate = launcher.detectedSourcePath {
                    Text("Detected: \(candidate)")
                        .font(.callout.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Button("Use Detected Copy") { launcher.useDetectedSource() }
                        .buttonStyle(.borderedProminent)
                        .disabled(launcher.isBusy)
                }
                HStack {
                    Button("Choose GTA III App or Folder…") { launcher.chooseSource() }
                    Text("Original release only — not Definitive Edition.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var installedView: some View {
        GroupBox("mac3") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Engine version", value: launcher.activeManifest.version)
                if let update = launcher.availableUpdate {
                    Text("Version \(update.version) is available.").foregroundStyle(.tint)
                }
                HStack {
                    Button("Play") { launcher.play() }
                        .buttonStyle(.borderedProminent)
                        .disabled(launcher.isBusy || !launcher.playableAppExists)
                    Button("Check for Updates") { launcher.checkForUpdate() }.disabled(launcher.isBusy)
                    if let update = launcher.availableUpdate {
                        Button("Install \(update.version)") { launcher.install(update) }.disabled(launcher.isBusy)
                    }
                    Button("Rebuild") { launcher.rebuild() }.disabled(launcher.isBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

@MainActor
final class LauncherStore: ObservableObject {
    @Published var status = "Looking for an installed GTA III copy…"
    @Published var isBusy = false
    @Published var hasError = false
    @Published var hasImportedGameData = false
    @Published var playableAppExists = false
    @Published var detectedSourcePath: String?
    @Published var availableUpdate: DistributionManifest?

    let bundledManifest: DistributionManifest
    private let fileManager = FileManager.default
    private var runningGame: Process?

    init() {
        do {
            bundledManifest = try JSONDecoder().decode(DistributionManifest.self,
                from: Data(contentsOf: Self.resourceURL("DistributionManifest", "json")))
        } catch { fatalError("Missing or invalid bundled distribution manifest: \(error)") }
        refreshState()
        detectedSourcePath = Self.detectedSource()?.path
        status = hasImportedGameData ? "Choose Play, Check for Updates, or Rebuild." : "Choose or drop in your original GTA III app."
    }

    var activeManifest: DistributionManifest {
        guard let data = try? Data(contentsOf: Self.activeManifestURL()),
              let manifest = try? JSONDecoder().decode(DistributionManifest.self, from: data) else { return bundledManifest }
        return manifest
    }

    var playableAppURL: URL { Self.playableURL() }

    func chooseSource() {
        let panel = NSOpenPanel()
        panel.title = "Choose your original GTA III app or game folder"
        panel.message = "Select the original Steam wrapper or the folder containing models/gta3.img."
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAndBuild(from: url)
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { self?.importAndBuild(from: url) }
        }
        return true
    }

    func useDetectedSource() {
        guard let path = detectedSourcePath else { return }
        importAndBuild(from: URL(fileURLWithPath: path))
    }

    func rebuild() {
        runWorker("Rebuilding mac3 from its embedded game data…") { [activeManifest] in
            try Self.build(archive: try Self.archiveURL(for: activeManifest), manifest: activeManifest,
                           gameData: Self.gameDataURL(), output: Self.playableURL())
        } success: { [weak self] in self?.refreshState(); self?.setStatus("mac3 rebuilt and ready to play.", error: false) }
    }

    func play() {
        guard playableAppExists, runningGame == nil else { return }
        let process = Process()
        process.executableURL = playableAppURL.appendingPathComponent("Contents/MacOS/mac3")
        process.currentDirectoryURL = Self.gameDataURL()
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.runningGame = nil
                NSApp.setActivationPolicy(.regular)
                NSApp.unhide(nil)
                NSApp.activate(ignoringOtherApps: true)
                self.setStatus("Welcome back. Choose Play, Check for Updates, or Rebuild.", error: false)
            }
        }
        do {
            try process.run()
            runningGame = process
            setStatus("GTA III is running. mac3 Launcher will return when you quit the game.", error: false)
            NSApp.hide(nil)
            NSApp.setActivationPolicy(.prohibited)
        } catch { setStatus("Could not launch GTA III. \(error.localizedDescription)", error: true) }
    }

    func checkForUpdate() {
        isBusy = true
        setStatus("Checking your fork for a verified distribution update…", error: false)
        let url = URL(string: "https://raw.githubusercontent.com/malouf-dev/mac3/main/DistributionManifest.json")!
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                guard error == nil, let data, let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let remote = try? JSONDecoder().decode(DistributionManifest.self, from: data),
                      remote.product == "mac3", remote.schemaVersion == 1 else {
                    self.setStatus("No mac3-compatible update manifest is published in your fork yet.", error: true); return
                }
                if remote.version.compare(self.activeManifest.version, options: .numeric) == .orderedDescending {
                    self.availableUpdate = remote
                    self.setStatus("Version \(remote.version) is available. Choose Install to download, verify, and rebuild.", error: false)
                } else {
                    self.availableUpdate = nil; self.setStatus("mac3 \(self.activeManifest.version) is current.", error: false)
                }
            }
        }.resume()
    }

    func install(_ manifest: DistributionManifest) {
        runWorker("Downloading, verifying, and installing \(manifest.version)…") {
            try Self.assertWritableLauncherBundle()
            let data = try Data(contentsOf: manifest.archiveURL)
            guard !data.isEmpty else { throw LauncherError("Empty update archive.") }
            let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mac3-update-\(UUID().uuidString).tar.gz")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary, options: .atomic)
            guard try Self.sha256(temporary) == manifest.archiveSHA256 else { throw LauncherError("Downloaded archive did not match the fork’s pinned SHA-256.") }
            let archive = try Self.cacheURL(for: manifest)
            try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: temporary, to: archive)
            try JSONEncoder().encode(manifest).write(to: Self.activeManifestURL(), options: .atomic)
            try Self.build(archive: archive, manifest: manifest, gameData: Self.gameDataURL(), output: Self.playableURL())
        } success: { [weak self] in self?.availableUpdate = nil; self?.refreshState(); self?.setStatus("Version \(manifest.version) is installed and ready to play.", error: false) }
    }

    private func importAndBuild(from source: URL) {
        runWorker("Importing your GTA III data and building mac3…") {
            try Self.assertWritableLauncherBundle()
            let data = try Self.resolveGameDirectory(source)
            let manifest = try Self.activeManifest()
            try Self.build(archive: try Self.archiveURL(for: manifest), manifest: manifest, gameData: data, output: Self.playableURL())
        } success: { [weak self] in self?.refreshState(); self?.setStatus("Setup complete. mac3 is ready to play.", error: false) }
    }

    private func runWorker(_ message: String, work: @escaping () throws -> Void, success: @escaping () -> Void) {
        isBusy = true; setStatus(message, error: false)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try work()
                DispatchQueue.main.async { self?.isBusy = false; success() }
            } catch {
                DispatchQueue.main.async { self?.isBusy = false; self?.setStatus("\(message) \(error.localizedDescription)", error: true) }
            }
        }
    }

    private func refreshState() {
        hasImportedGameData = fileManager.fileExists(atPath: Self.gameDataURL().appendingPathComponent("models/gta3.img").path)
        playableAppExists = fileManager.fileExists(atPath: playableAppURL.path)
    }
    private func setStatus(_ text: String, error: Bool) { status = text; hasError = error }

    private static func portableURL() -> URL { Bundle.main.resourceURL!.appendingPathComponent("Portable", isDirectory: true) }
    private static func playableURL() -> URL { portableURL().appendingPathComponent("Playable/mac3.app", isDirectory: true) }
    private static func gameDataURL() -> URL { playableURL().appendingPathComponent("Contents/Resources/GameData", isDirectory: true) }
    private static func activeManifestURL() -> URL { portableURL().appendingPathComponent("active-distribution.json") }
    private static func cacheURL(for manifest: DistributionManifest) throws -> URL {
        portableURL().appendingPathComponent("Distributions/mac3-\(manifest.version)-\(manifest.archiveSHA256.prefix(12)).tar.gz")
    }
    private static func assertWritableLauncherBundle() throws {
        guard FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.path) else {
            throw LauncherError("mac3.app is not writable. Copy it to a writable folder such as Applications or Downloads, then run setup again.")
        }
    }
    private static func resourceURL(_ name: String, _ ext: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { throw LauncherError("Missing bundled resource \(name).\(ext).") }
        return url
    }
    private static func activeManifest() throws -> DistributionManifest {
        if let data = try? Data(contentsOf: activeManifestURL()), let manifest = try? JSONDecoder().decode(DistributionManifest.self, from: data) { return manifest }
        return try JSONDecoder().decode(DistributionManifest.self, from: Data(contentsOf: resourceURL("DistributionManifest", "json")))
    }
    private static func archiveURL(for manifest: DistributionManifest) throws -> URL {
        let cached = try cacheURL(for: manifest)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        let bundled = try resourceURL("mac3-macos-arm64", "tar.gz")
        guard try sha256(bundled) == manifest.archiveSHA256 else { throw LauncherError("Bundled distribution does not match its SHA-256 manifest.") }
        return bundled
    }
    private static func resolveGameDirectory(_ root: URL) throws -> URL {
        let candidates = [
            root,
            root.appendingPathComponent("Contents/Resources/GameData"),
            root.appendingPathComponent("Contents/Resources/transgaming/c_drive/Program Files/Rockstar Games/GTAIII"),
            root.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Rockstar Games/GTAIII"),
            root.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/Program Files/Rockstar Games/GTAIII")
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.appendingPathComponent("models/gta3.img").path) { return candidate }
        throw LauncherError("No GTA III data found. Expected models/gta3.img in the selected item.")
    }
    private static func detectedSource() -> URL? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let candidates = [
            home.appendingPathComponent("Library/Application Support/Steam/steamapps/common/grand theft auto 3/Grand Theft Auto 3.app"),
            home.appendingPathComponent("Downloads/Grand Theft Auto 3.app"),
            home.appendingPathComponent("Downloads/Grand Theft Auto III.app")
        ]
        return candidates.first { (try? resolveGameDirectory($0)) != nil }
    }
    private static func streamedAudioDirectory(for gameData: URL) -> URL? {
        var ciderRoot = gameData
        for _ in 0..<3 { ciderRoot.deleteLastPathComponent() }
        let candidates = [gameData.appendingPathComponent("audio"), gameData.appendingPathComponent("Audio"), ciderRoot.appendingPathComponent("Audio"), ciderRoot.appendingPathComponent("audio")]
        return candidates.first { directory in
            ["head.wav", "head.mp3", "head.adf"].contains { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
        }
    }
    private static func build(archive: URL, manifest: DistributionManifest, gameData: URL, output: URL) throws {
        guard try sha256(archive) == manifest.archiveSHA256 else { throw LauncherError("Distribution archive checksum failed.") }
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mac3-launcher-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        try run("/usr/bin/tar", ["-xzf", archive.path, "-C", temporary.path])
        let app = temporary.appendingPathComponent("mac3.app", isDirectory: true)
        let appData = app.appendingPathComponent("Contents/Resources/GameData", isDirectory: true)
        let executable = app.appendingPathComponent("Contents/MacOS/mac3")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw LauncherError("Distribution archive is missing its native executable.") }
        let seed = temporary.appendingPathComponent("seed", isDirectory: true)
        try run("/usr/bin/ditto", [appData.path, seed.path])
        try run("/usr/bin/ditto", [gameData.path, appData.path])
        if !FileManager.default.fileExists(atPath: appData.appendingPathComponent("audio").path), let audio = streamedAudioDirectory(for: gameData) {
            try FileManager.default.createDirectory(at: appData.appendingPathComponent("audio"), withIntermediateDirectories: true)
            try run("/usr/bin/ditto", [audio.path, appData.appendingPathComponent("audio").path])
        }
        try run("/usr/bin/ditto", [seed.path, appData.path])
        _ = try? run("/usr/bin/xattr", ["-cr", app.path])
        try disableLegacyUpdater(in: executable)
        try "\(sha256(executable))\n".write(to: app.appendingPathComponent("Contents/Resources/version.sha"), atomically: true, encoding: .utf8)
        let frameworks = app.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        for library in try FileManager.default.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil) where library.pathExtension == "dylib" {
            try run("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", library.path])
        }
        try run("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", executable.path])
        try run("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", app.path])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try run("/usr/bin/ditto", [app.path, output.path])
        try signLauncherBundle()
    }
    private static func signLauncherBundle() throws {
        try assertWritableLauncherBundle()
        let launcher = Bundle.main.bundleURL
        try run("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", launcher.path])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", launcher.path])
    }
    private static func disableLegacyUpdater(in executable: URL) throws {
        var data = try Data(contentsOf: executable)
        // In mac3 1.0.3183, CGame::InitialiseOnceBeforeRW calls
        // ValidateVersion() at this fixed Mach-O file offset. The old routine
        // invokes the upstream curl/Terminal updater and crashes when it has
        // no response. Replace its single `bl ValidateVersion` with `nop`.
        let versionCheckCallOffset = 0xE9288
        let expectedCall = Data([0x46, 0xE7, 0x00, 0x94])
        let noOperation = Data([0x1F, 0x20, 0x03, 0xD5])
        guard data.count >= versionCheckCallOffset + expectedCall.count,
              data.subdata(in: versionCheckCallOffset..<(versionCheckCallOffset + expectedCall.count)) == expectedCall else {
            throw LauncherError("Cannot locate the legacy version-check call in this distribution.")
        }
        data.replaceSubrange(versionCheckCallOffset..<(versionCheckCallOffset + expectedCall.count), with: noOperation)
        let commands = [
            "curl -fsSL --connect-timeout 2 -m 5 https://raw.githubusercontent.com/gtamac/mac3/main/version.sha 2>/dev/null",
            "osascript -e 'tell application \"Terminal\" to activate' -e 'tell application \"Terminal\" to do script \"curl -fsSL https://raw.githubusercontent.com/gtamac/mac3/main/quick-install.sh | bash\"'"
        ]
        for command in commands {
            let needle = Data(command.utf8)
            guard let range = data.range(of: needle) else {
                throw LauncherError("Cannot locate a legacy updater command in this distribution.")
            }
            data.replaceSubrange(range, with: Data("true".utf8) + Data(repeating: 0, count: needle.count - 4))
        }
        try data.write(to: executable, options: .atomic)
    }
    @discardableResult private static func run(_ command: String, _ arguments: [String]) throws -> String {
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: command); process.arguments = arguments
        process.standardOutput = output; process.standardError = output
        try process.run(); process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw LauncherError("\(URL(fileURLWithPath: command).lastPathComponent) failed: \(text.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return text
    }
    private static func sha256(_ url: URL) throws -> String { try run("/usr/bin/shasum", ["-a", "256", url.path]).split(separator: " ").first.map(String.init) ?? "" }
}

struct LauncherError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
