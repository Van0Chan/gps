import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Nastavenie simulácie polohy celého iPhonu.
struct DeviceSetupView: View {
    @Environment(DeviceLocationController.self) private var device
    @AppStorage(DeviceLocationController.ipKey) private var ipSetting = DeviceLocationController.automaticIP
    @AppStorage(DeviceLocationController.followKey) private var follow = true
    @AppStorage(DeviceLocationController.rpPortKey) private var rpPort = ""
    @AppStorage(BuiltInVPN.settingKey) private var builtInVPN = true

    @State private var showImporter = false
    @State private var importError: String?
    @State private var importSuccess = false
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
                    if !device.isOnWiFi {
                        Label {
                            Text(device.waitingForWiFi
                                 ? "Čakám na Wi-Fi – spojenie sa obnoví samo."
                                 : "Na pripojenie treba Wi-Fi. Po pripojení ju môžeš vypnúť, spojenie vydrží aj na dátach.")
                        } icon: {
                            Image(systemName: "wifi.exclamationmark")
                        }
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
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
                        .confirmationDialog("Vymazať pairing file?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Vymazať", role: .destructive) { device.deletePairingFile() }
                            Button("Zrušiť", role: .cancel) {}
                        } message: {
                            Text("Na zmenu polohy ho potom budeš musieť importovať znova.")
                        }
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
                Text("Pairing file (.plist alebo .mobiledevicepairing) môžeš importovať aj zo Súborov: podrž prst na súbore ▸ Zdieľať ▸ GeoPilot. Pairing file dáva plný prístup k tvojmu iPhonu. Nikomu ho neposielaj. Aplikácia ho ukladá iba lokálne v iPhone.")
            }

            Section {
                Toggle("Vstavaná VPN", isOn: $builtInVPN)
            } footer: {
                Text(builtInVPN
                     ? "GeoPilot si zapne vlastnú lokálnu VPN – LocalDevVPN netreba. Pri prvom spustení iOS požiada o povolenie VPN konfigurácie. Žiadne dáta neopúšťajú iPhone."
                     : "Používa sa externá aplikácia LocalDevVPN – musí byť zapnutá.")
            }

            Section("Pripojenie") {
                Picker("Adresa zariadenia", selection: $ipSetting) {
                    Text("Automaticky").tag(DeviceLocationController.automaticIP)
                    Text("\(BuiltInVPN.targetAddress) (vstavaná VPN)").tag(BuiltInVPN.targetAddress)
                    Text("10.7.0.1 (LocalDevVPN)").tag("10.7.0.1")
                    Text("10.7.0.2").tag("10.7.0.2")
                    if ![DeviceLocationController.automaticIP, BuiltInVPN.targetAddress, "10.7.0.2", "10.7.0.1"].contains(ipSetting) {
                        Text(ipSetting).tag(ipSetting)
                    }
                }
                HStack {
                    TextField("Vlastná IP adresa", text: $customIP)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                    Button("Použiť") {
                        let ip = customIP.trimmingCharacters(in: .whitespaces)
                        if !ip.isEmpty { ipSetting = ip }
                    }
                    .disabled(customIP.isEmpty)
                }
                HStack {
                    Text("Port RemotePairing")
                    TextField("automaticky", text: $rpPort)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Developer Disk Image", value: DDIStore.anyDownloaded ? "Stiahnutý" : "Stiahne sa pri pripojení")
                if DDIStore.anyDownloaded {
                    Button("Zmazať stiahnutý DDI (~16 MB)") { DDIStore.delete() }
                }
            }

            Section("Návod") {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Zapni **Režim pre vývojárov**: Nastavenia ▸ Súkromie a bezpečnosť ▸ Režim pre vývojárov (iPhone sa reštartuje).")
                    step(2, "VPN zapne GeoPilot sama (prepínač **Vstavaná VPN**). Ak by tvoj certifikát VPN nepovoľoval, vypni prepínač a použi aplikáciu LocalDevVPN z App Store.")
                    step(3, "Získaj **pairing file**: RemotePairing súbor (napr. zo StikDebug, kľúče public_key/private_key) alebo klasický pairing file z počítača (iloader, JitterbugPair). Oba typy fungujú.")
                    step(4, "Tu ťukni na **Importovať pairing file** a vyber ho.")
                    step(5, "Na **Wi-Fi** ťukni na **Pripojiť**. Pri prvom pripojení po reštarte sa stiahne a pripojí Developer Disk Image (~16 MB). Potom môžeš Wi-Fi vypnúť – spojenie vydrží aj na mobilných dátach.")
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
        .scrollDismissesKeyboard(.immediately)
        .sensoryFeedback(.success, trigger: device.isConnected) { _, new in new }
        .sensoryFeedback(.success, trigger: importSuccess) { _, new in new }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(onPick: { url in
                showImporter = false
                let result = Result { try device.importPairingFile(from: url) }
                // Upozornenie zobrazíme až po zatvorení výberu súboru.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    switch result {
                    case .success: importSuccess = true
                    case .failure(let error): importError = error.localizedDescription
                    }
                }
            }, onCancel: {
                showImporter = false
            })
            .ignoresSafeArea()
        }
        .alert("Pairing file importovaný", isPresented: $importSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(builtInVPN ? "Teraz ťukni na Pripojiť." : "Teraz zapni LocalDevVPN a ťukni na Pripojiť.")
        }
        .alert("Import zlyhal", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch device.status {
        case .idle:
            statusHeader("Nepripojené", detail: device.hasPairingFile ? "Pripravené na pripojenie" : "Chýba pairing file",
                         icon: "iphone.slash", color: .gray)
        case .working(let text):
            HStack(spacing: 14) {
                ProgressView()
                    .frame(width: 40, height: 40)
                Text(text)
                    .font(.subheadline)
            }
        case .connected:
            statusHeader("Pripojené", detail: "Poloha iPhonu sa dá meniť", icon: "iphone.gen3.radiowaves.left.and.right", color: .green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                statusHeader("Chyba pripojenia", detail: nil, icon: "exclamationmark.triangle.fill", color: .red)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func statusHeader(_ title: String, detail: String?, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
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

/// Výber súboru cez systémový UIDocumentPicker (funguje spoľahlivo pre ľubovoľný typ súboru).
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.propertyList, .xml, .data, .item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
