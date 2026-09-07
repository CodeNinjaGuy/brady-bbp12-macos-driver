//
//  Brady BBP12 Konfiguration
//
//  Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
//  MIT License - https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
//
//  Kleines Konfigurationsfenster fuer den Brady-BBP12-Treiber: Etikettengroessen
//  anlegen, Druckursprung kalibrieren, Druckqualitaet festlegen, Testdruck.
//

import SwiftUI
import AppKit

// MARK: - Shell

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (code: Int32, out: String, err: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do { try proc.run() } catch { return (-1, "", "\(error)") }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }

    /// Fuehrt einen Befehl mit Administratorrechten aus; macOS fragt selbst nach dem Passwort.
    static func admin(_ command: String) -> (ok: Bool, message: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let result = run("/usr/bin/osascript",
                         ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
        if result.code != 0 {
            let raw = result.err.trimmingCharacters(in: .whitespacesAndNewlines)
            return (false, raw.contains("-128") ? "Abgebrochen." : raw)
        }
        return (true, result.out.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Pfade

enum Paths {
    static let ppd  = "/Library/Printers/PPDs/Contents/Resources/BradyBBP12.ppd"
    static let conf = "/Library/Printers/Brady/bbp12.conf"
    static var resources: String { Bundle.main.resourcePath ?? "." }
    static var labelTool: String { resources + "/label-size.py" }
    static var calibTool: String { resources + "/make_calibration.py" }
}

// MARK: - Modell

struct LabelSize: Identifiable, Hashable {
    let id: String
    let label: String
    let wmm: Double
    let hmm: Double
    let isDefault: Bool
}

@MainActor
final class Driver: ObservableObject {
    @Published var queues: [String] = []
    @Published var queue = ""
    @Published var sizes: [LabelSize] = []
    @Published var selectedSize: LabelSize.ID?
    @Published var didPreselect = false
    @Published var dpi = 300

    @Published var xoffMM = "0.0"
    @Published var yoffMM = "0.0"

    @Published var density = 8.0
    @Published var speed = 2
    @Published var dither = "Threshold"
    @Published var media = "Gap"
    @Published var gapMM = "3"
    @Published var ribbon = "On"
    @Published var pinQuality = false

    @Published var status = ""
    @Published var busy = false
    @Published var installed = true

    var dotsPerMM: Double { Double(dpi) / 25.4 }
    var size: LabelSize? { sizes.first { $0.id == selectedSize } }

    func reload() {
        installed = FileManager.default.fileExists(atPath: Paths.ppd)
        guard installed else {
            status = "Treiber nicht gefunden. Bitte zuerst install.sh ausfuehren."
            return
        }
        loadQueues()
        loadPPD()
        loadSizes()
        loadConf()
    }

    private func loadQueues() {
        let dir = "/etc/cups/ppd"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        queues = files.filter { $0.hasSuffix(".ppd") }.compactMap { file -> String? in
            guard let text = try? String(contentsOfFile: "\(dir)/\(file)", encoding: .isoLatin1),
                  text.contains("Brady BBP12 TSPL") else { return nil }
            return String(file.dropLast(4))
        }.sorted()
        if queue.isEmpty || !queues.contains(queue) { queue = queues.first ?? "" }
    }

    private func loadPPD() {
        guard let text = try? String(contentsOfFile: Paths.ppd, encoding: .isoLatin1) else { return }
        for line in text.split(separator: "\n") where line.hasPrefix("*DefaultResolution:") {
            dpi = line.contains("203") ? 203 : 300
        }
    }

    private func loadSizes() {
        let r = Shell.run("/usr/bin/python3", [Paths.labelTool, "list", "--ppd", Paths.ppd])
        sizes = r.out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4 else { return nil }
            let mm = f[3].replacingOccurrences(of: " mm", with: "").split(separator: "x")
            guard mm.count == 2,
                  let w = Double(mm[0].trimmingCharacters(in: .whitespaces)),
                  let h = Double(mm[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            let isDefault = f.count >= 5 && f[4].trimmingCharacters(in: .whitespaces) == "*"
            return LabelSize(id: f[0], label: f[1], wmm: w, hmm: h, isDefault: isDefault)
        }
        // Beim ersten Laden das Standardformat des Treibers vorwaehlen, nicht
        // einfach den ersten Listeneintrag -- sonst druckt der Testknopf das
        // falsche Etikett.
        if !didPreselect || !sizes.contains(where: { $0.id == selectedSize }) {
            selectedSize = (sizes.first { $0.isDefault } ?? sizes.first)?.id
            didPreselect = true
        }
    }

    private func loadConf() {
        guard let text = try? String(contentsOfFile: Paths.conf, encoding: .utf8) else { return }
        var found: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: " ", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2 { found[parts[0]] = parts[1] }
        }
        if let v = found["BradyXOffset"], let d = Double(v) {
            xoffMM = String(format: "%.1f", d / dotsPerMM)
        }
        if let v = found["BradyYOffset"], let d = Double(v) {
            yoffMM = String(format: "%.1f", d / dotsPerMM)
        }
        pinQuality = found["BradyDensity"] != nil
        if let v = found["BradyDensity"], let d = Double(v) { density = d }
        if let v = found["BradySpeed"], let i = Int(v) { speed = i }
        if let v = found["BradyDither"] { dither = v }
        if let v = found["BradyMediaType"] { media = v }
        if let v = found["BradyGap"] { gapMM = v }
        if let v = found["BradyRibbon"] { ribbon = v }
    }

    // MARK: Aktionen

    private func mm(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    func saveConfig() {
        let x = Int((mm(xoffMM) * dotsPerMM).rounded())
        let y = Int((mm(yoffMM) * dotsPerMM).rounded())
        var text = """
        # Brady BBP12 - Geraetekalibrierung
        # Geschrieben von Brady BBP12 Konfiguration
        # Werte in Druckpunkten bei \(dpi) dpi (1 mm = \(String(format: "%.3f", dotsPerMM)) Punkte)
        BradyXOffset \(x)
        BradyYOffset \(y)
        """
        if pinQuality {
            text += """

            BradyDensity \(Int(density))
            BradySpeed \(speed)
            BradyDither \(dither)
            BradyMediaType \(media)
            BradyGap \(gapMM)
            BradyRibbon \(ribbon)
            """
        }
        text += "\n"

        let tmp = NSTemporaryDirectory() + "bbp12.conf"
        do { try text.write(toFile: tmp, atomically: true, encoding: .utf8) }
        catch { status = "Konnte nicht schreiben: \(error.localizedDescription)"; return }

        busy = true
        let result = Shell.admin("/bin/mkdir -p /Library/Printers/Brady && "
                                 + "/bin/cp '\(tmp)' '\(Paths.conf)' && "
                                 + "/bin/chmod 644 '\(Paths.conf)'")
        busy = false
        status = result.ok
            ? "Gespeichert: Versatz \(x), \(y) Punkte (\(xoffMM) mm, \(yoffMM) mm)"
            : "Nicht gespeichert - \(result.message)"
    }

    func addSize(width: String, height: String) {
        let w = mm(width), h = mm(height)
        guard w >= 4, h >= 4 else { status = "Breite und Hoehe muessen mindestens 4 mm sein."; return }
        busy = true
        let result = Shell.admin("/usr/bin/python3 '\(Paths.labelTool)' add "
                                 + "\(w) \(h) --queue '\(queue)'")
        busy = false
        status = result.ok ? "Etikettengroesse \(w.clean) x \(h.clean) mm angelegt."
                           : "Nicht angelegt - \(result.message)"
        if result.ok { reload() }
    }

    func removeSelectedSize() {
        guard let id = selectedSize else { return }
        busy = true
        let result = Shell.admin("/usr/bin/python3 '\(Paths.labelTool)' remove \(id) --queue '\(queue)'")
        busy = false
        status = result.ok ? "Etikettengroesse entfernt." : "Nicht entfernt - \(result.message)"
        if result.ok { reload() }
    }

    func makeDefaultSize() {
        guard let id = selectedSize else { return }
        busy = true
        let result = Shell.admin("/usr/bin/python3 '\(Paths.labelTool)' default \(id) --queue '\(queue)'")
        busy = false
        status = result.ok ? "Standardformat gesetzt." : "Nicht gesetzt - \(result.message)"
        if result.ok { reload() }
    }

    func printCalibration() {
        guard let s = size else { status = "Keine Etikettengroesse gewaehlt."; return }
        guard !queue.isEmpty else { status = "Keine Warteschlange gefunden."; return }
        let pdf = NSTemporaryDirectory() + "bbp12-kalibrierung.pdf"
        let gen = Shell.run("/usr/bin/python3", [Paths.calibTool, "\(s.wmm)", "\(s.hmm)", pdf])
        guard gen.code == 0 else { status = "Kalibrier-Etikett fehlgeschlagen: \(gen.err)"; return }
        let job = Shell.run("/usr/bin/lp", ["-d", queue, "-o", "media=\(s.id)", pdf])
        status = job.code == 0
            ? "Kalibrier-Etikett \(s.label) gesendet."
            : "Druck fehlgeschlagen: \(job.err.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func openLog() {
        Shell.run("/usr/bin/open", ["-a", "Console", "/var/log/cups/error_log"])
    }
}

private extension Double {
    var clean: String { self == rounded() ? String(Int(self)) : String(format: "%g", self) }
}

// MARK: - Oberflaeche

struct ContentView: View {
    @StateObject private var driver = Driver()
    @State private var newWidth = ""
    @State private var newHeight = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView {
                calibration.tabItem { Text("Kalibrierung") }
                labels.tabItem { Text("Etikettengroessen") }
                quality.tabItem { Text("Druckqualitaet") }
            }
            .padding(12)
            Divider()
            footer
        }
        .frame(width: 560, height: 470)
        .onAppear { driver.reload() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "printer.fill").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Brady BBP12").font(.headline)
                Text("SeeBubble Media FlexCo").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if driver.queues.isEmpty {
                Text("keine Warteschlange").foregroundStyle(.red).font(.caption)
            } else {
                Picker("", selection: $driver.queue) {
                    ForEach(driver.queues, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 190)
            }
            Text("\(driver.dpi) dpi").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var calibration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Der Druckkopf ist breiter als das Etikett. Wo das Material darin liegt, "
                 + "ist bei jedem Geraet etwas anders - dieser Versatz gleicht das aus.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("nach rechts").frame(width: 110, alignment: .trailing)
                    TextField("", text: $driver.xoffMM).frame(width: 70)
                    Text("mm").foregroundStyle(.secondary)
                    Text(dots(driver.xoffMM)).font(.caption).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("nach unten").frame(width: 110, alignment: .trailing)
                    TextField("", text: $driver.yoffMM).frame(width: 70)
                    Text("mm").foregroundStyle(.secondary)
                    Text(dots(driver.yoffMM)).font(.caption).foregroundStyle(.secondary)
                }
            }

            Text("Vorgehen: Kalibrier-Etikett drucken. Der Rahmen liegt genau auf der Kante. "
                 + "Fehlt links etwas, den Wert um die fehlenden Millimeter erhoehen.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Kalibrier-Etikett drucken") { driver.printCalibration() }
                Spacer()
                Button("Kalibrierung sichern") { driver.saveConfig() }
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Diese Formate stehen im Druckdialog unter Papierformat zur Auswahl. "
                 + "Die Auswahl hier gilt auch fuer den Testdruck auf der Kalibrierseite.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $driver.selectedSize) {
                ForEach(driver.sizes) { size in
                    HStack {
                        Text(size.label)
                        if size.isDefault {
                            Text("Standard").font(.caption2).padding(.horizontal, 5)
                                .padding(.vertical, 1).background(Color.accentColor.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Text(size.id).font(.caption).foregroundStyle(.secondary)
                    }.tag(size.id)
                }
            }
            .frame(minHeight: 180)

            HStack(spacing: 8) {
                TextField("Breite", text: $newWidth).frame(width: 66)
                Text("x").foregroundStyle(.secondary)
                TextField("Hoehe", text: $newHeight).frame(width: 66)
                Text("mm").foregroundStyle(.secondary)
                Button("Hinzufuegen") {
                    driver.addSize(width: newWidth, height: newHeight)
                    newWidth = ""; newHeight = ""
                }
                Spacer()
                Button("Als Standard") { driver.makeDefaultSize() }
                    .disabled(driver.selectedSize == nil || driver.size?.isDefault == true)
                Button("Entfernen") { driver.removeSelectedSize() }
                    .disabled(driver.selectedSize == nil || driver.sizes.count <= 1)
            }
        }
    }

    private var quality: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow {
                    Text("Schwaerzung").frame(width: 110, alignment: .trailing)
                    Slider(value: $driver.density, in: 0...15, step: 1).frame(width: 200)
                    Text("\(Int(driver.density))").monospacedDigit().frame(width: 24)
                }
                GridRow {
                    Text("Geschwindigkeit").frame(width: 110, alignment: .trailing)
                    Picker("", selection: $driver.speed) {
                        ForEach(2...5, id: \.self) { Text("\($0) Zoll/s").tag($0) }
                    }.labelsHidden().frame(width: 200)
                }
                GridRow {
                    Text("Halbton").frame(width: 110, alignment: .trailing)
                    Picker("", selection: $driver.dither) {
                        Text("Scharf (Text, Barcode)").tag("Threshold")
                        Text("Fehlerdiffusion (Fotos)").tag("Diffusion")
                    }.labelsHidden().frame(width: 200)
                }
                GridRow {
                    Text("Material").frame(width: 110, alignment: .trailing)
                    Picker("", selection: $driver.media) {
                        Text("Stanzetiketten").tag("Gap")
                        Text("Endlosmaterial").tag("Continuous")
                        Text("Schwarzmarke").tag("BlackMark")
                    }.labelsHidden().frame(width: 200)
                }
                GridRow {
                    Text("Luecke").frame(width: 110, alignment: .trailing)
                    HStack { TextField("", text: $driver.gapMM).frame(width: 60); Text("mm") }
                }
                GridRow {
                    Text("Verfahren").frame(width: 110, alignment: .trailing)
                    Picker("", selection: $driver.ribbon) {
                        Text("Thermotransfer (Farbband)").tag("On")
                        Text("Direktthermo").tag("Off")
                    }.labelsHidden().frame(width: 200)
                }
            }

            Toggle("Diese Werte als Geraetestandard festschreiben", isOn: $driver.pinQuality)
            Text(driver.pinQuality
                 ? "Die Werte gelten dann fuer alle Auftraege und haben Vorrang vor dem Druckdialog."
                 : "Ohne Haken bleiben diese Einstellungen im Druckdialog aenderbar.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Sichern") { driver.saveConfig() }.keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if driver.busy { ProgressView().controlSize(.small) }
            Text(driver.status).font(.caption).lineLimit(2)
                .foregroundStyle(driver.status.contains("Nicht") || driver.status.contains("fehl")
                                 ? Color.red : Color.secondary)
            Spacer()
            Button("Protokoll") { driver.openLog() }.controlSize(.small)
            Button("Aktualisieren") { driver.reload() }.controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func dots(_ text: String) -> String {
        let v = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
        return "= \(Int((v * driver.dotsPerMM).rounded())) Punkte"
    }
}

@main
struct BradyBBP12ConfigApp: App {
    var body: some Scene {
        Window("Brady BBP12 Konfiguration", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
