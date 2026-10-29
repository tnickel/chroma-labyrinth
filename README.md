# Chroma-Labyrinth

Prozedurales 3D-Labyrinth für Godot 4.7.2 mit Forward+. Vier animierte Menschenmodelle und ihre Texturen werden mit dem Projekt mitgeliefert. In Godot `project.godot` öffnen, den ersten Import abwarten und das Projekt mit F5 starten.

![Nocturne mit echten Wand- und Bodenreflexionen](doc/showcase/nocturne.png)

## Starten

1. Repository klonen oder als ZIP herunterladen und entpacken. Die Modelle sind enthalten; Git LFS ist nicht nötig.
2. [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) installieren. Die Demo wurde mit dieser Version und dem Vulkan-Renderer Forward+ geprüft.
3. `project.godot` im Editor öffnen und F5 drücken. Der erste Import erzeugt den lokalen `.godot`-Cache.

Unter Windows übernimmt `start.bat` Import und Start. Der Starter sucht der Reihe
nach nach `GODOT_EXE`, einer optionalen `start.local.bat`, einer Godot-EXE neben
dem Starter und `godot.exe`/`godot4.exe` im `PATH`. Eine lokale Konfiguration sieht so aus:

```bat
@echo off
set "GODOT_EXE=C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
```

Diese zwei Zeilen als `start.local.bat` speichern; die Datei bleibt über
`.gitignore` privat. Unter Linux/macOS direkt im Godot-Editor starten oder
`godot --path .` ausführen. Die Engine selbst und generierte Caches sind nicht
Bestandteil des Repositorys. Quellen und Lizenzangaben der mitgelieferten Modelle
stehen in [assets/people/ASSET-LICENSES.md](assets/people/ASSET-LICENSES.md).

Der Grundriss hat **50 % mehr Fläche** als die ursprüngliche Demo: rund
**80,83 × 80,83 m** statt 66 × 66 m, entsprechend **6.534 m²** statt 4.356 m²
Grundfläche. Länge und Breite wachsen dafür jeweils um den Faktor √1,5.
Die Hallen sind jetzt etwa 22,05 × 22,05 m groß. Drei Etagen, sechs Meter
Geschossabstand, Figurengröße und Laufgeschwindigkeit bleiben erhalten.

## Steuerung

- **W/A/S/D:** laufen; **Umschalt:** sprinten; **Leertaste:** springen
- **Maus:** umsehen; **F:** Taschenlampe an/aus
- **Esc:** Maus freigeben; **Linksklick:** Maus wieder einfangen
- **F3:** Bildratenanzeige ein-/ausblenden
- **Tab:** Welt-Auswahl öffnen/schließen; dort **1–8** oder eine Karte anklicken
- **H:** HUD und Minimap für eine freie Ansicht ein-/ausblenden
- **F11:** Vollbild ein-/ausschalten
- **Im Flugzeug:** **E** Fensterplatz/Aufstehen; **R** Rundflug starten; **L** vorzeitige Rückkehr ab der Wolkenreise; **M** Fluggeräusch stummschalten

Die Welt-Auswahl setzt den Spieler mit einer kurzen Überblendung an einen
geprüften Aussichtspunkt im echten Labyrinth. Von dort ist jeder Bereich frei
begehbar. Beim normalen Erkunden kündigen zurückhaltende Titel die Räume an.

Die Minimap unten links ist nordfest; der Pfeil zeigt die Blickrichtung. Auf Rampen wechselt sie am Mittelpunkt zwischen den Etagen. Die Rampen liegen an den beiden äußeren Rändern bei Z ≈ −36,74 und Z ≈ +36,74; ihr unterer Zugang befindet sich jeweils beim westlichen Rand. Ihre horizontale Länge beträgt jetzt 22,05 m bei sechs Metern Höhenunterschied (etwa 15,23° Steigung).

Die Bodenpfeile zeigen tatsächlich begehbare Routen: **Cyan führt aufwärts,
Amber abwärts**. An Abzweigungen stehen Ziel-Etage und verbleibende Weglänge;
die Entfernung folgt dem Labyrinthweg, nicht der Luftlinie. Direkt an den Rampen
stehen zusätzliche Etagen-Schilder. Im mittleren Stockwerk sind Auf- und Abstieg
getrennt markiert.

## Airport / Chroma Orbit

Im Erdgeschoss führt die neue **Ostachse vom Atrium** zu einem ausgeschilderten
Flughafenportal. Der Glasgang, die Wartehalle, die Fluggastbrücke und die Maschine
sind tatsächlich begehbar. Alternativ führt **Tab → AIRPORT** direkt ins Terminal.
Die Abflugtafel und Bodenmarkierungen weisen zu **Gate A01**; zurück geht es
über die Schilder **CHROMA / GALERIEN**. Die ursprüngliche Labyrinthfläche bleibt
erhalten; Terminal und Vorfeld liegen als zusätzlicher Anbau daneben.

Durch die Panoramafenster sind Landebahn, Hangars und drei Flugzeuge mit
Start-, Lande- und Rollbewegungen zu sehen. Die eigene Maschine besitzt
36 Sitze, 18 nutzbare Fensterplätze, einen Mittelgang, Gepäckfächer, Flügel,
Triebwerke und eine schließbare Einstiegstür. Die Fenster sind echte Öffnungen
mit transparentem Glas, keine Bilder an einer geschlossenen Wand.

1. Über Gate A01 und die Glasbrücke in die Maschine gehen.
2. Mit **E** neben einer Sitzreihe einen Fensterplatz einnehmen.
3. **R** drücken oder nach **Esc** den Button **RUNDFLUG STARTEN** anklicken.
   Der Start ist nur an Bord möglich und setzt den Spieler nötigenfalls an
   einen Fensterplatz. Der Mausblick bleibt frei.
4. Der rund **150 Sekunden** lange Flug führt automatisch über Rollen, Start,
   Wolken, Orbitalpanorama und Landung zurück zum Gate. **E** erlaubt auch
   währenddessen das Aufstehen und Gehen in der geschlossenen Kabine.
5. Nach dem Andocken öffnet die Tür. Mit **E** aufstehen und denselben Weg durch
   Brücke und Terminal zurück ins Labyrinth gehen. Weitere Flüge sind möglich.

Das ist ein inszenierter Passagier-Erlebnisflug: Ein gewöhnliches Verkehrsflugzeug
fliegt nicht ins All. Die Kabine behält stabile Physikkoordinaten; bewegte
Landschaft, gestaffelte Wolken, Himmel und gekrümmter Planet erzeugen das
Panorama. Der Planet ist prozedural und keine geografisch genaue Erdkarte.
Leises Triebwerksrauschen und ein Kabinensignal entstehen ebenfalls im Code.
Während des Fluges bleibt die Weltenauswahl gesperrt, bis das ursprüngliche
Gate samt Kamera, Umgebung, Licht und Steuerung wiederhergestellt ist.

Das vollständige Konzept steht in [doc/Flugterminal-Konzept.txt](doc/Flugterminal-Konzept.txt).
Module: `scripts/airport/`; Außenwelt- und Terminal-Shader: `shaders/airport_*.gdshader`.
`Tests/AirportRegression.gd` prüft den realen Hin-/Rückweg mit der Player-Kapsel,
E/R/L/Tab-Eingaben, alle Flugphasen, zwei Flüge und die vollständige Rückkehr.
Der Abschlusslauf bestand 3.923 Prüfungen mit 1.344 Wegproben. Zusätzlich sind
Flugstart während eines Weltwechsels und die Sitzsperre beim Menüschließen
abgedeckt. Die Weltenauswahl bestand weitere 3.276 Prüfungen mit acht Zielen.
`tools/airport_review.gd` erzeugt echte Forward+-Aufnahmen; `tools/airport_benchmark.gd`
misst die laufende Hauptszene mit normalem HUD, Besuchern und Flugverkehr.

Forward+-Aufnahmen aus der tatsächlichen Hauptszene:

![Terminal mit Gate und Blick auf das Vorfeld](doc/airport/airport_terminal.png)
![Begehbare Kabine mit Fensterplätzen](doc/airport/airport_cabin.png)
![Orbitalpanorama vom Fensterplatz](doc/airport/airport_space.png)

Leistungsstichprobe vom 29.10.2026, RTX 4070, Godot 4.7.2, 1920×1080,
ohne VSync und ohne parallele Lasttests. Je Ansicht 2,5 Sekunden Aufwärmzeit
und drei Sekunden Messung, normale Besucher-/Verkehrslogik und HUD aktiv:

| Ansicht mit Flughafen-Erweiterung | Median pro Bild | 95. Perzentil | FPS aus dem Median |
| --- | ---: | ---: | ---: |
| Atrium | 9,10 ms | 13,53 ms | 110 |
| Terminal mit Flugverkehr | 3,64 ms | 4,58 ms | 275 |
| Kabine am Gate | 3,48 ms | 3,94 ms | 287 |
| Start, Blick aus dem Fenster | 1,58 ms | 1,68 ms | 632 |
| Wolkenreise, Blick aus dem Fenster | 1,52 ms | 1,73 ms | 657 |
| Orbitalpanorama, Blick aus dem Fenster | 1,52 ms | 1,84 ms | 657 |

Die Flugansicht rendert nur die Kabine und ihre eigene vereinfachte Außenwelt;
das erklärt die deutlich geringere Last als im Museum. Die Wolken sind
prozedurale Schichten und weich schattierte Sprites, keine volumetrische
Wettersimulation. Diese kurzen Stichproben einzelner Ansichten sind keine
Mindest-FPS-Zusage oder isolierte Messung des zusätzlichen Flughafenaufwands.
Unbearbeitete Bilder und Messdaten liegen in `doc/airport/`, vom Asset-Import
durch `.gdignore` ausgeschlossen.

## Die sechs Galerien

Die Architektur und alle neuen Materialien entstehen im Code. Dafür werden
keine externen Texturen oder Architekturmodelle geladen. Die vorhandenen
Besuchermodelle bleiben mitgelieferte GLB-Dateien.

| Etage | Nordwestliche Halle | Südöstliche Halle |
| --- | --- | --- |
| 01 / OBSIDIAN | **SOLAR:** warme Sonnensegel, gerillter Kalkstein, Travertin und Messing | **NOCTURNE:** Sternenraum, Obsidian, kosmisches Wandfenster, echter Wandspiegel und 12 × 12 m perspektivischer Spiegelboden |
| 02 / GLACIER | **GLACIER:** spektral leuchtender Kristall, rotierende Strahlenfächer, Kaustik-Lichtkranz, Wasser-Lichtboden und schwebendes Eis | **SPECTRUM:** raumspannende prismatische Bänder, Terrazzo und kinetisches Möbiusband |
| 03 / EMBER | **EMBER:** Basaltgewölbe, langsam glühende Magmaadern und Kupfer | **AFTERGLOW:** fließende Aurorabänder, projizierter Lichtgarten und blaugrüner Stein |

Das Atrium verbindet die Etagen mit Glasbrüstungen, Stahlstützen, einem Glasdach
und dem **Engine of Light**: drei zwölf Meter hohe, GPU-animierte Metallsegel
um einen leuchtenden Kern. Eine reflektierende Bodenrosette greift seine Form auf.
Zwölf beschriftete Raumportale markieren die wichtigsten tatsächlichen Zugänge;
weitere Öffnungen behalten dezente Bodenschwellen. Die Rampen haben Glasgeländer und einen
verglasten äußeren Abschluss. In den Gängen hängen gerahmte, langsam animierte
Konturzeichnungen. Fugen, Metallprofile, eingelassene Bodenlinien und eigene
Leuchten geben der Architektur erkennbare Maßstäbe.

Die Beleuchtung setzt Raumakzente statt eines identischen Lampenrasters in jeder
Halle. Acht lokale Nebelvolumen unterstützen gerichtete Lichtschächte; der globale
Nebel bleibt schwach. AgX-Tonemapping erhält helle Lichtflächen, ohne die gesamte
Szene weiß aufzuhellen. Die Materialfamilien unterscheiden sich in Maserung,
Rauheit, Reflexion und Relief, nicht nur in ihrer Farbe.

### Glacier: Prismenresonanz

Über **Tab → GLACIER** lässt sich die Installation direkt besuchen. Die fünf
Kristalle tragen polierte Facetten mit wandernden Lichtadern und gegeneinander
versetzten Spektralfarben. Ein Farbkreis dauert rund 18 Sekunden; die Farben
gehen kontinuierlich ineinander über. Langsam rotierende Strahlenfächer,
ein mehrfarbiger Bodenlichtkranz und 96 schwebende Lichtpartikel ergänzen den Kern.
Drei synchronisierte Echtzeitlichter beleuchten den Sockel, Boden und Besucher.
Die Bodenmuster und Strahlen sind künstlerische Shader-Effekte, keine physikalisch
berechneten Lichtbrechungs-Kaustiken.

Die 60 ursprünglichen Kanten-Meshes wurden zu fünf zusammengefasst. Kristalle,
Sockel und Effekt benötigen zusammen 14 Mesh-Surfaces; die Partikel bewegen sich
gebündelt auf der GPU. Zusätzliche Lichter und Atmosphäre blenden zwischen 18 und
24 Metern aus und schalten auf anderen Etagen ab. Im inaktiven Zustand prüft das
Modul nur zehnmal pro Sekunde die Kamera und überträgt keine Animationsparameter.
Die echten Kristall-Meshes bleiben für Sichtbarkeit und Reflexionen bestehen.
Die vorhandenen statischen Cubemaps werden weiterhin einmal aufgenommen;
laufende Farbänderungen erscheinen dort nicht zeitlich korrekt. SSR und direkte
Beleuchtung bleiben dynamisch.

`Tests/GlacierRadianceRegression.gd` prüft Integration, Farbphase, Etagen,
Distanzblende und Geometrie-/Lichtgrenzen. Für reproduzierbare Bilder bzw. eine
Messung des zusätzlichen lokalen Licht-/Atmosphäreaufwands bei aktivem HUD,
Minimap und Besuchern:

```text
godot --path . --resolution 1920x1080 --script res://tools/glacier_review.gd
godot --path . --resolution 1920x1080 --script res://tools/glacier_review.gd -- --benchmark
```

Die Bilder und Messdaten werden im Godot-`user://`-Verzeichnis gespeichert.
Der Bildvergleich benötigt einen echten Forward+-Viewport, keinen Headless-Lauf.

Die Erweiterung wurde auf der RTX 4070 bei 1920×1080 mit normalen Besuchern,
HUD und Minimap geprüft: zwei aktive Stichproben ergaben **6,49 und 6,79 ms
Median pro Bild** (rund 154 bzw. 147 FPS). Die Vergleichsläufe ohne zusätzliche
Lichter/Atmosphäre lagen bei 6,62 und 6,84 ms; die Unterschiede liegen innerhalb
der Streuung dieses kurzen Tests und belegen keinen belastbaren Zeitgewinn.
Rohdaten: `doc/showcase/glacier-radiance-benchmark-1920x1080.json`.
Alle vier relevanten Regressionstests bestanden, darunter 140 gezielte
Glacier-Prüfungen. Zwei tatsächlich gerenderte Farbphasen:

![Glacier mit warmen Spektralfarben](doc/showcase/glacier.png)
![Glacier mit blauvioletten Spektralfarben](doc/showcase/glacier-spectral-blue.png)

## Aufbau

- `Main.tscn`, `Main.gd`: Zusammensetzen der Komponenten und Forward+-Umgebung.
- `Player.tscn`, `Player.gd`: Spielfigur, Eingaben, Taschenlampe und Minimap.
- `scripts/LabyrinthGenerator.gd`: Geometrie, Kollision, Materialien, Räume, Rampen und Beleuchtung.
- `scripts/LabyrinthLayout.gd`: zentraler Flächenfaktor und Umrechnung zwischen ursprünglichem Entwurfsraster und tatsächlichen Metern. Kollisionskörper werden direkt in den passenden Größen gebaut; die Welt hängt nicht an einem verzerrten Physik-Elternknoten.
- `scripts/GalleryEnvironment.gd`: Tonemapping, indirektes Licht, Nebel und Bildschirm-Effekte.
- `scripts/SurfaceLibrary.gd`, `shaders/architectural_surface.gdshader`, `shaders/gallery_glass.gdshader`: gemeinsam genutzte Stein-, Metall-, Keramik- und Glasmaterialien.
- `scripts/GalleryArchitecture.gd`: Glasdach, Wandpaneele, gerichtete Haupt-/Gegenlichter, Wandbeleuchtung und Reflexionsproben.
- `scripts/ChromaAtrium.gd`, `shaders/chroma_*.gdshader`: kinetisches Atrium mit konservativen Culling-Grenzen für die Shader-Animation.
- `scripts/GlacierRadiance.gd`, `shaders/glacier_*.gdshader`: lokale spektrale Kristallinstallation mit GPU-Partikeln und abgestimmten Echtzeitlichtern.
- `scripts/ExperienceWorlds.gd`, `shaders/experience_*.gdshader`: sechs eigenständige Rauminstallationen und animierte Oberflächen, ohne neue Physikhindernisse.
- `scripts/ExperienceResponse.gd`: dezente lokale Lichtreaktion der Wasser-/Auroraböden auf die Spielerposition, höchstens zehn Parameteraktualisierungen je Sekunde und Material.
- `scripts/GalleryThresholds.gd`: zwölf Portale aus den tatsächlichen Hallen-/Gangverbindungen.
- `scripts/ShowcaseDirector.gd`: Welt-Auswahl, sichere Einstiegspunkte, Vollbild und Raumtitel.
- `scripts/ExhibitSculptures.gd`, `shaders/wall_art.gdshader`: sieben unterschiedliche Exponate und generative Wandbilder.
- `scripts/PlanarGalleryMirror.gd`, `shaders/planar_mirror.gdshader`: perspektivisch berechneter Wandspiegel in Nocturne.
- `scripts/NocturneReflectingFloor.gd`: begrenzter horizontaler Spiegelboden mit derselben Projektionsberechnung, eigener Reichweite und Ausschluss der oberen Etagen.
- `scripts/RampWayfinding.gd`: Wegweiser aus dem tatsächlichen Navigationsgraphen.
- `scripts/GalleryHUD.gd`: Etagen-/Raumanzeige und optionale Bildrate.
- `scripts/VisitorCrowd.gd`, `scripts/LabyrinthVisitor.gd`: 24 Besucher mit reservierten Betrachtungsplätzen, geglätteten Wegen, Bewegung und Animation. Die Anzahl lässt sich über `visitor_count` einstellen.
- `scripts/VisitorItinerary.gd`: persönliche Rundgänge zu Galerien und Atrium; Exponate werden 5–12 Sekunden betrachtet, Ziele bleiben bei einer Neuplanung erhalten.
- `scripts/VisitorTraffic.gd`: Abstandhalten, Ausweichen, Rücksicht auf den Spieler und geregelter Gegenverkehr an Rampen.
- `scripts/VisitorFootIK.gd`: Bodenabfragen, Fuß- und Beinanpassung, begrenzte Beckenabsenkung und Kontaktprüfung anhand der Schuhsohlen.
- `scripts/VisitorTurnMotion.gd`: abwechselnde Drehschritte mit angehobenem Schwungfuß und festem Standfuß.
- `scripts/VisitorAttention.gd`: sanfte, begrenzte Kopfbewegung zum betrachteten Exponat.
- `assets/people/`: vier animierte GLB-Modelle und ihre Texturen; Herkunft und Lizenz stehen in `ASSET-LICENSES.md`.

Architektur liegt auf Render-Layer 1, Decken und Deckeninstallationen auf Layer 2.
Bewegte Besucher verwenden Layer 3 (Bitmaske 4), die echte Spiegelfläche Layer 4
(Bitmaske 8). Die Hauptkamera sieht alle vier Layer (Maske 15), die Minimap nur
Architektur und Besucher (Maske 5). Dadurch bleiben die Decken ausgeblendet und
statische Reflexionsproben enthalten keine eingefrorenen Besucher.
Die Welt besteht aus drei Ebenen im Abstand von sechs Metern; ihre Grundrisse
werden mit einem festen Zufalls-Seed erzeugt. SDFGI, volumetrischer Nebel, Glow,
SSR, SSAO und SSIL benötigen eine für Forward+ geeignete Grafikkarte.

## Besucher und Rechenaufwand

`VisitorCrowd.gd` prüft viermal pro Sekunde die räumliche Entfernung zum Spieler.
Nahe Besucher werden mit voller Bildrate animiert; nur dort laufen Fuß-IK,
Bodenabfragen, Drehschritte und zusätzliche Kopfbewegungen. Pro nahem Besucher
werden zwei Bodenstrahlen je Physikschritt abgefragt. Die kleinen Kontaktbereiche
der Schuhsohlen werden einmal beim Laden erfasst und anschließend für die
Bodenkorrektur verwendet. Ab der mittleren Distanz
werden die Posen nur noch zwölfmal pro Sekunde ausgewertet; die Bewegung und
Kollision bleiben dort flüssig. Weit entfernte Besucher werden ausgeblendet;
Animation, Bewegung, Wegsuche und Kollision werden pausiert. Position, Pose und
Weg bleiben gespeichert. Es gibt beim Aufwecken keinen nachgeholten Zeitsprung.

Die Schwellwerte sind im Crowd-Skript einstellbar: `full_animation_distance`
(20 m), `visibility_distance` (42 m), `distance_hysteresis` (3 m) und
`distant_animation_fps` (12). Mit diesen Werten erfolgt der Wechsel zur
reduzierten Animation beim Entfernen über 23 m, zurück zur vollen Rate unter
17 m. Schlaf beginnt über 45 m, das Aufwecken unter 39 m. Der Abstand wird
dreidimensional gemessen; andere Etagen werden nicht pauschal abgeschaltet,
da sie durch das Atrium sichtbar sein können. Die Minimap verwendet dieselben
Figuren; deshalb entscheidet kein kameraabhängiger Sichtbarkeits-Notifier über
die Simulation. Entfernte pausierte Besucher wandern während der Pause nicht
weiter. Die importierten Mesh-LODs bleiben zusätzlich aktiv.

Zusätzlich teilen gleich große Architekturteile ihre Mesh-Ressourcen.
Lichtwirkungen werden in der Entfernung ausgeblendet. Die Minimap wird mit
20 Bildern pro Sekunde und einer eigenen Umgebung ohne Nebel/SSR/Glow gerendert.
Physikinterpolation glättet die Bewegung der Besucher zwischen Physikschritten;
die Maussteuerung bleibt unmittelbar. 2x MSAA und TAA glätten Kanten und
feine Materialdetails. Wiederholte Wandprofile werden in räumlich begrenzten
MultiMeshes zusammengefasst; sämtliche Richtungspfeile benötigen zusammen zwei
MultiMeshes. Materialien teilen eine gemeinsame prozedurale Stein-Noise-Textur.

Sieben ReflectionProbes erfassen die Räume einmalig. SSR ergänzt sichtbare,
bewegte Reflexionen. Die übrigen polierten Wandpaneele verwenden diese lokalen
Reflexionsproben; sie sind keine perspektivisch exakten Planspiegel. Der einzelne
echte Wandspiegel in Nocturne rendert dagegen aus dem gespiegelten Augenpunkt mit
korrekt versetztem Frustum. Sein zusätzliches Bild ist 941×512 Pixel groß und
wird höchstens 24-mal pro Sekunde aktualisiert, nur auf der sichtbaren Vorderseite
innerhalb von rund 22 Metern. Nachweislich durch eine massive Wand vollständig
verdeckte Spiegel werden nicht aktualisiert; Glas oder eine teilweise Verdeckung
stoppen den Capture nicht. Am Rand der Reichweite blendet die Oberfläche in
probe-beleuchtetes Metall über, statt ein eingefrorenes Live-Bild zu zeigen.
Es enthält keine rekursiven Spiegel und keinen zweiten
SSR-/Nebel-/GI-Nachbearbeitungsdurchlauf.
Ein zusätzlicher, 12 × 12 m großer Spiegeleinsatz im Nocturne-Boden reflektiert
Sternendecke, Skulptur und Besucher mit korrekter Perspektive. Sein Capture ist
640 × 640 Pixel groß, auf 20 Hz und 16 m Entfernung begrenzt. Von den oberen
Hallen verhindern die tatsächlich geschlossenen Deckenflächen unnötige Captures
beider Spiegel. Sichtstrahlen außerhalb dieser Deckenfläche bleiben zulässig.
Beide Planspiegel schließen
Spiegelflächen aus ihren Captures aus, damit keine rekursiven Renderketten entstehen.
Die einmaligen Cubemaps bleiben statische Annäherungen. Bewegte Raumkunst wird
über SSR und den echten Planspiegel dynamisch reflektiert, soweit sie dort sichtbar
ist. Die Wassereffekte und Magmaadern sind gestaltete Shader-Installationen;
sie simulieren keine physikalische Flüssigkeit. Die Glasbrechung verwendet den
opaken Bildhintergrund und kann keine verdeckten oder transparenten Hintergründe rekonstruieren.
Eine allgemeine FPS-Garantie lässt sich daraus nicht ableiten.

## Verhalten und Grenzen

Normale Kurven werden ohne vollständigen Halt durchlaufen. Die geglätteten
Wegsegmente werden mit der Kollisionskapsel auf freie Durchgänge geprüft.
An engen Rampen und vor Kehrtwenden bewegen sich die Besucher vorsichtiger.
Auf der tatsächlichen Steigung bleiben Seitenschritte gesperrt. Auf den breiten,
flachen Rampenpodesten dürfen wartende Besucher dagegen kollisionsgeprüft Platz
machen, damit sie den Gegenverkehr nicht am Ausgang festhalten.
Das Animationstempo folgt der tatsächlichen Gehgeschwindigkeit einschließlich
der Steigung auf Rampen. Exponate
werden im Stand angesehen. Betrachtungsplätze werden reserviert, damit nicht
alle Besucher denselben Zielpunkt belegen. Die Reservierung erfolgt erst in
der Nähe des Exponats; bei voller Belegung geht der Besucher nach einer kurzen
Wartezeit zum nächsten Exponat. Dadurch blockieren lange Anreisen keine Plätze.

Die Figuren verwenden vorhandene Geh- und Standanimationen, ergänzt durch
prozedurale Drehschritte, Kopfbewegungen und Fuß-IK. Beim Drehen im Stand setzen
sie die Füße abwechselnd um. Auf Rampen passen sich Beine, Schuhneigung und
Becken an die Bodenhöhe an; gesetzte Füße werden während der Kontaktphase in
Weltkoordinaten gehalten. Eine zusätzliche Prüfung der verformten Schuhsohle
korrigiert Einsinken, das allein anhand der Fußknochen nicht erkennbar wäre.
Die Anpassung berücksichtigt die unabhängigen Fußwurzelknochen aller vier Modelle.

Die Ergänzungen sind prozedural, keine neu aufgenommenen Motion-Capture-Clips.
Die isolierten Fußtests prüfen ebenen Boden und ±18,4° Steigung, einschließlich
Querstellung. Die verlängerten Projektrampen sind mit etwa ±15,23° flacher und
werden zusätzlich mit echten Besucher-Traversierungen geprüft. Die begrenzte IK ist keine allgemeine
Lösung für Sprünge, hohe Treppenstufen oder beliebig unebenes Gelände.

Reproduzierbare Prüfungen stehen unter `Tests/`: Besucher-Rundgänge,
Abstandssteuerung, Rampen und Gegenverkehr. Beispielsweise:
`godot --headless --path . --fixed-fps 60 --script Tests/VisitorTourRegression.gd`.
Dieser Test simuliert fünf Minuten mit 24 aktiven Besuchern und prüft
Zielankünfte, Betrachtungspausen, Blickrichtung, Stürze und lange Stillstände.

Zusätzliche Tests prüfen Beinlängen und Knöchelkontakt (`VisitorFootIKRegression.gd`),
die tatsächlich verformten Schuhsohlen (`VisitorSoleRegression.gd`), feste
Fußkontakte (`VisitorPlantRegression.gd`), Drehschritte (`VisitorTurnMotionRegression.gd`)
und Kopfbewegungen (`VisitorAttentionRegression.gd`). Beim geprüften Stand
bestanden 2.400 Sohlen-Snapshots aller vier Modelle ohne gemessene Bodenpenetration;
der größte Abstand des unteren Sohlenpunkts betrug 1,35 cm. Die Renderprobe
`tools/visitor_pose_probe.gd` prüft zusätzlich das Zusammenspiel und das Abschalten
der zusätzlichen Berechnungen in mittlerer und großer Entfernung.

## Grafik- und Wegeprüfung

- `Tests/WayfindingRegression.gd`: 439 Routen gegen unabhängig berechnete kürzeste Wege, Pfeilrichtungen, Wandfreiheit und Rampen-Bodenkontakt.
- `Tests/ExpandedLayoutRegression.gd`: tatsächliche Mesh-Grundfläche, Gebäudeabmessungen, Rampenprofil, Bodenunterstützung aller Graphpunkte sowie unveränderte Spielergröße und Geschwindigkeit.
- `Tests/ShowcaseRegression.gd`: echte Welt-Sprünge, Kapsel-/Bodenprüfungen, Minimap, vollständige Rotationshülle der Atriumsegel sowie Spiegel-Verdeckung/Fallback.
- `Tests/ExperienceWorldsRegression.gd`: Geometriehöhen, geglättete Normalen, Wandunterstützung und Render-Layer aller sechs Installationen. Ein Lauf mit dem echten Renderer vergleicht zusätzlich alle 1.336 MultiMesh-Transforms mit ihren gebauten Werten; der Headless-Dummy behält diese GPU-Daten nicht.
- `Tests/GalleryArchitectureRegression.gd`: tatsächliche Render-Layer, Minimap-Clipping, gültige Geometrie und Kollisionsfreiheit entlang der Navigationskanten.
- `Tests/PlanarMirrorRegression.gd`: Off-Axis-Projektion, reflektierte Sichtstrahlen, Clipping und begrenzte Aktualisierung.
- `Tests/VisitorRampLandingRegression.gd`: vier gezielt erzwungene Konflikte zwischen Warteschlange und Rampenausfahrt, einschließlich Verbot von Seitenschritten auf der Steigung.
- `tools/gallery_review_probe.gd`: echte Forward+-Bilder vom Startpunkt, Atrium und allen sechs Hallen unter `user://gallery_*.png`.
- `tools/showcase_review.gd`: aktuelle Welt-Auswahl, acht Forward+-Raumansichten und Menü; mit `-- 0 3` lassen sich einzelne Bereiche prüfen.
- `tools/showcase_benchmark.gd`: alle acht Welten mit normalem HUD, Minimap und Besucher-LOD; je 2,5 Sekunden Aufwärmphase und drei Sekunden Messung. JSON-Ergebnisse unter `user://showcase_benchmark_<Breite>x<Höhe>.json`.
- `tools/planar_mirror_probe.gd`: seitliche Spiegelansichten mit einem unabhängigen Farb-/Projektionsvergleich.
- `tools/gallery_benchmark.gd`: vier Ansichten bei Projektauflösung, ohne VSync, mit Aufwärmphase, Median und 95. Perzentil der tatsächlich gerenderten Bildintervalle. Währenddessen keine anderen Lasttests starten.

Messung der vollständigen Erlebniswelten vom 29.10.2026 **vor der Glacier-
Prismenresonanz-Erweiterung**, auf der vorhandenen
RTX 4070, Godot 4.7.2, **1920×1080**, ohne VSync und ohne parallele Testprozesse.
Die normale Besucher-LOD, HUD und Minimap blieben aktiv. Pro Ansicht wurden
nach 2,5 Sekunden Aufwärmen drei Sekunden gemessen. Ergebnisse sind Stichproben
dieser Ansichten, keine Mindest-FPS-Zusage:

| Ansicht | Median pro Bild | 95. Perzentil | FPS aus dem Median |
| --- | ---: | ---: | ---: |
| Atrium | 6,02 ms | 8,00 ms | 166 |
| Solar | 6,14 ms | 8,64 ms | 163 |
| Nocturne mit Wand- und Bodenspiegel | 4,72 ms | 7,27 ms | 212 |
| Glacier | 5,84 ms | 7,20 ms | 171 |
| Spectrum | 6,10 ms | 8,00 ms | 164 |
| Ember | 4,97 ms | 6,17 ms | 201 |
| Afterglow | 5,71 ms | 8,03 ms | 175 |

Die Capture-Zähler bestätigen in der Nocturne-Messung **72 Wand- und 60
Bodenspiegelbilder in drei Sekunden**. In den anderen sechs Messansichten
blieben beide Zähler bei null. Das schließt insbesondere die Räume über
Nocturne ein: Deren geschlossene Geschossdecke verhindert unnötiges Spiegelrendern.
Rohdaten stehen in `doc/showcase/benchmark-1920x1080.json`; echte, unbearbeitete
1080p-Renderaufnahmen aller Welten und der Auswahl ebenfalls in `doc/showcase/`.
Dieser Ordner ist über `.gdignore` vom Asset-Import ausgeschlossen.

Der Abschlusscheck bestand 3.266 Showcase-Prüfungen einschließlich echter
Tasteneingaben und sieben sicheren Weltwechseln. Die Installationsprüfung mit
aktivem Vulkan-Renderer bestand 179.940 Prüfungen einschließlich des Readbacks
aller 1.336 gebauten Instanztransformationen. Die unabhängige Architekturprüfung
bestand 10.636 Kapselpositionen entlang des Wegenetzes; alle 439 geprüften
Rampenrouten und die vier tatsächlichen Rampendurchläufe blieben fehlerfrei.

Der letzte Rundgangstest der Besucherlogik im vergrößerten Grundriss mit 24 Besuchern über fünf Simulationsminuten
bestand mit 91 Zielankünften, 89 geprüften Betrachtungspausen und keinem
Rückwärtslaufen. Der längste ungeplante Stillstand außerhalb einer Rampenwarteschlange
betrug 6,33 Sekunden. Die zusätzliche Rampen-Landungsprüfung bestand alle vier
erzwungenen Konfliktfälle.

Bekannte Einschränkung der installierten Godot-Version: Beim Beenden nach einem
ReflectionProbe-Capture erscheint eine Warnung über sieben Texture-RIDs.
`tools/reflection_shutdown_probe.gd` reproduziert sie bereits in einer isolierten
Szene mit einer einzigen ReflectionProbe, auch nach expliziter Freigabe und
Render-Synchronisation. Ohne ReflectionProbe tritt sie dort nicht auf. Die Warnung
wird nicht unterdrückt; sie ist von Skriptfehlern und fehlgeschlagenen Tests zu unterscheiden.
