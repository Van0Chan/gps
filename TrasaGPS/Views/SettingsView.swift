import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.units) private var unitsRaw = UnitSystem.metric.rawValue
    @AppStorage(SettingsKey.mapStyle) private var mapStyleRaw = MapStyleOption.standard.rawValue
    @AppStorage(SettingsKey.simSpeedKmh) private var simSpeedKmh = 5.0
    @AppStorage(SettingsKey.simLoop) private var simLoop = false
    @AppStorage(SettingsKey.simPingPong) private var simPingPong = false
    @AppStorage(SettingsKey.maxAccuracy) private var maxAccuracy = 50.0
    @AppStorage(SettingsKey.minPointDistance) private var minPointDistance = 3.0

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    var body: some View {
        NavigationStack {
            Form {
                Section("Zobrazenie") {
                    Picker("Jednotky", selection: $unitsRaw) {
                        ForEach(UnitSystem.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Typ mapy", selection: $mapStyleRaw) {
                        ForEach(MapStyleOption.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Predvolená rýchlosť: \(Fmt.speed(simSpeedKmh / 3.6, units))")
                        Slider(value: $simSpeedKmh, in: 1...200, step: 1)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(RouteSimulator.Preset.allCases) { preset in
                                Button {
                                    simSpeedKmh = preset.kmh
                                } label: {
                                    Label(preset.title, systemImage: preset.systemImage)
                                }
                                .buttonStyle(.bordered)
                                .tint(simSpeedKmh == preset.kmh ? .accentColor : .gray)
                            }
                        }
                    }
                    Toggle("Opakovať trasu", isOn: $simLoop)
                    Toggle("Tam a späť", isOn: $simPingPong)
                        .disabled(!simLoop)
                } header: {
                    Text("Simulácia")
                } footer: {
                    Text("„Tam a späť“ pri opakovaní otočí smer namiesto skoku na začiatok trasy.")
                }

                Section {
                    Picker("Max. nepresnosť GPS", selection: $maxAccuracy) {
                        Text("±10 m").tag(10.0)
                        Text("±20 m").tag(20.0)
                        Text("±50 m").tag(50.0)
                        Text("±100 m").tag(100.0)
                    }
                    Picker("Min. vzdialenosť bodov", selection: $minPointDistance) {
                        Text("1 m").tag(1.0)
                        Text("3 m").tag(3.0)
                        Text("5 m").tag(5.0)
                        Text("10 m").tag(10.0)
                        Text("25 m").tag(25.0)
                    }
                } header: {
                    Text("Nahrávanie")
                } footer: {
                    Text("Body s horšou presnosťou sa do trasy neukladajú. Nahrávanie pokračuje aj na pozadí.")
                }

                Section("O simulácii polohy") {
                    Text("Simulácia v aplikácii prehráva trasu na mape. Ak chceš podvrhnúť polohu celému iPhonu pri vývoji, exportuj trasu cez „Exportovať pre simuláciu v Xcode“ a v Xcode ju vyber v Debug ▸ Simulate Location. Časy bodov sú prepočítané podľa zvolenej rýchlosti.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Verzia", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Nastavenia")
        }
    }
}
