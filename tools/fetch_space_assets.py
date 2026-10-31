"""Build the offline lunar flight textures from NASA/LROC observations.

Requires Pillow, numpy, tifffile, OpenEXR and opencv-python-headless. Original
downloads are cached under ignored build/space-sources. No generated imagery,
AI upscaling or invented terrain is used. See assets/space/SOURCE.json for the
exact source/product coordinates, processing and checksums.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
# Optional local conversion dependencies: never required when playing the game.
sys.path.insert(0, str(ROOT / "build" / "space-python"))
RADIUS = 1737400.0
SVS = "https://svs.gsfc.nasa.gov/vis/a000000/"
PDS = "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/"
WAC_NAME = "copernicus_wac_4096.png"
WAC_URL = "https://planetarymaps.usgs.gov/cgi-bin/mapserv?map=/maps/earth/moon_simp_cyl.map&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=LROC_WAC&STYLES=&FORMAT=image/png&SRS=EPSG:4326&BBOX=334,2,350,18&WIDTH=4096&HEIGHT=4096"
WAC_DOCUMENTATION = "https://astrogeology.usgs.gov/search/map/moon_lro_lroc_wac_global_morphology_mosaic_100m"
WAC_LICENSE = "https://www.usgs.gov/media/images/moon-lro-lroc-wac-global-morphology-mosaic-100-m"
CLOUD_NAME = "cloud_combined_2048.jpg"
CLOUD_ORIGINAL = "https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57747/cloud_combined_2048.jpg"
CLOUD_DOCUMENTATION = "https://science.nasa.gov/earth/earth-observatory/the-blue-marble-true-color-global-imagery-at-1km-resolution/"
# Real photographed spacecraft hardware for the lunar base compounds: flown ISS
# hardware photographed by Shuttle/ISS crews plus the Apollo 11 descent stage.
BASE_DOCUMENTATION = "https://www.nasa.gov/nasa-brand-center/images-and-media/"
BASE_SOURCES = {
    "s116e05970~orig.jpg": "https://images-assets.nasa.gov/image/s116e05970/s116e05970~orig.jpg",
    "s124e006729~orig.jpg": "https://images-assets.nasa.gov/image/s124e006729/s124e006729~orig.jpg",
    "as11-40-5927~orig.jpg": "https://images-assets.nasa.gov/image/as11-40-5927/as11-40-5927~orig.jpg",
}
BASE_CROPS = [
    {"source": "s116e05970~orig.jpg", "rect": [83, 379, 1789, 1256], "output": "base_solar_cells.jpg",
     "subject": "STS-116 photograph of an ISS Solar Array Wing, face-on photovoltaic cells",
     "transformation": "Single crop of the clean cell field at original 3032x2008 pixels; no resize, sharpening or synthesis."},
    {"source": "s124e006729~orig.jpg", "rect": [720, 300, 2050, 1450], "output": "base_module_hull.jpg",
     "subject": "STS-124 photograph of the JEM Kibo pressurized module micrometeoroid shielding and rails",
     "transformation": "Single crop of the plated hull at original 3072x2098 pixels; no resize, sharpening or synthesis."},
    {"source": "as11-40-5927~orig.jpg", "rect": [1113, 1648, 1497, 2256], "output": "base_gold_foil.jpg",
     "subject": "Apollo 11 photograph AS11-40-5927 of the LM descent stage crinkled gold thermal blanket",
     "transformation": "Single crop at original 4095x4095 pixels plus +18% exposure normalization for space lighting; no resize or synthesis."},
    {"source": "as11-40-5927~orig.jpg", "rect": [1913, 560, 2777, 1158], "output": "base_ascent_white.jpg",
     "subject": "Apollo 11 photograph AS11-40-5927 of the LM ascent stage white thermal panels and black boxes",
     "transformation": "Single crop at original 4095x4095 pixels; no resize, sharpening or synthesis."},
]
DOWNLOADS = {
    "lroc_color_poles_16k.tif": SVS + "a004700/a004720/lroc_color_poles_16k.tif",
    "ldem_64_uint.tif": SVS + "a004700/a004720/ldem_64_uint.tif",
    "starmap_2020_8k.exr": SVS + "a004800/a004851/starmap_2020_8k.exr",
    "NAC_ROI_COPERNICLOF_E102N3413_5M.TIF": PDS + "EXTRAS/BROWSE/NAC_ROI/COPERNICLOF/NAC_ROI_COPERNICLOF_E102N3413_5M.TIF",
    "NAC_DTM_COPRNICUS01.TIF": PDS + "DATA/SDP/NAC_DTM/COPRNICUS01/NAC_DTM_COPRNICUS01.TIF",
    "NAC_DTM_COPRNICUS01_README.TXT": PDS + "DATA/SDP/NAC_DTM/COPRNICUS01/NAC_DTM_COPRNICUS01_README.TXT",
    WAC_NAME: WAC_URL,
    CLOUD_NAME: CLOUD_ORIGINAL,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(cache: Path, name: str, url: str, expected: str | None) -> dict:
    path = cache / name
    if not path.exists():
        partial = path.with_suffix(path.suffix + ".partial")
        request = Request(url, headers={"User-Agent": "ChromaLabyrinth-LunarAssets/1.0"})
        with urlopen(request, timeout=180) as response, partial.open("wb") as output:
            total = 0
            while data := response.read(4 * 1024 * 1024):
                total += len(data)
                if total > 600_000_000:
                    raise RuntimeError("Source exceeds expected 600 MB maximum: " + name)
                output.write(data)
        partial.replace(path)
    digest = sha256(path)
    if expected is not None and expected != digest:
        raise RuntimeError("Source changed; review new data before replacing assets: " + name)
    print(f"Source {name}: {path.stat().st_size:,} bytes, SHA256 {digest}", flush=True)
    return {"name": name, "url": url, "bytes": path.stat().st_size, "sha256": digest}


def geo_metadata(path: Path) -> dict:
    # Both NAC GeoTIFF products use a spherical equirectangular projection.
    with tifffile.TiffFile(path) as source:
        page = source.pages[0]
        origin_x, origin_y = page.tags[33922].value[3:5]
        pixel_size = page.tags[33550].value[0]
        lat_origin, lon_origin, standard_parallel = page.tags[34736].value[:3]
        height, width = page.shape
    longitude_scale = RADIUS * math.cos(math.radians(standard_parallel))
    west = lon_origin + math.degrees(origin_x / longitude_scale)
    east = lon_origin + math.degrees((origin_x + width * pixel_size) / longitude_scale)
    if west > 180:
        west -= 360
        east -= 360
    return {"bounds_degrees": {"west": west, "east": east,
                               "north": lat_origin + math.degrees(origin_y / RADIUS),
                               "south": lat_origin + math.degrees((origin_y - height * pixel_size) / RADIUS)},
            "dimensions": [width, height], "source_metres_per_pixel": pixel_size,
            "projection": "spherical equirectangular",
            "standard_parallel_degrees": standard_parallel,
            "sphere_radius_metres": RADIUS}


def packed_height(values: np.ndarray, path: Path) -> None:
    # Store measured unsigned half metres as R=high byte/G=low byte. Godot's
    # normal PNG importer converts 16-bit grayscale PNG to 8-bit; this avoids it.
    raw = np.rint(np.clip((values + 10000.0) * 2.0, 0, 65535)).astype(np.uint16)
    encoded = np.zeros((*raw.shape, 3), dtype=np.uint8)
    encoded[:, :, 0] = raw >> 8
    encoded[:, :, 1] = raw & 255
    Image.fromarray(encoded).save(path, optimize=False, compress_level=6)


def record(path: Path, **metadata) -> dict:
    print(f"Output {path.name}: {path.stat().st_size:,} bytes", flush=True)
    if path.stat().st_size >= 100_000_000:
        raise RuntimeError("Runtime texture exceeds repository size limit: " + path.name)
    return {"file": path.name, "bytes": path.stat().st_size, "sha256": sha256(path), **metadata}


def configure_import(path: Path) -> None:
    """Keep byte-packed DEM data exact and colorful images GPU-compressed."""
    sidecar = path.with_name(path.name + ".import")
    if sidecar.exists():
        content = sidecar.read_text(encoding="utf-8")
    else:
        # The editor fills UID/cache destinations on first import.
        content = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n'
    height_data = "height" in path.name
    validity = "mask" in path.name
    values = {"compress/mode": "0" if height_data or validity else "2",
              "compress/high_quality": "false" if height_data or validity else "true",
              "compress/normal_map": "0", "compress/channel_pack": "0",
              # Mip quantization of the high byte would add false elevations.
              "mipmaps/generate": "false" if height_data else "true",
              "process/fix_alpha_border": "false", "process/size_limit": "0",
              "process/hdr_as_srgb": "false", "process/hdr_clamp_exposure": "false",
              "detect_3d/compress_to": "0"}
    for key, value in values.items():
        pattern = r"^" + re.escape(key) + r"=.*$"
        line = key + "=" + value
        content = re.sub(pattern, line, content, flags=re.MULTILINE) if re.search(pattern, content, flags=re.MULTILINE) else content.rstrip() + "\n" + line + "\n"
    sidecar.write_text(content, encoding="utf-8")


def sample_raster(data: np.ndarray, source_bounds: dict, longitude: np.ndarray,
                  latitude: np.ndarray) -> np.ndarray:
    height, width = data.shape[:2]
    xs = (longitude - source_bounds["west"]) / (source_bounds["east"] - source_bounds["west"]) * width - 0.5
    ys = (source_bounds["north"] - latitude) / (source_bounds["north"] - source_bounds["south"]) * height - 0.5
    grid_x, grid_y = np.meshgrid(xs.astype(np.float32), ys.astype(np.float32))
    return cv2.remap(data, grid_x, grid_y, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)


def build_wide_context(cache: Path, target: Path) -> list[dict]:
    source = cache / WAC_NAME
    if source.stat().st_size > 30_000_000:
        raise RuntimeError("WAC request exceeds bounded30MB expected size")
    image = Image.open(source).convert("L")
    assert image.size == (4096, 4096), "Unexpected WMS response"
    path = target / "moon_wac_copernicus_4k.jpg"
    image.save(path, quality=96, optimize=True)
    bounds = {"west": -26.0, "east": -10.0, "south": 2.0, "north": 18.0}
    photo = record(path, dimensions=[4096, 4096], bounds_degrees=bounds,
                   color_space="sRGB", source=WAC_NAME,
                   source_layer="USGS planetary WMS LROC_WAC, LROC global morphology100m June2013, edge updateFeb2016",
                   source_metres_per_pixel=100.0000418,
                   output_equatorial_metres_per_pixel=math.radians(16.0) * RADIUS / 4096.0,
                   transformation="4096-square WMS reprojection from native100m observed LROC morphology, JPEG96; no enlargement or generated details. Monochrome photograph includes sunlight/shadows.")
    # Exactly1024 original LOLA pixels per16degrees, sampled at native centers.
    lola = Image.open(cache / "ldem_64_uint.tif")
    crop = lola.crop((154 * 64, 72 * 64, 170 * 64, 88 * 64))
    measured = np.asarray(crop, dtype=np.float32) * 0.5 - 10000.0
    height_path = target / "moon_wac_height.png"
    packed_height(measured, height_path)
    height = record(height_path, dimensions=[1024, 1024], bounds_degrees=bounds,
                    color_space="linear data", source="ldem_64_uint.tif",
                    output_equatorial_metres_per_pixel=math.radians(1.0 / 64.0) * RADIUS,
                    height_range_metres=[float(measured.min()), float(measured.max())],
                    transformation="Exact pixel crop of native64pixels/degree LOLA, original half-metre values packedRG; no resampling.")
    return [photo, height]


def build_earth_clouds(cache: Path, target: Path) -> dict:
    source = cache / CLOUD_NAME
    if source.stat().st_size > 3_000_000:
        raise RuntimeError("Cloud source exceeds3MB limit")
    image = Image.open(source)
    assert image.size == (2048, 1024), "Unexpected cloud texture dimensions"
    path = target / "earth_clouds_2k.jpg"
    path.write_bytes(source.read_bytes())
    return record(path, dimensions=[2048, 1024],
                  bounds_degrees={"west": -180.0, "east": 180.0, "south": -90.0, "north": 90.0},
                  color_space="grayscale cloud brightness used as coverage, not a calibrated optical-depth measurement",
                  source=CLOUD_NAME, original_nasa_url=CLOUD_ORIGINAL,
                  retrieved_from=CLOUD_ORIGINAL,
                  verified_utc_date="2026-10-30",
                  credit="NASA Goddard Space Flight Center; Reto Stoeckli; Robert Simmon",
                  transformation="Exact NASA download bytes, no resizing or image manipulation",
                  limitation="Historical Blue Marble composite cloud pattern; not current or simulated live weather.")


def build_base_hardware(cache: Path, target: Path, old_sources: dict) -> tuple[list[dict], list[dict]]:
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None
    hardware_dir = target / "base"
    hardware_dir.mkdir(parents=True, exist_ok=True)
    sources = [fetch(cache, name, BASE_SOURCES[name], old_sources.get(name)) for name in BASE_SOURCES]
    sizes = {name: Image.open(cache / name).size for name in BASE_SOURCES}
    outputs = []
    for crop in BASE_CROPS:
        image = Image.open(cache / crop["source"])
        left, top, right, bottom = crop["rect"]
        within = left >= 0 and top >= 0 and right <= sizes[crop["source"]][0] and bottom <= sizes[crop["source"]][1]
        if not within:
            raise RuntimeError("Hardware crop exceeds source bounds: " + crop["output"])
        piece = image.crop(crop["rect"])
        if "exposure normalization" in crop["transformation"]:
            # Keep photographic content identical; only lift display exposure.
            from PIL import ImageEnhance
            piece = ImageEnhance.Brightness(piece).enhance(1.18)
        path = hardware_dir / crop["output"]
        piece.save(path, quality=92, optimize=True)
        entry = record(path, dimensions=list(piece.size), color_space="sRGB",
                       source=crop["source"], subject=crop["subject"],
                       crop_rectangle_pixels=crop["rect"],
                       transformation=crop["transformation"])
        # Keep manifest paths relative to assets/space like every other output.
        entry["file"] = "base/" + path.name
        outputs.append(entry)
    return sources, outputs


def main() -> None:
    global cv2, np, OpenEXR, tifffile, Image
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="Verify shipped outputs without network/conversion")
    parser.add_argument("--wac-only", action="store_true", help="Add/rebuild only the broad Copernicus WAC context and native LOLA crop")
    parser.add_argument("--clouds-only", action="store_true", help="Add/rebuild only the small real Earth cloud map")
    parser.add_argument("--base-only", action="store_true", help="Add/rebuild only the photographed lunar base hardware textures")
    args = parser.parse_args()
    target = ROOT / "assets" / "space"
    cache = ROOT / "build" / "space-sources"
    target.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    # Godot does not honor Git ignore rules when scanning image resources.
    (ROOT / "build" / ".gdignore").touch()
    manifest_path = target / "SOURCE.json"
    previous = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    if args.verify:
        for item in previous["outputs"]:
            assert sha256(target / item["file"]) == item["sha256"], item["file"]
        print(f"Verified {len(previous['outputs'])} offline lunar textures.")
        return
    import cv2
    import numpy as np
    import OpenEXR
    import tifffile
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None
    old_sources = {entry["name"]: entry["sha256"] for entry in previous.get("sources", [])}
    if args.clouds_only:
        assert previous, "Build original assets first"
        source = fetch(cache, CLOUD_NAME, DOWNLOADS[CLOUD_NAME], old_sources.get(CLOUD_NAME))
        output = build_earth_clouds(cache, target)
        previous["sources"] = [item for item in previous["sources"] if item["name"] != CLOUD_NAME] + [source]
        previous["outputs"] = [item for item in previous["outputs"] if item["file"] != output["file"]] + [output]
        previous["documentation"] = list(dict.fromkeys(previous["documentation"] + [CLOUD_DOCUMENTATION]))
        manifest_path.write_text(json.dumps(previous, indent=2) + "\n", encoding="utf-8")
        configure_import(target / output["file"])
        return
    if args.base_only:
        assert previous, "Build original assets first"
        base_sources, base_outputs = build_base_hardware(cache, target, old_sources)
        previous["sources"] = [item for item in previous["sources"] if item["name"] not in BASE_SOURCES] + base_sources
        output_names = {item["file"] for item in base_outputs}
        previous["outputs"] = [item for item in previous["outputs"] if item["file"] not in output_names] + base_outputs
        previous["documentation"] = list(dict.fromkeys(previous["documentation"] + [BASE_DOCUMENTATION]))
        manifest_path.write_text(json.dumps(previous, indent=2) + "\n", encoding="utf-8")
        for item in base_outputs:
            configure_import(target / item["file"])
        return
    if args.wac_only:
        assert previous, "Build original assets first"
        updates = [fetch(cache, name, DOWNLOADS[name], old_sources.get(name)) for name in [WAC_NAME, "ldem_64_uint.tif"]]
        new_outputs = build_wide_context(cache, target)
        previous["sources"] = [item for item in previous["sources"] if item["name"] not in {WAC_NAME, "ldem_64_uint.tif"}] + updates
        output_names = {item["file"] for item in new_outputs}
        previous["outputs"] = [item for item in previous["outputs"] if item["file"] not in output_names] + new_outputs
        previous["documentation"] = list(dict.fromkeys(previous["documentation"] + [WAC_DOCUMENTATION]))
        previous["license_evidence"] = list(dict.fromkeys(previous["license_evidence"] + [WAC_LICENSE]))
        manifest_path.write_text(json.dumps(previous, indent=2) + "\n", encoding="utf-8")
        for item in new_outputs:
            configure_import(target / item["file"])
        return
    sources = [fetch(cache, name, url, old_sources.get(name)) for name, url in DOWNLOADS.items()]
    outputs = []
    global_bounds = {"west": -180.0, "east": 180.0, "north": 90.0, "south": -90.0}
    globe = Image.open(cache / "lroc_color_poles_16k.tif").convert("RGB")
    globe.save(target / "moon_albedo_16k.jpg", quality=95, subsampling=0, optimize=True)
    outputs.append(record(target / "moon_albedo_16k.jpg", dimensions=list(globe.size),
                          bounds_degrees=global_bounds, color_space="sRGB",
                          source="lroc_color_poles_16k.tif",
                          transformation="Original 16384x8192 pixels, JPEG quality95 4:4:4; no resize or sharpening"))
    del globe
    lola = np.asarray(Image.open(cache / "ldem_64_uint.tif"), dtype=np.float32) * 0.5 - 10000.0
    coarse = cv2.resize(lola, (8192, 4096), interpolation=cv2.INTER_AREA)
    packed_height(coarse, target / "moon_height_8k.png")
    outputs.append(record(target / "moon_height_8k.png", dimensions=[8192, 4096],
                          bounds_degrees=global_bounds, color_space="linear data",
                          source="ldem_64_uint.tif", transformation="Area reduction 23040x11520 to8192x4096; RG half-metre packing",
                          height_range_metres=[float(coarse.min()), float(coarse.max())]))
    del coarse
    color_name = "NAC_ROI_COPERNICLOF_E102N3413_5M.TIF"
    region = geo_metadata(cache / color_name)
    bounds = region["bounds_degrees"]
    image = np.asarray(Image.open(cache / color_name))
    width, height = round(image.shape[1] * 8192 / image.shape[0]), 8192
    resized = cv2.resize(image, (width, height), interpolation=cv2.INTER_AREA)
    # Nodata zero wedges are masked separately; real black shadows remain.
    validity = cv2.resize((image != 0).astype(np.uint8), (width, height), interpolation=cv2.INTER_NEAREST)
    distance = cv2.distanceTransform(validity, cv2.DIST_L2, 3)
    mask = np.clip(distance / 12.0, 0.0, 1.0)
    Image.fromarray(resized).save(target / "moon_region_albedo.jpg", quality=96, optimize=True)
    Image.fromarray(np.rint(mask * 255).astype(np.uint8)).save(target / "moon_region_mask.png")
    outputs.append(record(target / "moon_region_albedo.jpg", **region,
                          output_dimensions=[width, height], source=color_name, color_space="sRGB",
                          transformation="Area downsample, JPEG quality96. Actual monochrome low-Sun orthophoto with baked shadows, NOT unlit albedo.",
                          output_metres_per_pixel=5.0 * image.shape[0] / height))
    # region['dimensions'] records the source; use one explicit runtime field.
    outputs[-1]["dimensions"] = [width, height]
    outputs[-1]["source_dimensions"] = region["dimensions"]
    outputs.append(record(target / "moon_region_mask.png", dimensions=[width, height], bounds_degrees=bounds,
                          transformation="Zero/nodata validity, 12pixel feather; no invented photo content"))
    del image, resized, validity, distance, mask
    longitude = np.linspace(bounds["west"], bounds["east"], width, endpoint=False) + (bounds["east"] - bounds["west"]) / (2 * width)
    latitude = np.linspace(bounds["north"], bounds["south"], height, endpoint=False) - (bounds["north"] - bounds["south"]) / (2 * height)
    region_heights = np.empty((height, width), dtype=np.float32)
    for start in range(0, height, 256):
        region_heights[start:start + 256] = sample_raster(lola, global_bounds, longitude, latitude[start:start + 256])
    del lola
    dtm_name = "NAC_DTM_COPRNICUS01.TIF"
    dtm_geo = geo_metadata(cache / dtm_name)
    dtm = np.asarray(Image.open(cache / dtm_name)).copy()
    dtm_valid = (dtm > -10000.0) & (dtm < 20000.0)
    dtm[~dtm_valid] = 0.0
    # Feather only the measured dataset boundary into actual LOLA elevations.
    # This is a presentation blend, not extra measured resolution outside NAC.
    dtm_weight = np.clip(cv2.distanceTransform(dtm_valid.astype(np.uint8), cv2.DIST_L2, 3) / 50.0, 0, 1)
    fine_bounds = dtm_geo["bounds_degrees"]
    inside_x = (longitude >= fine_bounds["west"]) & (longitude <= fine_bounds["east"])
    for start in range(0, height, 256):
        lat = latitude[start:start + 256]
        weights = sample_raster(dtm_weight, fine_bounds, longitude, lat)
        weights *= inside_x[None, :]
        weights *= ((lat >= fine_bounds["south"]) & (lat <= fine_bounds["north"]))[:, None]
        fine = sample_raster(dtm, fine_bounds, longitude, lat)
        block = region_heights[start:start + 256]
        block[:] = block * (1.0 - weights) + fine * weights
    packed_height(region_heights, target / "moon_region_height.png")
    outputs.append(record(target / "moon_region_height.png", dimensions=[width, height], bounds_degrees=bounds,
                          source=["ldem_64_uint.tif", dtm_name], color_space="linear data",
                          fine_dtm=dtm_geo, output_metres_per_pixel=5.0 * 11214 / height,
                          height_range_metres=[float(region_heights.min()), float(region_heights.max())],
                          transformation="LOLA global measured heights, replaced by measured 5m NAC stereo elevations inside valid footprint; 250m boundary feather. Linear resampling and RG half-metre packing.",
                          limitation="Fine stereo relief only within NAC_DTM_COPRNICUS01 valid footprint; elsewhere source LOLA has64pixels/degree (~474m equatorial spacing)."))
    del region_heights, dtm, dtm_valid, dtm_weight
    stars = OpenEXR.File(str(cache / "starmap_2020_8k.exr")).channels()["RGB"].pixels.astype(np.float32)
    # This NASA source is already normalized to linear [0,1]. sRGB transfer
    # preserves its full range; PNG avoids lossy JPEG artifacts around stars.
    assert float(stars.min()) >= 0.0 and float(stars.max()) <= 1.0, "Review HDR source range"
    srgb = np.where(stars <= 0.0031308, stars * 12.92, 1.055 * np.power(stars, 1.0 / 2.4) - 0.055)
    encoded = np.rint(np.clip(srgb, 0.0, 1.0) * 255.0).astype(np.uint8)
    Image.fromarray(encoded).save(target / "stars_8k.png", compress_level=6)
    srgb = encoded.astype(np.float32) / 255.0
    check = np.where(srgb <= 0.04045, srgb / 12.92, np.power((srgb + 0.055) / 1.055, 2.4))
    outputs.append(record(target / "stars_8k.png", dimensions=[8192, 4096], color_space="sRGB",
                          credit="NASA/Goddard Space Flight Center Scientific Visualization Studio; Gaia DR2: ESA/Gaia/DPAC; Ernie Wright (USRA)",
                          source="starmap_2020_8k.exr", transformation="Normalized linear EXR RGB[0,1] transferred to sRGB8 losslessPNG, same8192x4096 pixels; no clipping, exposure adjustment, tonemapping or resizing. Quantization is documented by measured conversion error.",
                          projection="Celestial ICRF/J2000 plate carree, RA0hours at horizontal center, RA increases left, north at top",
                          luminance_sample_percentiles=dict(zip(["min", "p50", "p90", "p99", "p99.9", "max"], map(float, np.percentile(check, [0, 50, 90, 99, 99.9, 100])))),
                          maximum_linear_rgb_quantization_error=float(np.max(np.abs(stars - check)))))
    outputs += build_wide_context(cache, target)
    outputs.append(build_earth_clouds(cache, target))
    manifest = {"title": "Observed Moon and catalog-derived star sky for Chroma-Labyrinth",
                "retrieved_utc_date": "2026-10-29", "offline_runtime": True,
                "reference_moon_radius_metres": RADIUS,
                "height_decode": "metres = (normalized_R *65280 + normalized_G *255) *0.5 -10000; import PNG lossless as linear data (NO source_color)",
                "global_uv": "u=(longitude_degrees+180)/360; v=(90-latitude_degrees)/180",
                "regional_uv": "u=(longitude-west)/(east-west); v=(north-latitude)/(north-south)",
                "sources": sources, "outputs": outputs,
                "documentation": ["https://svs.gsfc.nasa.gov/4720/", "https://svs.gsfc.nasa.gov/4851/",
                                  "https://data.lroc.im-ldi.com/lroc/view_rdr/NAC_ROI_COPERNICLOF",
                                  "https://data.lroc.im-ldi.com/lroc/view_rdr/NAC_DTM_COPRNICUS01", WAC_DOCUMENTATION, CLOUD_DOCUMENTATION],
                "license_evidence": ["https://svs.gsfc.nasa.gov/help/", "https://lroc.im-ldi.com/about/terms", WAC_LICENSE,
                                     "https://www.nasa.gov/nasa-brand-center/images-and-media/"],
                "limitations": ["Visualization assets, not a scientific reconstruction or navigation product.",
                                "The 16k global map has finite resolution; it does not resolve metre-scale rocks.",
                                "The regional photograph includes original sunlight/shadows. It is not a measured reflectance map.",
                                "No generated detail, AI enlargement, invented stars or synthetic craters are included in these assets."]}
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    for item in outputs:
        configure_import(target / item["file"])


if __name__ == "__main__":
    main()
