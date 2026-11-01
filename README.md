# TrasaGPS

iOS aplikácia (SwiftUI, iOS 17+) na živé GPS, nahrávanie a plánovanie trás, štatistiky a simuláciu pohybu po trase.

## Funkcie

**Mapa**
- Živá poloha: súradnice (s kopírovaním), rýchlosť, nadmorská výška, presnosť a smer
- Štandardná, hybridná a satelitná mapa, 3D, kompas a mierka
- Nahrávanie trasy so štartom, pauzou a stopom, aj na pozadí. Zobrazuje čas, vzdialenosť a počet bodov a po skončení ponúkne uloženie trasy.

**Plánovač**
- Body trasy pridávaš ťukaním na mapu
- Režimy: priamo, po cestách (auto) alebo pešo (trasovanie cez Apple Mapy)
- Hľadanie miesta alebo adresy a jeho pridanie ako bodu
- Späť, obrátenie smeru, uzavretie okruhu, vymazanie
- Dĺžka trasy a odhad času pri zvolenej rýchlosti
- Uloženie trasy alebo okamžitá simulácia

**Simulácia trasy**
- Značka sa pohybuje po trase so smerovou šípkou
- Rýchlosti: chôdza, beh, bicykel, auto, diaľnica, alebo vlastná 1 až 200 km/h
- Spustenie a pauza, posúvanie po trase, návrat na začiatok, opakovanie a režim tam a späť
- Kamera sleduje simulovanú polohu, zobrazuje sa prejdená vzdialenosť a zostávajúci čas

**Trasy**
- Zoznam s vyhľadávaním a filtrom (nahraté, naplánované, importované) a mazaním
- Detail trasy: mapa so štartom a cieľom, premenovanie a štatistiky (dĺžka, trvanie, priemerná a maximálna rýchlosť, stúpanie a klesanie, minimálna a maximálna výška, počet bodov)
- Graf výškového profilu
- Vytvorenie spiatočnej trasy
- Import GPX (track, route aj waypointy). GPX súbor sa dá otvoriť aj priamo z aplikácie Súbory.
- Export GPX a **export pre Xcode**: časy bodov sú prepočítané podľa rýchlosti, takže súbor sa dá použiť v Debug ▸ Simulate Location

**Poloha celého iPhonu**
- Mení GPS polohu pre **všetky aplikácie**, nielen v TrasaGPS
- Presun na ľubovoľné miesto: posunieš zameriavač na mape a ťukneš na „Presunúť iPhone sem“
- Pri prehrávaní trasy sa poloha celého iPhonu pohybuje spolu so simuláciou
- Funguje bez počítača cez vývojárske služby iOS (knižnica [idevice](https://github.com/jkcoxson/idevice), MIT licencia)
- Potrebuješ: zapnutý Režim pre vývojárov, aplikáciu **LocalDevVPN** z App Store a **pairing file** vytvorený raz na počítači
- Pri prvom pripojení po reštarte sa stiahne a pripojí Developer Disk Image (~16 MB)
- Podrobný návod je priamo v aplikácii: Nastavenia ▸ Poloha celého iPhonu

**Nastavenia**
- Metrické alebo imperiálne jednotky, typ mapy
- Predvolená rýchlosť simulácie, opakovanie, tam a späť
- Filter presnosti GPS a minimálna vzdialenosť medzi bodmi pri nahrávaní

## Inštalácia (.ipa)

Hotový `.ipa` súbor nájdeš v sekcii **Releases** (https://github.com/Van0Chan/gps/releases). Nový release sa vytvorí automaticky pri každom pushi do vetvy `main`.

Nainštaluješ ho cez **Sideloadly**, **AltStore/SideStore** alebo **TrollStore**. Samotné ťuknutie na .ipa v iPhone nefunguje. Po inštalácii cez Sideloadly treba v *Nastavenia ▸ Všeobecné ▸ VPN a správa zariadenia* dôverovať svojmu Apple ID a zapnúť *Režim pre vývojárov*. Aplikácia vyžaduje iOS 17 alebo novší.

## Spustenie zo zdrojákov

Potrebuješ Mac s Xcode 15 alebo novším.

```bash
brew install xcodegen
./scripts/build-idevice.sh   # zostaví knižnicu idevice (Rust) pre iOS
xcodegen generate
open TrasaGPS.xcodeproj
```

V Xcode vyber v *Signing & Capabilities* svoj tím (Team) a spusti aplikáciu na iPhone alebo v simulátore.

Bez XcodeGen: v Xcode vytvor nový projekt *iOS App* (SwiftUI, SwiftData), nahraď jeho súbory obsahom priečinka `TrasaGPS/` a v Build Settings nastav `INFOPLIST_FILE = TrasaGPS/Resources/Info.plist`.

## Poznámka

Zmena polohy celého iPhonu používa vývojárske služby iOS (rovnaké, aké používa Xcode). Platí, kým je aplikácia spojená s iPhonom, a Apple ju môže v budúcich verziách iOS zmeniť. Simulácia polohy v hrách a službách, ktoré to zakazujú, porušuje ich podmienky.
