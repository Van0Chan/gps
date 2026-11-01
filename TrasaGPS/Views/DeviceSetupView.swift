import SwiftUI
import UniformTypeIdentifiers

/// Nastavenie simulácie polohy celého iPhonu.
struct DeviceSetupView: View {
    @Environment(DeviceLocationController.self) private var device
    @AppStorage(DeviceLocationController.ipKey) private var ipSetting = DeviceLocationController.automaticIP
    @AppStorage(DeviceLocationController.followKey) private var follow = true

    @State private var showImporter = false
    @State private var importError: String?
    @State private var customIP = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Stav") {
                statusRow
                if device.isConnected {
                    if let c = device.spoofedCoordinate {
                        LabeledContent("Simulovaná poloha", value: Fmt.coordinate(c))
                        Button("Obnoviť skutočnú polohu") {
                            Task { await device.restoreRealLocation() }
                        }
                    } else {
                        Text("iPhone používa skutočnú polohu. Na mape ťukni na „Presunúť iPhone sem“ alebo spusti simuláciu trasy.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let ip = device.activeIP {
                        LabeledContent("Adresa", value: ip)
                    }
                    Button("Odpojiť a vrátiť skutočnú polohu", role: .destructive) {
                        Task { await device.disconnect() }
                    }
                } else {
                    Button {
                        Task { await device.connect() }
                    } label: {
                        Label("Pripojiť", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(!device.hasPairingFile || device.isWorking)
                }
            }

            Section {
                Toggle("Posielať simuláciu trasy do iPhonu", isOn: $follow)
            } footer: {
                Text("Keď prehrávaš trasu, poloha celého iPhonu sa pohybuje spolu s ňou.")
            }

            Section {
                if device.hasPairingFile {
                    Label("Pairing file je importovaný", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Button("Nahradiť pairing file") { showImporter = true }
                    Button("Vymazať pairing file", role: .destructive) { confirmDelete = true }
                } else {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Importovať pairing file", systemImage: "doc.badge.plus")
                    }
                }
            } header: {
                Text("Pairing file")
            } footer: {
                Text("Pairing file dáva plný prístup k tvojmu iPhonu. Nikomu ho neposielaj. Aplikácia ho ukladá iba lokálne v iPhone.")
            }

            Section("Pripojenie") {
                Picker("Adresa zariadenia", selection: $ipSetting) {
                    Text("Automaticky").tag(DeviceLocationController.automaticIP)
                    Text("10.7.0.2").tag("10.7.0.2")
                    Text("10.7.0.1").tag("10.7.0.1")
                    if ![DeviceLocationController.automaticIP, "10.7.0.2", "10.7.0.1"].contains(ipSetting) {
                        Text(ipSetting).tag(ipSetting)
                    }
                }
                HStack {
                    TextField("Vlastná IP adresa", text: $customIP)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                    Button("Použiť") {
                        let ip = customIP.trimmingCharacters(in: .whitespaces)
                        if !ip.isEmpty { ipSetting = ip }
                    }
                    .disabled(customIP.isEmpty)
                }
                LabeledContent("Developer Disk Image", value: DDIStore.isDownloaded ? "Stiahnutý" : "Stiahne sa pri pripojení")
                if DDIStore.isDownloaded {
                    Button("Zmazať stiahnutý DDI (~16 MB)") { DDIStore.delete() }
                }
            }

            Section("Návod") {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Zapni **Režim pre vývojárov**: Nastavenia ▸ Súkromie a bezpečnosť ▸ Režim pre vývojárov (iPhone sa reštartuje).")
                    step(2, "Z App Store nainštaluj **LocalDevVPN** a zapni v nej VPN. Tá umožní aplikácii pripojiť sa k vývojárskym službám vlastného iPhonu.")
                    step(3, "Na počítači vytvor **pairing file** pre svoj iPhone (napr. nástrojom iloader, JitterbugPair alebo `idevice pair`) a pošli si ho do iPhonu (AirDrop, Súbory, e-mail).")
                    step(4, "Tu ťukni na **Importovať pairing file** a vyber ho.")
                    step(5, "Ťukni na **Pripojiť**. Pri prvom pripojení po reštarte sa stiahne a pripojí Developer Disk Image (~16 MB).")
                    step(6, "Na mape posuň zameriavač a ťukni na **Presunúť iPhone sem**, alebo spusti simuláciu trasy.")
                }
                .font(.footnote)
            }

            Section {
                Text("Simulovaná poloha platí, kým je aplikácia spojená s iPhonom (aj na pozadí). Po odpojení, ukončení aplikácie alebo reštarte sa vráti skutočná poloha. Funkcia používa vývojárske služby iOS a Apple ju môže v budúcich verziách iOS zmeniť.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Poloha celého iPhonu")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.propertyList, .xml, .data, .item]) { result in
            switch result {
            case .success(let url):
                do { try device.importPairingFile(from: url) }
                catch { importError = error.localizedDescription }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Import zlyhal", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .confirmationDialog("Vymazať pairing file?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Vymazať", role: .destructive) { device.deletePairingFile() }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch device.status {
        case .idle:
            Label("Nepripojené", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .working(let text):
            HStack {
                ProgressView()
                Text(text)
            }
        case .connected:
            Label("Pripojené – poloha iPhonu sa dá meniť", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Chyba", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .bold()
                .frame(width: 18, alignment: .leading)
            Text(text)
        }
    }
}
