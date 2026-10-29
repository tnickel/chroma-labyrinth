# Chroma — Spaces in Motion: Projektdokumentation

## 1. Projektübersicht

**Chroma — Spaces in Motion** (Projektordner `GDotLabyrith2`) ist eine interaktive 3D-Echtzeit-Erfahrung in der **Godot Engine 4** (Forward+ Renderer / Vulkan), die vollständig durch dialogbasierte KI-Programmierung (GPT-4 Astra / Codex / Antigravity) entstanden ist.

Das Projekt demonstriert modernes prozedurales Leveldesign, High-End-Echtzeitgrafik in Godot (SDFGI, SSR-Spiegelungen, volumetrischer Nebel, prozedurale Custom-Shader) sowie ein iteratives Entwicklungsmodell: Komplexe Spiel- und Architektur-Elemente werden nicht durch einen einzigen Prompt "aus der Konserve" generiert, sondern Schritt für Schritt interaktiv aufgebaut, getestet und verfeinert.

---

## 2. Architektur & Spielwelt

### 2.1 Multi-Etagen-Labyrinth & Kunstgalerien
- **Fläche & Maßstab:** Grundfläche von ca. 80,83 × 80,83 m (~6.534 m²) über 3 Stockwerke mit jeweils 6 m Deckenhöhe.
- **Rampen- und Wegeleitsystem:** Die Etagen sind über großzügige 22-Meter-Rampen verbunden. Ein dynamisches, pfadbasiertes Wegweisungssystem auf dem Boden führt die Besucher:
  - **Cyan-Pfeile:** Führen nach oben.
  - **Amber-Pfeile:** Führen nach unten.
  - Meterangaben an Abzweigungen berechnen die tatsächliche Labyrinth-Distanz (keine bloße Luftlinie).
- **Zentrales Atrium:** Großes, offenes Atrium mit der kinetischen Metallskulptur *"Chroma — Engine of Light"*, Reflexionsböden und Glasbrüstungen.

### 2.2 Die Galeriewelten
1. **01 Atrium (Chroma):** 12 Meter kinetisches Metall, ständige dynamische Lichtbrechung.
2. **02 Solar:** Warmer Mineralsaal, goldene Sonnensegel, gefiltertes Sonnenlicht.
3. **03 Nocturne:** Obsidianboden, kosmische Tiefen, Sternenhimmel und Planarspiegel.
4. **04 Glacier:** Schwebende Eis- und Prismenkristalle mit spektraler Lichtbrechung und Kaustik-Shadern.
5. **05 Spectrum:** Prismatische Farbbänder an Decke und Boden, kinetische Torus-Skulptur.
6. **06 Ember:** Dunkles Gestein, Wabenstrukturen, Kupferakzente und glühendes Bodennetz.
7. **07 Afterglow:** Sanfte Polarlichter (Aurora Borealis), schwebende DNA-Doppelhelix-Skulptur.

---

## 3. Der Flugterminal-Anbau: Chroma Orbit

Im Erdgeschoss führt eine beschilderte Ostachse vom Atrium durch einen realen Durchbruch in der Außenwand zum **Flugterminal**:

### 3.1 Terminal & Fluggastbrücke
- **Wartehalle:** Verglaste Lounge mit Anzeigetafeln, Sitzgruppen, Blick auf das Rollfeld und autonomen Flugverkehr (startende, landende und rollende Maschinen).
- **Gate A01 & Jetbridge:** Ein stufenlos verbundener Glasgang führt direkt zur Passagiermaschine ("Chroma Orbit Liner").

### 3.2 Die Passagiermaschine & der Orbit-Rundflug
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

## 4. Steuerung & Tastenbelegung

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

## 5. Technische Highlights & Render-Pipeline

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
