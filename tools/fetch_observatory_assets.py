"""Fetch the unmodified observatory photographs; runtime is entirely offline."""
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from pathlib import Path
from urllib.request import Request, urlopen
import json

ROOT = Path(__file__).resolve().parents[1] / "assets/space/observatory"
SOURCES = [
    dict(file="carina_webb.jpg", title="NIRCam Image of the Cosmic Cliffs in Carina",
         url="https://cdn.esawebb.org/archives/images/publicationjpg/weic2205a.jpg",
         page="https://esawebb.org/images/weic2205a/",
         credit="NASA, ESA, CSA, and STScI", image_id="weic2205a",
         interpretation="Infrared observations mapped to visible colours; not a naked-eye view.",
         license="CC BY 4.0", license_url="https://esawebb.org/copyright/"),
    dict(file="jupiter_cassini.jpg", title="Cassini Jupiter Portrait",
         url="https://assets.science.nasa.gov/dynamicimage/assets/science/psd/photojournal/pia/pia04/pia04866/PIA04866.jpg?w=1920&h=2400&fit=max",
         page="https://science.nasa.gov/photojournal/cassini-jupiter-portrait/",
         credit="NASA/JPL/Space Science Institute", image_id="PIA04866",
         interpretation="27-frame true-colour mosaic, Cassini, 29 December 2000.",
         license="NASA/JPL image use guidelines; retain credit; no endorsement implied",
         license_url="https://www.jpl.nasa.gov/jpl-image-use-policy/"),
    dict(file="saturn_cassini.jpg", title="The Day the Earth Smiled",
         url="https://assets.science.nasa.gov/dynamicimage/assets/science/psd/solar/2023/09/1/185_PIA17172.jpg?w=4096&fit=max",
         page="https://science.nasa.gov/resource/the-day-the-earth-smiled/",
         credit="NASA/JPL-Caltech/SSI", image_id="PIA17172",
         interpretation="Natural-colour mosaic of 141 Cassini frames, 19 July 2013.",
         license="NASA/JPL image use guidelines; retain credit; no endorsement implied",
         license_url="https://www.jpl.nasa.gov/jpl-image-use-policy/"),
]


def fetch(source):
    target = ROOT / source["file"]
    request = Request(source["url"], headers={"User-Agent": "ChromaObservatoryAssetFetcher/1.0"})
    with urlopen(request, timeout=90) as response:
        payload = response.read()
    if not payload.startswith(b"\xff\xd8\xff"):
        raise ValueError(f"Not a JPEG: {source['url']}")
    target.write_bytes(payload)
    return dict(source, bytes=len(payload), sha256=sha256(payload).hexdigest(),
                transformation="No local image edits. NASA CDN requests a maximum resolution, preserving aspect ratio; ESA publication JPEG used as distributed. Scene keeps image aspect ratio; engine tone mapping applies.")


if __name__ == "__main__":
    ROOT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=3) as pool:
        sources = list(pool.map(fetch, SOURCES))
    manifest = dict(retrieved_utc_date="2026-10-31", offline_runtime=True,
                    presentation="Virtual archive projections during a fictional, time-compressed Mars voyage. Not objects along a physical trajectory.",
                    runtime_compositing="Planet photographs use transparent dark backgrounds and feathered image edges over the catalogue sky. Elliptical limb mattes occult stars on the dark bodies; Jupiter's cropped unlit hemisphere is extended as a black geometric matte. Ring light contribution is preserved independently of coverage. Carina is unmasked. Source JPEGs remain unchanged; no surface detail is generated.",
                    stars="Existing assets/space/stars_8k.png: NASA SVS catalogue-derived sky; see ../SOURCE.json and https://svs.gsfc.nasa.gov/4851/.",
                    sources=sources)
    (ROOT / "SOURCE.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps([{k: s[k] for k in ("file", "bytes", "sha256")} for s in sources], indent=2))
