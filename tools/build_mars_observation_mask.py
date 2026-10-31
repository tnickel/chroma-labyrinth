#!/usr/bin/env python3
"""Mark the border-connected black gaps in the NASA panorama.

The original photograph is unchanged. The separate low-resolution mask keeps
dark rocks and rover parts opaque, and supplies sky/ground boundary samples
for filling only the regions the source mosaic did not photograph.
"""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets/space/mars_observation"


def main() -> None:
    Image.MAX_IMAGE_PIXELS = None
    with Image.open(ROOT / "gediz_vallis_360.jpg") as image:
        width = 3500
        height = round(image.height * width / image.width)
        small = np.asarray(image.convert("RGB").resize((width, height), Image.Resampling.BOX))
    # All excluded areas touch an image edge. Connected-component selection
    # prevents black shadows and dark rover hardware inside the photo from
    # being mistaken for an empty background.
    dark = (small.max(axis=2) <= 6).astype(np.uint8)
    _, labels = cv2.connectedComponents(dark, connectivity=8)
    border = np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
    border = border[border != 0]
    missing = np.isin(labels, border)
    valid = (~missing).astype(np.uint8) * 255
    # Fade well inside the valid sky/ground before reaching JPEG's black tile
    # margins, which would otherwise leave a dark saw-tooth halo.
    inset = cv2.erode(valid, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (35, 35)))
    softened = cv2.GaussianBlur(inset, (0, 0), sigmaX=15.0, sigmaY=15.0)
    Image.fromarray(softened).save(ROOT / "gediz_coverage.png", optimize=True)
    top = np.argmax(valid > 0, axis=0)
    bottom = height - 1 - np.argmax((valid > 0)[::-1], axis=0)
    edges = np.zeros((1, width, 3), dtype=np.uint8)
    edges[0, :, 0] = np.rint(top / (height - 1) * 255).astype(np.uint8)
    edges[0, :, 1] = np.rint(bottom / (height - 1) * 255).astype(np.uint8)
    Image.fromarray(edges).save(ROOT / "gediz_edges.png", optimize=True)

    # Sample the real sky close to the upper image edge, reject non-sky dark
    # or strongly chromatic pixels, then interpolate and smooth horizontally.
    # A smooth color strip avoids stretching individual pixels into bands.
    sample_y = np.minimum(top + 20, height - 1)
    columns = np.arange(width)
    sky_samples = small[sample_y, columns].astype(np.float32)
    sample_min = sky_samples.min(axis=1)
    sample_max = sky_samples.max(axis=1)
    good = (sample_min > 65) & ((sample_max - sample_min) < 70) & (valid[sample_y, columns] > 0)
    good_indices = columns[good]
    if len(good_indices) < width // 10:
        raise RuntimeError("Could not identify enough sky pixels at the photographed edge")
    extended_indices = np.concatenate((good_indices - width, good_indices, good_indices + width))
    sky = np.empty((width, 3), dtype=np.float32)
    for channel in range(3):
        values = np.tile(sky_samples[good_indices, channel], 3)
        sky[:, channel] = np.interp(columns, extended_indices, values)
    padded = np.pad(sky, ((240, 240), (0, 0)), mode="wrap")[None, :, :]
    smoothed = cv2.GaussianBlur(padded, (0, 0), sigmaX=70.0, sigmaY=1.0)[0, 240:-240]
    Image.fromarray(np.clip(np.rint(smoothed), 0, 255).astype(np.uint8)[None, :, :]).save(
        ROOT / "gediz_sky.png", optimize=True
    )
    print(f"Mask: {width}x{height}; missing {100.0 * missing.mean():.1f}%; sky samples {100.0 * good.mean():.1f}%")


if __name__ == "__main__":
    main()
