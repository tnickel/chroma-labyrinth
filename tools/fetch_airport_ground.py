"""Reproduce the bounded, public-domain NAIP image used by the flight stage.

No GIS/Pillow dependencies; USGS performs projection and JPEG export. Raster
IDs and export parameters are pinned in the source manifest. A future provider
re-render with different bytes is rejected instead of silently replacing art.
"""
from pathlib import Path
import hashlib
import json
import urllib.parse
import urllib.request


def main():
    root = Path(__file__).resolve().parents[1] / "assets" / "airport" / "ground"
    source = json.loads((root / "source.json").read_text(encoding="utf-8-sig"))
    target = root / source["file"]
    expected = source["sha256"]
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == expected:
        print(f"Verified bundled USDA NAIP image: {target.name}")
        return
    payload = urllib.parse.urlencode(source["export_parameters"]).encode("ascii")
    request = urllib.request.Request(source["source_service"] + "/exportImage", data=payload)
    with urllib.request.urlopen(request, timeout=90) as response:
        result = json.load(response)
    if "error" in result:
        raise RuntimeError(f"USGS export failed: {result['error']}")
    if result.get("width") != 4000 or result.get("height") != 4000:
        raise RuntimeError("USGS returned unexpected image dimensions")
    with urllib.request.urlopen(result["href"], timeout=90) as response:
        image = response.read(15 * 1024 * 1024 + 1)
    if len(image) > 15 * 1024 * 1024:
        raise RuntimeError("USGS image exceeds the 15 MiB asset budget")
    if hashlib.sha256(image).hexdigest() != expected:
        raise RuntimeError("USGS export checksum changed; inspect source imagery before updating the manifest")
    temporary = target.with_suffix(".jpg.part")
    temporary.write_bytes(image)
    temporary.replace(target)
    print(f"Downloaded and verified USDA NAIP image: {target.name} ({len(image):,} bytes)")


if __name__ == "__main__":
    main()
