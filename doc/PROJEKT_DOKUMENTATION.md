# Chroma — Spaces in Motion: Projektdokumentation

## 1. Projektübersicht & Entstehungsgeschichte

**Chroma — Spaces in Motion** (Projektordner `GDotLabyrith2`) ist ein 3D-Showcase-Projekt für die **Godot Engine 4** (Forward+ Renderer / Vulkan), das die Leistungsfähigkeit moderner KI-gestützter Spieleentwicklung demonstriert.

### Kern-Fakten:
* **Entwicklungszeit:** Innerhalb von nur **3 bis 4 Stunden** von Grund auf entwickelt.
* **Entwickler-Hintergrund:** Erstellt von Thomas Nickel ohne tiefere Vorkenntnisse in 3D-Grafikprogrammierung, Shadern oder Vektormathematik.
* **Entwicklungsmethode:** Vollständig dialogbasiert mit der **Astra-KI** (GPT-4 Astra / Codex). Die KI erzeugte den GDScript-Code, Shader-Dateien, Szenenstrukturen und automatische Regressionstests.
* **Showcase-Zweck:** Das Projekt beweist, wie schnell und zugänglich High-End-3D-Entwicklung in Godot 4 durch iterative KI-Führung wird.

---

## 2. Die Video-Showcases auf YouTube

Zur Veranschaulichung und Präsentation des Projekts existieren zwei begleitende YouTube-Videos:

### Video 1: Aufbau des Chroma-Museums (Labyrinth, Beleuchtung & Kunstgalerien)
* **URL:** [https://youtu.be/B02GJjcgpKk](https://youtu.be/B02GJjcgpKk)
* **Schwerpunkte:**
  - Aufbau des 3-stöckigen Gebäudes mit über 6.500 m² Grundfläche (80,83 × 80,83 m).
  - Implementierung von SDFGI (Signed Distance Field Global Illumination), Screen-Space Reflections (SSR) und volumetrischem Nebel.
  - Großes Atrium mit der kinetischen Metallskulptur *"Chroma — Engine of Light"*.
  - Vorstellung der Galeriewelten (Solar, Nocturne, Glacier, Spectrum, Ember, Afterglow).
  - Animierte Passanten und begehbare Verbindungsrampen mit zweifarbigem Wegeleitsystem.

### Video 2: Flughafen-Anbau, Orbit Liner & KI-Entwicklungs-Workflow
* **URL:** [https://youtu.be/k2gzdX22JTw](https://youtu.be/k2gzdX22JTw)
* **Schwerpunkte:**
  - Warum One-Shot-Prompts bei komplexen Projekten nicht genügen und wie iteratives Prompting mit kontinuierlicher Verfeinerung zum Erfolg führt.
  - Der neue Anbau: Begehbarer Flugterminal mit Wartehalle, Abflugtafel, Rollfeld und autonomen Flugzeugen.
  - Fluggastbrücke Gate A01 und Betreten des *Chroma Orbit Liners* (36 Sitze, 18 reale Fensterplätze).
  - 150-Sekunden-Rundflug in Echtzeit: Start, Wolkenschichten, Steigflug bis in den Orbit mit Erdkrümmung und Sternenhimmel, Landeanflug und Rückkehr ins Terminal.

---

## 3. Architektur & Spielwelt

### 3.1 Multi-Etagen-Labyrinth & Kunstgalerien
- **Fläche & Maßstab:** Grundfläche von ca. 80,83 × 80,83 m (~6.534 m²) über 3 Stockwerke mit jeweils 6 m Deckenhöhe.
- **Rampen- und Wegeleitsystem:** Die Etagen sind über großzügige 22-Meter-Rampen verbunden. Ein dynamisches, pfadbasiertes Wegweisungssystem auf dem Boden führt die Besucher:
  - **Cyan-Pfeile:** Führen nach oben.
  - **Amber-Pfeile:** Führen nach unten.
  - Meterangaben an Abzweigungen berechnen die tatsächliche Labyrinth-Distanz (keine bloße Luftlinie).
- **Zentrales Atrium:** Großes, offenes Atrium mit der kinetischen Metallskulptur *"Chroma — Engine of Light"*, Reflexionsböden und Glasbrüstungen.

### 3.2 Die Galeriewelten
1. **01 Atrium (Chroma):** 12 Meter kinetisches Metall, ständige dynamische Lichtbrechung.
2. **02 Solar:** Warmer Mineralsaal, goldene Sonnensegel, gefiltertes Sonnenlicht.
3. **03 Nocturne:** Obsidianboden, kosmische Tiefen, Sternenhimmel und Planarspiegel.
4. **04 Glacier:** Schwebende Eis- und Prismenkristalle mit spektraler Lichtbrechung und Kaustik-Shadern.
5. **05 Spectrum:** Prismatische Farbbänder an Decke und Boden, kinetische Torus-Skulptur.
6. **06 Ember:** Dunkles Gestein, Wabenstrukturen, Kupferakzente und glühendes Bodennetz.
7. **07 Afterglow:** Sanfte Polarlichter (Aurora Borealis), schwebende DNA-Doppelhelix-Skulptur.

---

## 4. Der Flugterminal-Anbau: Chroma Orbit

Im Erdgeschoss führt eine beschilderte Ostachse vom Atrium durch einen realen Durchbruch in der Außenwand zum **Flugterminal**:

### 4.1 Terminal & Fluggastbrücke
- **Wartehalle:** Verglaste Lounge mit Anzeigetafeln, Sitzgruppen, Blick auf das Rollfeld und autonomen Flugverkehr (startende, landende und rollende Maschinen).
- **Gate A01 & Jetbridge:** Ein stufenlos verbundener Glasgang führt direkt zur Passagiermaschine ("Chroma Orbit Liner").

### 4.2 Die Passagiermaschine & der Orbit-Rundflug
- **Kabine:** 36 Sitze, 18 reale Fensterplätze mit Blick nach außen, Gepäckablagen, Mittelgang und physisch schließbare Einstiegstür.
- **Flugablauf (~150 Sekunden):**
  1. *Boarding & Tür schließen:* Einstiegstür schließt automatisch.
  2. *Rollen & Start:* Beschleunigung auf der Startbahn und Abheben mit Triebwerkssound.
  3. *Wolkenreise:* Fünf gestaffelte Wolkenschichten mit GPU-Batching.
  4. *Orbitalpanorama:* Aufstieg bis in den Weltraum mit sichtbarer Erdkrümmung, Sternenhintergrund und Erdoberfläche.
  5. *Sinkflug & Landung:* Wiedereintritt, Landeanflug und sanftes Aufsetzen.
  6. *Andocken am Gate:* Tür öffnet wieder, Spieler kann aufstehen und ins Labyrinth zurückkehren.
- **Physikalisches Konzept:** Die Kabinenkollision bleibt ortsfest, um Floating-Point-Präzisionsfehler und komplexe Mitbewegungs-Physik zu vermeiden. Der Flug wird durch eine rotierende und sich bewegende Außenszenerie, adaptive Himmelsshader und Lichtstimmungen inszeniert.

---

## 5. Steuerung & Tastenbelegung

| Taste / Eingabe | Funktion |
| :--- | :--- |
| **W / A / S / D** | Gehen / Fortbewegen |
| **Umschalt (Shift)** | Sprinten |
| **Leertaste (Space)** | Springen |
| **Maus** | Freier Kameraschwenk (Mouse Look) |
| **F** | Taschenlampe an / aus |
| **Tab** | Welten-Schnellauswahl öffnen / schließen (Teleport zu Galerien & Airport) |
| **Esc** | Mauszeiger freigeben / Menüs bedienen |
| **Linksklick** | Mauszeiger wieder im Spielfenster fangen |
| **H** | HUD und Minimap ein- / ausblenden |
| **F3** | FPS- und Performance-Anzeige |
| **F11** | Vollbild umschalten |
| **E (im Flugzeug)** | Am Fensterplatz hinsetzen / im Mittelgang aufstehen |
| **R (im Flugzeug)** | Orbit-Rundflug starten |
| **L (im Flug)** | Vorzeitige Rückkehr einleiten (ab Wolkenreise) |
| **M (im Flug)** | Triebwerks-Sound stummschalten |

---

## 6. Technische Highlights & Render-Pipeline

- **Engine-Version:** Godot 4.3+ / 4.7.2 Forward+ (Vulkan Rendering Backend).
- **Echtzeitbeleuchtung:**
  - SDFGI (Signed Distance Field Global Illumination) für realistische indirekte Lichtausbreitung.
  - Screen-Space Reflections (SSR) & Planare Reflexions-Sonden für spiegelnde Böden und Fenster.
  - Volumetrischer Nebel, Glow/Bloom, SSAO und SSIL.
- **Prozedurale Erzeugung:** Wände, Galerien, Texturen und Skulpturen werden ohne schwere externe 3D-Assets über NoiseTextures, CSG-/ArrayMeshes und GDShaders generiert.
- **Shader-Architektur:**
  - `shaders/airport_flight_sky.gdshader`: Tag-, Dämmerungs- und Weltraumhimmel.
  - `shaders/airport_flight_clouds.gdshader`: Mehrschichtige Wolkeneffekte.
  - `shaders/airport_flight_ground.gdshader`: Landschaft und Erdkrümmung.
  - `shaders/glacier_radiance.gdshader`: Spektrale Lichtstreuung und Kaustiken.
- **Automatisierte Qualitätssicherung:**
  - `Tests/AirportRegression.gd`: Validiert Geometrie, Wegfindung, Hin-/Rückweg, Sitzmechanik und Flugphasen.
  - `Tests/GalleryArchitectureRegression.gd` & `ShowcaseRegression.gd`: Prüfen alle Galerien und Übergänge.
  - `tools/*_benchmark.gd`: Integrierte Performance- und Framezeit-Messungen bei 1080p.
