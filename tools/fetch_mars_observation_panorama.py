#!/usr/bin/env python3
"""Fetch and downsample NASA's 360-degree Curiosity panorama for the tower.

The source is resized without cropping so it fits the GPU's texture limit.
The game ships the derived image and needs no network at runtime.
"""
from pathlib import Path
from urllib.request import Request, urlopen
from io import BytesIO
import hashlib
from PIL import Image

URL = ("https://assets.science.nasa.gov/content/dam/science/psd/"
       "photojournal/pia/pia26/pia26363/PIA26363.jpg")
TARGET = Path(__file__).resolve().parents[1] / "assets/space/mars_observation/gediz_vallis_360.jpg"
TARGET_WIDTH = 14000


def main() -> None:
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    request = Request(URL, headers={"User-Agent": "ChromaLabyrinth/1.0 (NASA photo attribution in SOURCE.json)"})
    with urlopen(request, timeout=120) as response:
        if not response.headers.get_content_type().startswith("image/"):
            raise RuntimeError("NASA server did not return an image")
        data = response.read()
    if len(data) < 100_000 or not data.startswith(b"\xff\xd8\xff"):
        raise RuntimeError("NASA panorama download was incomplete")
    Image.MAX_IMAGE_PIXELS = None  # NASA's original is a very large panorama.
    with Image.open(BytesIO(data)) as image:
        width, height = image.size
        if width < 20000 or height < 4000:
            raise RuntimeError(f"Expected the full NASA panorama; received {width}x{height}")
        target_height = round(height * TARGET_WIDTH / width)
        image.resize((TARGET_WIDTH, target_height), Image.Resampling.LANCZOS).convert("RGB").save(
            TARGET, "JPEG", quality=94, subsampling=0, optimize=True
        )
    result = TARGET.read_bytes()
    print(f"Source: {width}x{height}; SHA-256 {hashlib.sha256(data).hexdigest()}")
    print(f"{TARGET}: {TARGET_WIDTH}x{target_height}, {len(result)} bytes; SHA-256 {hashlib.sha256(result).hexdigest()}")


if __name__ == "__main__":
    main()
