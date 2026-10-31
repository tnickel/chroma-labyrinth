#!/usr/bin/env python3
"""Fetch the CC0 Poly Haven lunar-analogue scans used by the lunar base.

The scans were made at Spaceport Rostock's terrestrial lunar-simulation lab;
they are not photographs or samples from the Moon. No downloads occur at run
time. Re-run this helper to reproduce the assets; upstream MD5 and our SHA-256
checksums are recorded alongside the files.
"""
from __future__ import annotations

import concurrent.futures
import hashlib
import json
from pathlib import Path, PurePosixPath
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1] / "assets" / "space" / "lunar_analog"
API = "https://api.polyhaven.com"
TEXTURES = ("moon_01", "moon_dusted_02", "moon_meteor_01", "moon_footprints_01", "moon_track_01")
MODELS = ("moon_rock_01", "moon_rock_02", "moon_rock_03", "moon_rock_05", "moon_rock_07")
MAPS = {"Diffuse": "albedo.jpg", "nor_gl": "normal_gl.jpg", "Rough": "roughness.jpg", "Displacement": "displacement.jpg"}


def fetch(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "Chroma-Labyrinth/1.0 (asset preparation)"})
    with urlopen(request, timeout=90) as response:
        return response.read()


def api_json(path: str) -> dict:
    return json.loads(fetch(API + path))


def safe_subpath(value: str) -> Path:
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("..", "") for part in path.parts):
        raise ValueError("Unsafe dependency path: " + value)
    return Path(*path.parts)


def main() -> None:
    jobs = []
    metadata = {}
    for name in TEXTURES + MODELS:
        info = api_json("/info/" + name)
        files = api_json("/files/" + name)
        metadata[name] = {
            "asset_page": "https://polyhaven.com/a/" + name,
            "authors": info.get("authors", {}),
            "source_context": "Terrestrial lunar-simulant lab at Spaceport Rostock; not lunar samples.",
            "files": {},
        }
        if name in TEXTURES:
            for source_key, local_name in MAPS.items():
                jobs.append((name, Path("textures") / name / local_name, files[source_key]["2k"]["jpg"]))
        else:
            entry = files["gltf"]["2k"]["gltf"]
            folder = Path("models") / name
            jobs.append((name, folder / (name + "_2k.gltf"), entry))
            for local_name, dependency in entry["include"].items():
                jobs.append((name, folder / safe_subpath(local_name), dependency))

    def download(job: tuple) -> tuple:
        asset, relative, record = job
        data = fetch(record["url"])
        if hashlib.md5(data).hexdigest() != record["md5"]:
            raise ValueError("Upstream checksum mismatch: " + record["url"])
        destination = ROOT / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        return asset, str(relative).replace("\\", "/"), {
            "url": record["url"], "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()
        }

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        for asset, relative, record in executor.map(download, jobs):
            metadata[asset]["files"][relative] = record
            print(relative, record["bytes"])
    manifest = {
        "source": "Poly Haven Moon Collection, terrestrial lunar-simulation lab scans",
        "license": "CC0-1.0", "license_url": "https://polyhaven.com/license",
        "collection": "https://polyhaven.com/collections/moon",
        "note": "These are terrestrial analogues, not images or samples collected on the Moon.",
        "assets": metadata,
    }
    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT / "SOURCE.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
