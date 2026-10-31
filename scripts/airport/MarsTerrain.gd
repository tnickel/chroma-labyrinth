extends RefCounted
## Scenic Mars frame. The shipped height maps are generated from image colour,
## not surveyed altimetry; the colony and its approach are deliberately graded.
const RADIUS := 3396200.0
const SITE_LATITUDE := -10.0
const SITE_LONGITUDE := -70.0
const REGION := Vector4(-78.0, -18.0, -62.0, -2.0)
const HEIGHT_PATH := "res://assets/space/mars/mars_height_4k.png"
const REGION_HEIGHT_PATH := "res://assets/space/mars/mars_region_height.png"
const PARK_POSITION := Vector3(0.0, 0.0, -70.0)
const CORRIDOR := Rect2(-28.0, -1600.0, 56.0, 1580.0)
const FIELD_RADIUS := 650.0
const FIELD_BLEND := 2000.0
const CABIN_FLOOR_HEIGHT := 3.2 # Gear centres -2.8 m, tyre radius 0.4 m.

static func site_elevation() -> float:
	var texture := load(REGION_HEIGHT_PATH) as Texture2D
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	var uv := Vector2((SITE_LONGITUDE - REGION.x) / (REGION.z - REGION.x),
		(REGION.w - SITE_LATITUDE) / (REGION.w - REGION.y))
	var pixel := uv * Vector2(image.get_size()) - Vector2(0.5, 0.5)
	var low := Vector2i(pixel.floor())
	var weight := pixel - Vector2(low)
	var top := image.get_pixel(low.x, low.y).lerp(image.get_pixel(low.x + 1, low.y), weight.x)
	var bottom := image.get_pixel(low.x, low.y + 1).lerp(image.get_pixel(low.x + 1, low.y + 1), weight.x)
	var packed := top.lerp(bottom, weight.y)
	return (packed.r * 65280.0 + packed.g * 255.0) * 0.5 - 10000.0
