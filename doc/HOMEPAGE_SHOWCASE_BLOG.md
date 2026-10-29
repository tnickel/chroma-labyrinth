# Chroma — Spaces in Motion: 3D-GameDev mit Godot 4 & Astra-KI in Rekordzeit

> **Vom Prompt zum begehbaren 3D-Museum mit Raumflug:** Wie mit der Godot Engine 4 (Forward+) und KI-gestützter Entwicklung (GPT-4 Astra / Codex) innerhalb von nur **3 bis 4 Stunden** ein vollständiges, mehrstöckiges 3D-Showcase mit High-End-Grafik, dynamischen Shadern und prozeduraler Architektur entstand – ohne Vorkenntnisse in 3D-Grafikprogrammierung.

---

## Die Video-Showcases auf YouTube

### Teil 1: Das Chroma-Labyrinth entsteht (Architektur, Beleuchtung & 3D-Galerien)
* **Link:** [https://youtu.be/B02GJjcgpKk](https://youtu.be/B02GJjcgpKk)
* **Inhalt:** Aufbau des dreistöckigen Labyrinths (80 × 80 Meter, über 6.500 m² Fläche), physikalische Lichtberechnung mit SDFGI, Screen-Space Reflections (SSR), Bodenleitsystem und die ersten Themenwelten (Solar, Nocturne, Glacier, Ember, Spectrum).
* **Embed-Code für Homepage:**
```html
<div class="video-container">
  <iframe width="560" height="315" src="https://www.youtube.com/embed/B02GJjcgpKk" title="Chroma Godot 4 Showcase Teil 1" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>
</div>
```

---

### Teil 2: Der Flughafen-Anbau & Flug in den Orbit (Iterative KI-Entwicklung)
* **Link:** [https://youtu.be/k2gzdX22JTw](https://youtu.be/k2gzdX22JTw)
* **Inhalt:** Rundgang durch das erweiterte Projekt, Erläuterung des iterativen Workflows (One-Shot vs. schrittweise Verfeinerung), der neue begehbare Flugterminal-Anbau mit Gate A01, Einstieg in den *Chroma Orbit Liner* und der vollständige 150-Sekunden-Rundflug bis ins Orbitalpanorama.
* **Embed-Code für Homepage:**
```html
<div class="video-container">
  <iframe width="560" height="315" src="https://www.youtube.com/embed/k2gzdX22JTw" title="Chroma Godot 4 Showcase Teil 2" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>
</div>
```

---

## Das Konzept: Was macht das Projekt so besonders?

Viele glauben immer noch, dass KI für Game Development entweder nur triviale 2D-Skripte schreiben kann oder man tiefgehende mathematische Kenntnisse in Shadern, Vektorrechnung und 3D-Engines benötigt.

**Chroma — Spaces in Motion** beweist das Gegenteil:
1. **Keine 3D-Grafik-Expertise nötig:** Entwickelt von Thomas Nickel, der selbst über keine Ausbildung in 3D-Grafikprogrammierung verfügt.
2. **Entwicklungszeit von nur 3 bis 4 Stunden:** Das komplette Projekt – inklusive prozeduralem Labyrinth-Generator, Shader-Entwicklung, Sound, UI, Animationen und Regressionstests – stand in einem einzigen Nachmittag.
3. **High-End-Grafik ohne schwere externe Assets:** Keine Gigabyte-großen Asset-Packs. Wände, Böden, Spiegel, Kristalle, Wolken und Planeten werden über Godot-Meshes und prozedurale Custom-Shader (`.gdshader`) in Echtzeit berechnet.

---

## Die wichtigste Lektion: Iteration schlägt "One-Shot"

Ein zentraler Punkt im Video ist das Mindset beim Entwickeln mit KI:

> *"Man gibt nicht einen magischen Prompt ein und das Projekt ist perfekt fertig. Wer glaubt, dass ein One-Shot-Prompt ein hochkomplexes 3D-Spiel liefert, wird enttäuscht. Der wahre Hebel liegt im dialogbasierten, iterativen Arbeiten: Prompten, sofort testen, Fehler gezielt korrigieren und Features schrittweise aufbauen."*

### So lief der Entwicklungszyklus mit Astra-KI:
1. **Stufe 1 – Grundarchitektur:** Hauptszene mit WorldEnvironment (SDFGI, Volumetric Fog, SSR, SSAO) und First-Person-Controller mit Minimap.
2. **Stufe 2 – Multi-Level-Labyrinth:** 3 Etagen mit Rampen, Atrium und 7 thematischen Galerien.
3. **Stufe 3 – Shader & Feinheiten:** Spektrale Kristallbrechung (Glacier), glühende Bodennetze (Ember), Aurora Borealis (Afterglow) und Planarspiegel (Nocturne).
4. **Stufe 4 – Flughafen & Weltraum-Flug:** Ausbau eines vollständigen Terminals mit Vorfeldverkehr, Fluggastbrücke und einer Passagiermaschine, die in Echtzeit in den Orbit fliegt.
5. **Automatisierte Qualitätssicherung:** Nach jeder Erweiterung prüften GDScript-Regressionstests im Hintergrund Wegpunkte, Kapselkollisionen und Menüzustände.

---

## Die 8 Welten von Chroma im Überblick

1. **01 Atrium (Chroma):** 12 Meter kinetisches Metall (*"Chroma — Engine of Light"*), das sich dynamisch im Boden spiegelt.
2. **02 Solar:** Warmer Saal mit goldenen Sonnensegeln und gefiltertem Licht.
3. **03 Nocturne:** Kosmischer Raum mit Sternenhimmel, Obsidianböden und Planarspiegeln.
4. **04 Glacier:** Schwebende Eisfragmente und Prismen mit spektraler Lichtbrechung.
5. **05 Spectrum:** Prismatische Farbbänder und kinetische Torus-Ringe.
6. **06 Ember:** Dunkles Basaltgestein, Kupferpaneele und glühendes Bodennetz.
7. **07 Afterglow:** Fließendes Polarlicht mit schwebender DNA-Helix-Skulptur.
8. **08 Airport & Chroma Orbit:** Terminal A, Gate A01, 36-Sitz-Passagierkabine und 150-Sekunden-Rundflug bis zur Erdkrümmung.

---

## Technische Eckdaten

* **Engine:** Godot 4.7.2 (getestet mit Forward+ Vulkan Renderer)
* **Hardware-Performance:** Flüssige 60+ FPS bei 1920×1080 auf RTX 4070
* **Features:** SDFGI, Screen-Space Reflections, Volumetrischer Nebel, Custom GDShaders
* **Repository:** Vollständig Open Source auf GitHub:  
  [https://github.com/tnickel/chroma-labyrinth](https://github.com/tnickel/chroma-labyrinth)

---

## Teaser-Text für Social Media & Startseite (Short Pitch)

> **🚀 In 3 Stunden zum eigenen 3D-Museum mit Raumflug in Godot 4!**  
> Wie viel GameDev-Erfahrung braucht man heute noch, um beeindruckende 3D-Welten mit Reflexionen, Shadern und eigener Flugmechanik zu bauen? Fast keine – wenn man die richtige KI an seiner Seite hat.  
> In diesem Showcase-Projekt zeigen wir, wie mit der Godot Engine 4 und Astra-KI in nur einem Nachmittag ein vollständiges Labyrinth mit 8 Themenwelten und echtem Orbit-Flug entstanden ist.  
> 📺 Jetzt beide Videos ansehen und den Code auf GitHub ausprobieren!
