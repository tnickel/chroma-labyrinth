"""Fetch the actual NASA GIBS 500-m Mediterranean basemap, without upscaling.

Requires Python 3 + Pillow. Four bounded WMS images cover an 8192 x 8192
georeferenced region; all source checksums and requests are recorded beside it.
The complete operation refuses downloads above 30 MB. No image synthesis occurs.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import tempfile
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from PIL import Image

SERVICE = "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi"
LAYER = "BlueMarble_NextGeneration"
LIMIT = 30_000_000
SOURCES = [
    ("northwest", (36, -4.5, 54, 13.5), (0, 0)),
    ("northeast", (36, 13.5, 54, 31.5), (4096, 0)),
    ("southwest", (18, -4.5, 36, 13.5), (0, 4096)),
    ("southeast", (18, 13.5, 36, 31.5), (4096, 4096)),
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    target = args.project_root / "assets" / "airport"
    target.mkdir(parents=True, exist_ok=True)
    output = target / "earth_mediterranean_500m.jpg"
    manifest_file = target / "earth-region-source.json"
    previous = json.loads(manifest_file.read_text(encoding="utf-8")) if manifest_file.exists() else {}
    if output.exists() and hashlib.sha256(output.read_bytes()).hexdigest() == previous.get("sha256"):
        print("NASA Mediterranean 500-m image already verified.")
        return
    previous_sources = {entry["name"]: entry for entry in previous.get("sources", [])}
    mosaic = Image.new("RGB", (8192, 8192))
    sources = []
    downloaded = 0
    cache = Path(tempfile.gettempdir()) / "chroma-nasa-gibs-source-cache"
    cache.mkdir(parents=True, exist_ok=True)
    for name, bbox, offset in SOURCES:
        query = {"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap",
                 "LAYERS": LAYER, "STYLES": "", "FORMAT": "image/jpeg",
                 "CRS": "EPSG:4326", "BBOX": ",".join(map(str, bbox)),
                 "WIDTH": 4096, "HEIGHT": 4096}
        url = SERVICE + "?" + urlencode(query)
        cached = cache / (hashlib.sha256(url.encode()).hexdigest() + ".jpg")
        if cached.exists():
            data = cached.read_bytes()
        else:
            for attempt in range(3):
                try:
                    with urlopen(Request(url, headers={"User-Agent": "ChromaLabyrinth-AssetBuilder/1.0"}), timeout=60) as response:
                        if response.headers.get_content_type() != "image/jpeg":
                            raise RuntimeError("NASA WMS did not return a JPEG: " + response.read(300).decode(errors="replace"))
                        data = response.read(LIMIT - downloaded + 1)
                    break
                except (TimeoutError, OSError):
                    if attempt == 2:
                        raise
                    print(f"Retrying NASA {name} after a temporary network error", flush=True)
                    time.sleep(1)
        downloaded += len(data)
        if downloaded > LIMIT:
            raise RuntimeError("NASA regional download exceeded the 30-MB limit")
        digest = hashlib.sha256(data).hexdigest()
        expected = previous_sources.get(name, {}).get("sha256")
        if expected is not None and digest != expected:
            raise RuntimeError(f"NASA source changed: {name}. Review before replacing the documented asset.")
        image = Image.open(io.BytesIO(data))
        if image.size != (4096, 4096):
            raise RuntimeError(f"Unexpected NASA image dimensions: {image.size}")
        cached.write_bytes(data)
        mosaic.paste(image.convert("RGB"), offset)
        sources.append({"name": name, "url": url, "sha256": digest, "bytes": len(data), "bbox_south_west_north_east": bbox})
        print(f"NASA {name}: {len(data):,} bytes verified", flush=True)
    # Lossless pixel assembly followed by ordinary JPEG encoding, no resize,
    # invented detail, sharpening, colour processing, or geographical warp.
    mosaic.save(output, quality=95, subsampling=0, optimize=True)
    manifest = {"file": output.name, "source": "NASA EOSDIS GIBS / Blue Marble Next Generation (MODIS)",
                "layer": LAYER, "matrix_set": "500m", "dimensions": [8192, 8192],
                "bounds_degrees": {"west": -4.5, "east": 31.5, "south": 18, "north": 54},
                "degrees_per_pixel": 36 / 8192, "equatorial_meters_per_pixel": 489.19698,
                "transformation": "Four native-resolution 4096-square WMS images assembled without resampling; JPEG quality95, 4:4:4",
                "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "sources": sources,
                "source_download_bytes": downloaded, "output_bytes": output.stat().st_size,
                "documentation": "https://nasa-gibs.github.io/gibs-api-docs/access-basics/",
                "usage": "https://www.nasa.gov/nasa-brand-center/images-and-media/"}
    manifest_file.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {output.name}: {output.stat().st_size:,} bytes; source total {downloaded:,} bytes")


if __name__ == "__main__":
    main()
