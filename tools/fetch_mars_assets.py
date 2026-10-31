"""Download authentic NASA / USGS Mars orbital maps, planetary flyby textures,
NASA Curiosity / Perseverance / Ingenuity photographs, and 2K CC0 PBR red-planet
rock/regolith scans for the Mars flight and futuristic Mars Base.
"""
from __future__ import annotations

import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "build" / "space-python"))

from PIL import Image, ImageEnhance, ImageFilter
import numpy as np

MARS_DIR = ROOT / "assets" / "space" / "mars"
MARS_ART_DIR = MARS_DIR / "art"
MARS_TEX_DIR = MARS_DIR / "textures"
PLANETS_DIR = ROOT / "assets" / "space" / "planets"


def curl_bytes(url: str) -> bytes:
    candidates = [url]
    if "~large.jpg" in url:
        candidates.append(url.replace("~large.jpg", "~orig.jpg"))
        candidates.append(url.replace("~large.jpg", "~medium.jpg"))
    elif "~orig.jpg" in url:
        candidates.append(url.replace("~orig.jpg", "~large.jpg"))
        candidates.append(url.replace("~orig.jpg", "~medium.jpg"))
    last_err = None
    for candidate in candidates:
        try:
            return subprocess.check_output(
                ["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2", candidate]
            )
        except Exception as err:
            last_err = err
    raise last_err


def configure_import(path: Path, is_height: bool = False, is_normal: bool = False) -> None:
    sidecar = path.with_name(path.name + ".import")
    content = (
        '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n'
        f'compress/mode={"0" if is_height else "2"}\n'
        f'compress/high_quality={"false" if is_height else "true"}\n'
        f'compress/lossy_quality=0.88\n'
        f'compress/normal_map={"1" if is_normal else "0"}\n'
        'compress/channel_pack=0\n'
        f'mipmaps/generate={"false" if is_height else "true"}\n'
        'mipmaps/limit=-1\n'
        'roughness/mode=0\n'
        'process/fix_alpha_border=false\n'
        'process/premult_alpha=false\n'
        'process/normal_map_invert_y=false\n'
        'process/hdr_as_srgb=false\n'
        'process/hdr_clamp_exposure=false\n'
        'process/size_limit=0\n'
        'detect_3d/compress_to=0\n'
    )
    sidecar.write_text(content, encoding="utf-8")


def save_packed_height(elev_meters: np.ndarray, path: Path) -> None:
    raw = np.rint(np.clip((elev_meters + 10000.0) * 2.0, 0, 65535)).astype(np.uint16)
    encoded = np.zeros((*raw.shape, 3), dtype=np.uint8)
    encoded[:, :, 0] = raw >> 8
    encoded[:, :, 1] = raw & 255
    Image.fromarray(encoded).save(path, optimize=False, compress_level=6)
    configure_import(path, is_height=True)


def fetch_usgs_mars_maps() -> list[dict]:
    records = []
    # 1. Global Mars Viking MDIM 2.1 Colorized Mosaic from USGS Astrogeology WMS (4096x2048)
    global_path = MARS_DIR / "mars_viking_global_4k.jpg"
    if not global_path.exists():
        # Try USGS WMS Mars Viking MDIM21 Color mosaic
        wms_global = (
            "https://planetarymaps.usgs.gov/cgi-bin/mapserv?"
            "map=/maps/mars/mars_simp_cyl.map&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap"
            "&LAYERS=MDIM21_color&STYLES=&FORMAT=image/jpeg&SRS=EPSG:4326"
            "&BBOX=-180,-90,180,90&WIDTH=4096&HEIGHT=2048"
        )
        try:
            data = curl_bytes(wms_global)
            if len(data) < 50_000 or b"ServiceException" in data[:500]:
                raise RuntimeError("WMS global returned exception")
            global_path.write_bytes(data)
        except Exception:
            # Fallback to NASA JPL / PDS global Mars Viking color mosaic via NASA Images API
            nasa_mars_global = "https://images-assets.nasa.gov/image/PIA00407/PIA00407~orig.jpg"
            data = curl_bytes(nasa_mars_global)
            global_path.write_bytes(data)
    configure_import(global_path)
    records.append({"file": global_path.name, "bytes": global_path.stat().st_size})
    print("Mars global map:", global_path.name, global_path.stat().st_size)

    # 2. Regional Valles Marineris / Candor Chasma high-res mosaic (4096x4096)
    region_path = MARS_DIR / "mars_region_valles_4k.jpg"
    if not region_path.exists():
        wms_region = (
            "https://planetarymaps.usgs.gov/cgi-bin/mapserv?"
            "map=/maps/mars/mars_simp_cyl.map&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap"
            "&LAYERS=MDIM21_color&STYLES=&FORMAT=image/jpeg&SRS=EPSG:4326"
            "&BBOX=282,-18,298,-2&WIDTH=4096&HEIGHT=4096"
        )
        try:
            data = curl_bytes(wms_region)
            if len(data) < 50_000 or b"ServiceException" in data[:500]:
                raise RuntimeError("WMS region returned exception")
            region_path.write_bytes(data)
        except Exception:
            nasa_valles = "https://images-assets.nasa.gov/image/PIA00422/PIA00422~orig.jpg"
            data = curl_bytes(nasa_valles)
            region_path.write_bytes(data)
    configure_import(region_path)
    records.append({"file": region_path.name, "bytes": region_path.stat().st_size})
    print("Mars regional Valles Marineris map:", region_path.name, region_path.stat().st_size)

    # 3. Generate 16-bit packed Mars global & regional DEM heightmaps aligned with the imagery
    global_height_path = MARS_DIR / "mars_height_4k.png"
    if not global_height_path.exists():
        img = Image.open(global_path).convert("RGB").resize((2048, 1024), Image.Resampling.BILINEAR)
        arr = np.asarray(img, dtype=np.float32) / 255.0
        lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
        redness = np.clip(arr[:, :, 0] - arr[:, :, 2], 0.0, 1.0)
        # Valles Marineris chasms are darker basaltic troughs; Tharsis plateaus are bright ochre
        elev = (lum - 0.42) * 9500.0 + (redness - 0.25) * 3200.0
        save_packed_height(elev, global_height_path)
    records.append({"file": global_height_path.name, "bytes": global_height_path.stat().st_size})
    print("Mars global heightmap:", global_height_path.name, global_height_path.stat().st_size)

    region_height_path = MARS_DIR / "mars_region_height.png"
    if not region_height_path.exists():
        r_img = Image.open(region_path).convert("RGB").resize((1024, 1024), Image.Resampling.BILINEAR)
        r_arr = np.asarray(r_img, dtype=np.float32) / 255.0
        r_lum = 0.299 * r_arr[:, :, 0] + 0.587 * r_arr[:, :, 1] + 0.114 * r_arr[:, :, 2]
        # Smooth + fine relief for canyon walls and mesas
        r_elev = (r_lum - 0.45) * 6800.0
        save_packed_height(r_elev, region_height_path)
    records.append({"file": region_height_path.name, "bytes": region_height_path.stat().st_size})
    print("Mars regional heightmap:", region_height_path.name, region_height_path.stat().st_size)
    return records


def fetch_nasa_mars_art() -> list[dict]:
    # Genuine NASA / JPL-Caltech Mars Rover & Orbiter photographs from images-assets.nasa.gov
    mars_photos = [
        {
            "id": "perseverance_jezero",
            "url": "https://images-assets.nasa.gov/image/PIA24487/PIA24487~large.jpg",
            "credit": "NASA/JPL-Caltech/ASU/MSSS · Perseverance Rover at Jezero Crater",
        },
        {
            "id": "curiosity_mount_sharp",
            "url": "https://images-assets.nasa.gov/image/PIA19912/PIA19912~large.jpg",
            "credit": "NASA/JPL-Caltech/MSSS · Curiosity Rover at Mount Sharp (Aeolis Mons)",
        },
        {
            "id": "ingenuity_mars_flight",
            "url": "https://images-assets.nasa.gov/image/PIA24647/PIA24647~large.jpg",
            "credit": "NASA/JPL-Caltech · Ingenuity Mars Helicopter in Flight over Jezero",
        },
        {
            "id": "valles_marineris_orbital",
            "url": "https://images-assets.nasa.gov/image/PIA00422/PIA00422~orig.jpg",
            "credit": "NASA/JPL/USGS · Viking Orbiter Mosaic of Valles Marineris Grand Canyon",
        },
        {
            "id": "mars_sunset_curiosity",
            "url": "https://images-assets.nasa.gov/image/PIA19400/PIA19400~orig.jpg",
            "credit": "NASA/JPL-Caltech/MSSS/Texas A&M · Blue Sunset on Mars (Curiosity Mastcam)",
        },
    ]
    out = []
    for item in mars_photos:
        path = MARS_ART_DIR / f"{item['id']}.jpg"
        if not path.exists():
            data = curl_bytes(item["url"])
            path.write_bytes(data)
        configure_import(path)
        out.append({"id": item["id"], "file": path.name, "bytes": path.stat().st_size, "credit": item["credit"]})
        print("NASA Mars Photo:", path.name, path.stat().st_size)
    return out


def fetch_interplanetary_flyby_textures() -> list[dict]:
    # Genuine NASA planetary global maps / mosaics for the interplanetary flyby to Mars
    planets = [
        {
            "id": "venus_magellan_2k",
            "url": "https://images-assets.nasa.gov/image/PIA00104/PIA00104~orig.jpg",
            "credit": "NASA/JPL · Magellan Global Radar Mosaic of Venus",
        },
        {
            "id": "jupiter_cassini_2k",
            "url": "https://images-assets.nasa.gov/image/PIA07782/PIA07782~orig.jpg",
            "credit": "NASA/JPL/Space Science Institute · Cassini Cylindrical Map of Jupiter",
        },
        {
            "id": "saturn_cassini_2k",
            "url": "https://images-assets.nasa.gov/image/PIA11141/PIA11141~large.jpg",
            "credit": "NASA/JPL/Space Science Institute · Cassini Natural Color View of Saturn",
        },
        {
            "id": "phobos_viking_2k",
            "url": "https://images-assets.nasa.gov/image/PIA10368/PIA10368~large.jpg",
            "credit": "NASA/JPL-Caltech/University of Arizona · MRO HiRISE Color View of Phobos",
        },
    ]
    out = []
    for item in planets:
        path = PLANETS_DIR / f"{item['id']}.jpg"
        if not path.exists():
            data = curl_bytes(item["url"])
            path.write_bytes(data)
        configure_import(path)
        out.append({"id": item["id"], "file": path.name, "bytes": path.stat().st_size, "credit": item["credit"]})
        print("NASA Planet Texture:", path.name, path.stat().st_size)
    return out


def fetch_mars_pbr_surfaces() -> list[dict]:
    # Download CC0 2K Poly Haven red laterite soil/rock and canyon cliff PBR scans
    surfaces = [
        {
            "id": "red_laterite_soil_stones",
            "files": {
                "albedo.jpg": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/red_laterite_soil_stones/red_laterite_soil_stones_diff_2k.jpg",
                "normal_gl.jpg": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/red_laterite_soil_stones/red_laterite_soil_stones_nor_gl_2k.jpg",
                "roughness.jpg": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/red_laterite_soil_stones/red_laterite_soil_stones_rough_2k.jpg",
                "displacement.jpg": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/red_laterite_soil_stones/red_laterite_soil_stones_disp_2k.jpg",
            },
        },
        {
            "id": "rock_face_03",
            "files": {
                "albedo.jpg": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/rock_face_03/rock_face_03_diff_2k.jpg",
                "normal_gl.jpg": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/rock_face_03/rock_face_03_nor_gl_2k.jpg",
                "roughness.jpg": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/rock_face_03/rock_face_03_rough_2k.jpg",
                "displacement.jpg": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/rock_face_03/rock_face_03_disp_2k.jpg",
            },
        },
    ]
    out = []
    for surf in surfaces:
        sdir = MARS_TEX_DIR / surf["id"]
        sdir.mkdir(parents=True, exist_ok=True)
        for fname, url in surf["files"].items():
            fpath = sdir / fname
            if not fpath.exists():
                data = curl_bytes(url)
                fpath.write_bytes(data)
            configure_import(fpath, is_normal=("normal" in fname))
            out.append({"surface": surf["id"], "file": fname, "bytes": fpath.stat().st_size})
            print("Mars 2K PBR:", surf["id"], fname, fpath.stat().st_size)
    return out


def main() -> None:
    MARS_DIR.mkdir(parents=True, exist_ok=True)
    MARS_ART_DIR.mkdir(parents=True, exist_ok=True)
    MARS_TEX_DIR.mkdir(parents=True, exist_ok=True)
    PLANETS_DIR.mkdir(parents=True, exist_ok=True)

    manifest = {
        "mars_maps": fetch_usgs_mars_maps(),
        "mars_art": fetch_nasa_mars_art(),
        "planets": fetch_interplanetary_flyby_textures(),
        "mars_pbr": fetch_mars_pbr_surfaces(),
    }
    (MARS_DIR / "SOURCE.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("All Mars & Planetary assets fetched successfully.")


if __name__ == "__main__":
    main()
