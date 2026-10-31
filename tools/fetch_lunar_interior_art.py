"""Install credited NASA/ESA mission and astronomy photographs for the habitat."""
from hashlib import md5, sha256
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1] / "assets" / "space" / "interior" / "art"
NASA_GUIDELINES = "https://www.nasa.gov/nasa-brand-center/images-and-media/"
HUBBLE_LICENSE = "https://esahubble.org/copyright/"
ART = [
    {"id": "orion", "url": "https://cdn.esahubble.org/archives/images/screen/heic0601a.jpg",
     "source": "https://esahubble.org/images/heic0601a/", "md5": "fb45d877d1b51166498ff181fc7afadb",
     "credit": "NASA, ESA, M. Robberto (Space Telescope Science Institute/ESA) and the Hubble Space Telescope Orion Treasury Project Team",
     "license": "CC BY 4.0", "license_url": HUBBLE_LICENSE},
    {"id": "pillars", "url": "https://cdn.esahubble.org/archives/images/screen/heic1501a.jpg",
     "source": "https://esahubble.org/images/heic1501a/", "md5": "e0f9966f78fe54ba9b5752ba7ba5fc2a",
     "credit": "NASA, ESA/Hubble and the Hubble Heritage Team",
     "license": "CC BY 4.0", "license_url": HUBBLE_LICENSE},
    {"id": "earthrise", "url": "https://images-assets.nasa.gov/image/as08-14-2383/as08-14-2383~large.jpg",
     "source": "https://science.nasa.gov/resource/the-rising-earth-as-seen-by-apollo-8/", "md5": "1b51ab1e7299112eb7165e6d99bcaf9a",
     "credit": "NASA / Apollo 8", "license": "NASA media usage guidelines", "license_url": NASA_GUIDELINES},
    {"id": "blue_marble", "url": "https://images-assets.nasa.gov/image/as17-148-22727/as17-148-22727~large.jpg",
     "source": "https://science.nasa.gov/resource/the-blue-marble/", "md5": "93d994956081accfb69a29ead32027f7",
     "credit": "NASA Johnson Space Center / Apollo 17", "license": "NASA media usage guidelines", "license_url": NASA_GUIDELINES},
    {"id": "apollo11", "url": "https://images-assets.nasa.gov/image/as11-40-5927/as11-40-5927~large.jpg",
     "source": "https://images.nasa.gov/details-as11-40-5927", "md5": "a6d7c450b96f137ca135d871dccda3e8",
     "credit": "NASA / Apollo 11", "license": "NASA media usage guidelines", "license_url": NASA_GUIDELINES},
    {"id": "apollo15_hadley", "url": "https://images-assets.nasa.gov/image/as15-88-11866/as15-88-11866~large.jpg",
     "source": "https://images.nasa.gov/details-as15-88-11866", "md5": "2414d6d264a81d2ec0f6097095ba1d75",
     "credit": "NASA / Apollo 15 (Dave Scott, Jim Irwin, Lunar Roving Vehicle & Mount Hadley)", "license": "NASA media usage guidelines", "license_url": NASA_GUIDELINES},
    {"id": "apollo17_boulder", "url": "https://images-assets.nasa.gov/image/as17-140-21496/as17-140-21496~large.jpg",
     "source": "https://images.nasa.gov/details-as17-140-21496", "md5": "481a33268c1f1115ecf892ca28443a29",
     "credit": "NASA / Apollo 17 (Gene Cernan, Harrison Schmitt & Taurus-Littrow Split Rock Boulder)", "license": "NASA media usage guidelines", "license_url": NASA_GUIDELINES},
]


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    for item in ART:
        data = subprocess.check_output(["curl", "--fail", "--location", "--silent", "--show-error", item["url"]])
        if md5(data).hexdigest() != item["md5"]:
            raise RuntimeError(f"Image checksum mismatch: {item['url']}")
        item["path"] = item["id"] + ".jpg"
        item["bytes"] = len(data)
        item["sha256"] = sha256(data).hexdigest()
        (ROOT / item["path"]).write_bytes(data)
        print(item["id"], len(data), item["sha256"])
    (ROOT / "image-sources.json").write_text(json.dumps({"images": ART}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
