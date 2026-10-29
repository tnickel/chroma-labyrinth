extends RefCounted
## Authoring coordinates describe the original 66 x 66 m footprint.
## Only horizontal distances grow: sqrt(1.5)^2 = 50% additional floor area.
## Geometry/physics nodes remain unscaled; positions and dimensions are baked.
const AREA_MULTIPLIER := 1.5
const HORIZONTAL_SCALE := sqrt(AREA_MULTIPLIER)
const FLOOR_HEIGHT := 6.0
const FLOOR_COUNT := 3
const GRID_COUNT := 11
const CELL_SIZE := 6.0 * HORIZONTAL_SCALE
const FOOTPRINT_WIDTH := CELL_SIZE * GRID_COUNT
const RAMP_RUN := 18.0 * HORIZONTAL_SCALE

static func to_world(design: Vector3) -> Vector3:
	return Vector3(design.x * HORIZONTAL_SCALE, design.y, design.z * HORIZONTAL_SCALE)

static func to_design(world: Vector3) -> Vector3:
	return Vector3(world.x / HORIZONTAL_SCALE, world.y, world.z / HORIZONTAL_SCALE)

static func ramp_angle() -> float:
	return atan2(FLOOR_HEIGHT, RAMP_RUN)
