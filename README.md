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

**Nastavenia**
- Metrické alebo imperiálne jednotky, typ mapy
- Predvolená rýchlosť simulácie, opakovanie, tam a späť
- Filter presnosti GPS a minimálna vzdialenosť medzi bodmi pri nahrávaní

## Spustenie

Potrebuješ Mac s Xcode 15 alebo novším.

```bash
brew install xcodegen
xcodegen generate
open TrasaGPS.xcodeproj
```

V Xcode vyber v *Signing & Capabilities* svoj tím (Team) a spusti aplikáciu na iPhone alebo v simulátore.

Bez XcodeGen: v Xcode vytvor nový projekt *iOS App* (SwiftUI, SwiftData), nahraď jeho súbory obsahom priečinka `TrasaGPS/` a v Build Settings nastav `INFOPLIST_FILE = TrasaGPS/Resources/Info.plist`.

## Poznámka

Aplikácia nemení systémovú polohu iPhonu pre iné aplikácie, to iOS bežnej aplikácii nedovolí. Na simuláciu polohy celého zariadenia počas vývoja použi export pre Xcode.
