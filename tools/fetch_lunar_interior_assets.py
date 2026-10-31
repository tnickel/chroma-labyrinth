"""Fetch the CC0 Poly Haven props used by the lunar habitat.

The project runs offline once imported. The manifest records the upstream
checksums and source of each file; no mutable API response is trusted without
verifying the corresponding download.
"""
from concurrent.futures import ThreadPoolExecutor
from hashlib import md5, sha256
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1] / "assets" / "space" / "interior"
ASSETS = (
    "chemistry_set", "circuit_board", "industrial_microscope",
    "modular_electric_cables", "plastic_container", "plastic_crate_02",
)
TEXTURES = ("blue_metal_plate", "rubber_tiles")


def fetch(url: str) -> bytes:
    return subprocess.check_output(["curl", "--fail", "--location", "--silent", "--show-error", url])


def install(asset: str) -> dict:
    api = f"https://api.polyhaven.com/files/{asset}"
    info = json.loads(fetch(api))["gltf"]["1k"]["gltf"]
    files = [{"path": f"{asset}_1k.gltf", **info}]
    files.extend({"path": path, **data} for path, data in info["include"].items())
    installed = []
    for entry in files:
        data = fetch(entry["url"])
        actual = md5(data).hexdigest()
        if actual != entry["md5"] or len(data) != entry["size"]:
            raise RuntimeError(f"Upstream checksum/size mismatch: {entry['url']}")
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Unexpected model path: {relative}")
        path = ROOT / asset / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        installed.append({"path": entry["path"], "url": entry["url"], "bytes": len(data),
                          "md5": actual, "sha256": sha256(data).hexdigest()})
    print(f"{asset}: {len(installed)} checked files")
    return {"id": asset, "page": f"https://polyhaven.com/a/{asset}", "api": api,
            "license": "CC0-1.0", "license_url": "https://polyhaven.com/license",
            "retrieved_utc_date": "2026-10-30", "files": installed}


def install_texture(asset: str) -> dict:
    api = f"https://api.polyhaven.com/files/{asset}"
    info = json.loads(fetch(api))
    installed = []
    for channel, local in (("Diffuse", "albedo.jpg"), ("nor_gl", "normal.jpg"), ("Rough", "roughness.jpg")):
        entry = info[channel]["1k"]["jpg"]
        data = fetch(entry["url"])
        actual = md5(data).hexdigest()
        if actual != entry["md5"] or len(data) != entry["size"]:
            raise RuntimeError(f"Upstream checksum/size mismatch: {entry['url']}")
        path = ROOT / "textures" / asset / local
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        installed.append({"path": f"textures/{asset}/{local}", "url": entry["url"], "bytes": len(data),
                          "md5": actual, "sha256": sha256(data).hexdigest()})
    print(f"{asset}: {len(installed)} checked texture maps")
    return {"id": asset, "page": f"https://polyhaven.com/a/{asset}", "api": api,
            "license": "CC0-1.0", "license_url": "https://polyhaven.com/license",
            "retrieved_utc_date": "2026-10-30", "files": installed}


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as executor:
        manifest = list(executor.map(install, ASSETS))
        textures = list(executor.map(install_texture, TEXTURES))
    (ROOT / "model-sources.json").write_text(json.dumps({"assets": manifest, "textures": textures}, indent=2) + "\n", encoding="utf-8")
    (ROOT / "LICENSES.txt").write_text(
        "Lunar habitat props from Poly Haven (https://polyhaven.com/)\n"
        "All listed models and textures are provided under CC0 1.0.\n"
        "License: https://polyhaven.com/license\n"
        "Individual asset pages, source URLs and checksums: model-sources.json\n", encoding="utf-8")


if __name__ == "__main__":
    main()
