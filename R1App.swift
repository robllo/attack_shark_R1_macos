// R1 Config: SwiftUI front end for R1Protocol.swift. Build with ./build.sh
import SwiftUI
import IOKit.hid

let green = Color(red: 0.24, green: 0.86, blue: 0.52)
let orange = Color(red: 1.0, green: 0.55, blue: 0.26)
let backgroundColor = Color(red: 0.06, green: 0.08, blue: 0.07)
let cardColor = Color(red: 0.10, green: 0.12, blue: 0.11)

// (label, protocol action) for the button pickers; "custom" shows a text field for any key combo.
let actionChoices: [(String, String)] = [
    ("Clique do meio", "middle-click"), ("Voltar (botão 4)", "back"), ("Avançar (botão 5)", "forward"),
    ("Voltar no Safari/Finder (⌘[)", "cmd+["), ("Avançar no Safari/Finder (⌘])", "cmd+]"),
    ("Mission Control (⌃↑)", "ctrl+up"), ("Janelas do app (⌃↓)", "ctrl+down"), ("Mostrar mesa (F11)", "f11"),
    ("Captura de área (⇧⌘4)", "cmd+shift+4"), ("Copiar (⌘C)", "cmd+c"), ("Colar (⌘V)", "cmd+v"),
    ("Clique duplo", "double-click"), ("Trocar DPI", "dpi-cycle"), ("DPI +", "dpi+"), ("DPI −", "dpi-"),
    ("Play/Pause", "play-pause"), ("Próxima faixa", "next-track"), ("Faixa anterior", "prev-track"),
    ("Mudo", "mute"), ("Volume +", "vol+"), ("Volume −", "vol-"), ("Desativado", "disable"),
    ("Atalho personalizado…", "custom"),
]

@main
struct R1ConfigApp: App {
    var body: some Scene {
        WindowGroup("R1 Config") {
            ContentView().preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
    }
}

// Transient UI state; @State is a macro that needs full Xcode, so this builds with the command-line tools alone.
final class Model: ObservableObject {
    @Published var battery = "—"
    @Published var connected = false
    @Published var status = "Mexa o mouse antes de aplicar: parado, ele dorme e não recebe a configuração."
    @Published var statusIsError = false
    @Published var busy = false
}

let bluetoothMessage = "O mouse está no Bluetooth, que não aceita configuração. Mude a chave para 2.4G (ou ligue o cabo), aplique, e volte ao Bluetooth: as configurações continuam valendo."
let notFoundMessage = "Mouse não encontrado. Use o dongle 2.4G ou o cabo: pelo Bluetooth o R1 não aceita configuração, mas o que você aplicar por aqui continua valendo no Bluetooth."

// All HID work runs on one serial queue so writes never interleave and the UI never blocks.
let hidQueue = DispatchQueue(label: "r1.hid")

struct ContentView: View {
    // The mouse can't be read back, so the last applied settings are remembered here.
    @AppStorage("dpis") private var dpisText = "400,800,1800,3200,6400,12000"
    @AppStorage("activeStage") private var activeStage = 3
    @AppStorage("angleSnap") private var angleSnap = false
    @AppStorage("ripple") private var ripple = false
    @AppStorage("polling") private var polling = 1000
    @AppStorage("btn.middle") private var middle = "middle-click"
    @AppStorage("btn.back") private var back = "back"
    @AppStorage("btn.forward") private var forward = "forward"
    @AppStorage("btn.dpi") private var dpiButton = "dpi-cycle"
    @AppStorage("btn.middle.custom") private var middleCustom = false
    @AppStorage("btn.back.custom") private var backCustom = false
    @AppStorage("btn.forward.custom") private var forwardCustom = false
    @AppStorage("btn.dpi.custom") private var dpiCustom = false

    @StateObject private var model = Model()

    private var dpis: [Int] {
        get { dpisText.split(separator: ",").compactMap { Int($0) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    dpiCard
                    pollingCard
                    buttonsCard
                }
                .padding(18)
            }
            // Pinned footer so the result of every apply stays visible however the window is scrolled.
            HStack(spacing: 8) {
                Image(systemName: model.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(model.statusIsError ? orange : green)
                    .accessibilityHidden(true)
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(model.statusIsError ? orange : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(cardColor)
        }
        .frame(width: 520, height: 820)
        .background(backgroundColor)
        .tint(green)
        .onAppear(perform: refreshBattery)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle().fill(model.connected ? green : orange).frame(width: 10, height: 10)
                .accessibilityLabel(model.connected ? "Conectado" : "Não encontrado")
            VStack(alignment: .leading, spacing: 2) {
                Text("Attack Shark R1").font(.title2.bold())
                Text(model.connected ? "Conectado" : "Sem conexão para configurar").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(model.battery, systemImage: "battery.75percent")
                .font(.headline.monospacedDigit())
                .foregroundStyle(green)
            Button(action: refreshBattery) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Ler bateria de novo")
                .accessibilityLabel("Atualizar bateria")
        }
        .padding(16)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 14))
    }

    private var dpiCard: some View {
        Section("DPI") {
            ForEach(0..<6, id: \.self) { i in
                HStack(spacing: 10) {
                    Button { activeStage = i + 1 } label: {
                        Image(systemName: activeStage == i + 1 ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(activeStage == i + 1 ? orange : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Usar estágio \(i + 1)")
                    Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 12)
                    Slider(value: dpiBinding(i), in: 100...18000, step: 100)
                        .accessibilityLabel("DPI do estágio \(i + 1)")
                    Stepper(value: dpiBinding(i), in: 100...18000, step: 100) {
                        Text("\(dpis[safe: i] ?? 800)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(activeStage == i + 1 ? orange : .primary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            HStack {
                Toggle("Angle snap", isOn: $angleSnap)
                Toggle("Ripple control", isOn: $ripple)
                Spacer()
                applyButton("Aplicar DPI", action: applyDPI)
            }
            .padding(.top, 4)
        }
    }

    private var pollingCard: some View {
        Section("Taxa de polling") {
            HStack {
                Picker("Taxa", selection: $polling) {
                    ForEach([125, 250, 500, 1000], id: \.self) { Text("\($0) Hz").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                applyButton("Aplicar", action: applyPolling)
            }
        }
    }

    private var buttonsCard: some View {
        Section("Botões") {
            ActionRow(title: "Meio (clique da roda)", action: $middle, custom: $middleCustom)
            ActionRow(title: "Lateral de trás", action: $back, custom: $backCustom)
            ActionRow(title: "Lateral da frente", action: $forward, custom: $forwardCustom)
            ActionRow(title: "Botão de DPI", action: $dpiButton, custom: $dpiCustom,
                      choices: actionChoices.filter { dpiButtonActions.contains($0.1) })
            HStack {
                Button("Restaurar padrão") {
                    middle = "middle-click"; back = "back"; forward = "forward"; dpiButton = "dpi-cycle"
                    middleCustom = false; backCustom = false; forwardCustom = false; dpiCustom = false
                }
                .buttonStyle(.borderless)
                .foregroundStyle(orange)
                Spacer()
                applyButton("Aplicar botões  ⌘↩", action: applyButtons)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.top, 4)
        }
    }

    private func applyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
            .disabled(model.busy)
    }

    private func dpiBinding(_ i: Int) -> Binding<Double> {
        Binding(
            get: { Double(dpis[safe: i] ?? 800) },
            set: { value in
                var d = dpis
                while d.count < 6 { d.append(800) }
                d[i] = Int(value)
                dpisText = d.map(String.init).joined(separator: ",")
            }
        )
    }

    // MARK: - Actions

    private func refreshBattery() {
        hidQueue.async {
            let result = Result { () -> String in
                let (device, wired) = try openMouse()
                guard let b = try readBattery(device, wired: wired) else { return "cabo" }
                return "\(b.percent)%\(b.charging ? " ⚡︎" : "")"
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let text): model.battery = text; model.connected = true
                case .failure(let error):
                    model.connected = false
                    model.battery = "—"
                    show(friendly(error), error: true)
                }
            }
        }
    }

    private func applyDPI() {
        guard let report = dpiReport(dpis, active: activeStage, angleSnap: angleSnap, ripple: ripple) else {
            return show("DPI inválido: use valores entre 100 e 18000.", error: true)
        }
        write(report, done: "DPI aplicado: estágio \(activeStage) = \(dpis[activeStage - 1]).")
    }

    private func applyPolling() {
        write(pollingReport(polling)!, done: "Polling aplicado: \(polling) Hz.")
    }

    private func applyButtons() {
        if !dpiButtonActions.contains(dpiButton) { dpiButton = "dpi-cycle"; dpiCustom = false } // older saves allowed any action
        var assignments: [String: (UInt8, UInt8, UInt8)] = [:]
        for (button, value) in [("middle", middle), ("back", back), ("forward", forward), ("dpi", dpiButton)] {
            guard let action = parseAction(value.lowercased()) else {
                return show("Atalho inválido: \"\(value)\". Use algo como cmd+shift+4 ou ctrl+up.", error: true)
            }
            assignments[button] = action
        }
        middleCustom = false; backCustom = false; forwardCustom = false; dpiCustom = false
        write(buttonReport(assignments), done: "Botões aplicados.")
    }

    private func write(_ report: [UInt8], done: String) {
        model.busy = true
        hidQueue.async {
            let result = Result { try send(openMouse().0, report) }
            DispatchQueue.main.async {
                model.busy = false
                switch result {
                case .success: show(done, error: false); model.connected = true
                case .failure(let error):
                    show(friendly(error), error: true)
                }
            }
        }
    }

    private func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("Bluetooth mode") { model.connected = false; return bluetoothMessage }
        if text.contains("not found") { model.connected = false; return notFoundMessage }
        return text
    }

    private func show(_ message: String, error: Bool) {
        model.status = message
        model.statusIsError = error
    }
}

struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(green).tracking(1.2)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ActionRow: View {
    let title: String
    @Binding var action: String
    // True only while the shortcut field is open; a confirmed custom shortcut lives in `action` like a preset.
    @Binding var custom: Bool
    var choices = actionChoices
    @FocusState private var focused: Bool

    private var isListed: Bool { choices.contains { $0.1 == action } && action != "custom" }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: Binding(
                get: { custom ? "custom" : action },
                set: { choice in
                    custom = choice == "custom"
                    if custom && isListed { action = "" } // keep a confirmed custom shortcut so it can be edited
                    if !custom { action = choice }
                }
            )) {
                if !isListed && !custom && !action.isEmpty {
                    Text("Atalho: \(prettyShortcut(action))").tag(action)
                }
                ForEach(choices, id: \.1) { Text($0.0).tag($0.1) }
            }
            .labelsHidden()
            .frame(width: 230)
        }
        if custom {
            HStack {
                Spacer()
                TextField("ex.: \\ ou cmd+shift+4", text: $action)
                    .focused($focused)
                    .onSubmit(confirm)
                    .onChange(of: focused) { _, isFocused in if !isFocused { confirm() } }
                    .onAppear { focused = true }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 230)
                    .foregroundStyle(parseAction(action.lowercased()) == nil ? orange : .primary)
                    .accessibilityLabel("Atalho personalizado para \(title)")
            }
        }
    }

    // Enter or clicking away closes the field, like picking from the list; an invalid combo keeps it open in orange.
    private func confirm() {
        if parseAction(action.lowercased()) != nil { custom = false }
    }
}

// "cmd+shift+4" -> "⇧⌘4", the way macOS menus show shortcuts.
func prettyShortcut(_ s: String) -> String {
    let symbols = ["ctrl": "⌃", "opt": "⌥", "alt": "⌥", "shift": "⇧", "cmd": "⌘", "win": "⌘"]
    var parts = s.lowercased().split(separator: "+").map(String.init)
    let key = parts.popLast() ?? ""
    let order = ["ctrl", "opt", "alt", "shift", "cmd", "win"]
    let mods = order.filter(parts.contains).compactMap { symbols[$0] }.joined()
    return mods + (key.count == 1 ? key.uppercased() : key.capitalized)
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
