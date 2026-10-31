extends RefCounted
const Terrain = preload("res://scripts/airport/MarsTerrain.gd")
## Fictional, time-compressed Mars journey with a natural transfer sky,
## a stylized canyon flyover and Ares Base landing.
## Durations and interpolation are staging choices, not orbital mechanics.
enum Phase { DOORS, TAXI, TAKEOFF, CLIMB, CLOUDS, EARTH_ORBIT, OUTBOUND,
	LUNAR_APPROACH, LOW_PASS, BASE_ORBIT, BASE_CLOSE, BASE_LANDING, BASE_SURFACE, BASE_DEPART,
	EARTHRISE, HOMEBOUND, REENTRY, DESCENT, APPROACH, LANDING, DOCK }

const DURATIONS := [4.0, 8.0, 12.0, 24.0, 18.0, 40.0, 110.0, 48.0,
	160.0, 34.0, 42.0, 34.0, 45.0, 28.0, 60.0, 100.0, 34.0, 30.0, 22.0, 12.0, 6.0]
const PHASES := [
	"TÜREN SCHLIESSEN", "ROLLEN", "START", "STEIGFLUG",
	"ÜBER DEN WOLKEN", "ERDE / ORBITALPANORAMA",
	"MARSTRANSFER / ERDE & STERNENHIMMEL",
	"MARS-ANFLUG / ROTER PLANET",
	"MARS-ÜBERFLUG / VALLES MARINERIS & JEZERO",
	"MARSBASIS / CANYON-ORBITALPANORAMA",
	"MARSBASIS / TIEFFLUG ARES-KOLONIE",
	"MARSBASIS / LANDEANFLUG",
	"MARSBASIS / GELANDET",
	"MARSBASIS / AUFSTIEG",
	"MARS-HORIZONT / FERNE ERDE",
	"RÜCKREISE ZUR ERDE", "WIEDEREINTRITT", "SINKFLUG", "LANDEANFLUG",
	"LANDUNG", "ANDOCKEN"
]
const MARS_FAR_ALTITUDE := 376291600.0
const EARTH_MARS_ALTITUDE := 376291600.0
const LANDED_SITE_HEIGHT := Terrain.CABIN_FLOOR_HEIGHT
const KEYS := ["earth_altitude", "speed", "transfer", "lunar_altitude", "orbit_angle", "lunar_mix", "landing_blend"]

const POINTS := [
	[0.0, 0.0, 0.0, MARS_FAR_ALTITUDE, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, MARS_FAR_ALTITUDE, 0.0, 0.0, 0.0],
	[0.0, 18.0, 0.0, MARS_FAR_ALTITUDE, 0.0, 0.0, 0.0],
	[900.0, 150.0, 0.0, MARS_FAR_ALTITUDE, 0.0, 0.0, 0.0],
	[4200.0, 320.0, 0.0, MARS_FAR_ALTITUDE, 0.0, 0.0, 0.0],
	[6500.0, 850.0, 0.0, MARS_FAR_ALTITUDE, 0.0, 0.0, 0.0],
	[120000.0, 850.0, 0.0, MARS_FAR_ALTITUDE, 0.0, 0.0, 0.0],
	[EARTH_MARS_ALTITUDE - 1200000.0, 950.0, 0.96, 1200000.0, 0.0, 0.0, 0.0],
	[EARTH_MARS_ALTITUDE - 15000.0, 520.0, 1.0, 15000.0, 0.0, 1.0, 0.0],
	[EARTH_MARS_ALTITUDE - 15000.0, 480.0, 1.0, 15000.0, 0.09, 1.0, 0.0],
	[EARTH_MARS_ALTITUDE - 4500.0, 240.0, 1.0, 4500.0, 0.09, 1.0, 0.0],
	[EARTH_MARS_ALTITUDE - 1600.0, 145.0, 1.0, 1600.0, 0.09, 1.0, 0.0],
	[EARTH_MARS_ALTITUDE - LANDED_SITE_HEIGHT, 0.0, 1.0, LANDED_SITE_HEIGHT, 0.09, 1.0, 1.0],
	[EARTH_MARS_ALTITUDE - LANDED_SITE_HEIGHT, 0.0, 1.0, LANDED_SITE_HEIGHT, 0.09, 1.0, 1.0],
	[EARTH_MARS_ALTITUDE - 15000.0, 460.0, 1.0, 15000.0, 0.09, 1.0, 0.0],
	[EARTH_MARS_ALTITUDE - 120000.0, 900.0, 1.0, 120000.0, 0.14, 1.0, 0.0],
	[120000.0, 900.0, 0.0, MARS_FAR_ALTITUDE, 0.18, 0.0, 0.0],
	[35000.0, 650.0, 0.0, MARS_FAR_ALTITUDE, 0.18, 0.0, 0.0],
	[7000.0, 220.0, 0.0, MARS_FAR_ALTITUDE, 0.18, 0.0, 0.0],
	[180.0, 90.0, 0.0, MARS_FAR_ALTITUDE, 0.18, 0.0, 0.0],
	[0.0, 0.0, 0.0, MARS_FAR_ALTITUDE, 0.18, 0.0, 0.0],
	[0.0, 0.0, 0.0, MARS_FAR_ALTITUDE, 0.18, 0.0, 0.0]
]

static func total_duration() -> float:
	var total := 0.0
	for duration: float in DURATIONS:
		total += duration
	return total

static func phase_start(index: int) -> float:
	var seconds := 0.0
	for phase in range(clampi(index, 0, DURATIONS.size())):
		seconds += DURATIONS[phase]
	return seconds

static func sample(index: int, fraction: float) -> Dictionary:
	index = clampi(index, 0, DURATIONS.size() - 1)
	var result := interpolate(_point(index), _point(index + 1), fraction)
	if index == Phase.LOW_PASS:
		# Deep canyon flyover across Valles Marineris & Candor Chasma
		var close_pass := smoothstep(0.0, 0.22, fraction) * (1.0 - smoothstep(0.78, 1.0, fraction))
		result.lunar_altitude = lerpf(15000.0, 3800.0, close_pass)
		result.earth_altitude = EARTH_MARS_ALTITUDE - float(result.lunar_altitude)
	if index == Phase.BASE_LANDING:
		# Touch down before stopping: the last 22% rolls along the cleared strip.
		var touchdown := interpolate(_point(index), _point(index + 1), fraction / 0.78)
		result.lunar_altitude = touchdown.lunar_altitude
		result.earth_altitude = EARTH_MARS_ALTITUDE - float(result.lunar_altitude)
		# Align above every scenic mesa before descending into the colony.
		# Touchdown and the short forward rollout occupy the cleared north apron.
		var approach_south := deg_to_rad(0.024) * Terrain.RADIUS
		var touchdown_south := Terrain.PARK_POSITION.z + 12.0
		var south := lerpf(approach_south, touchdown_south, smoothstep(0.0, 0.22, fraction))
		south = lerpf(south, Terrain.PARK_POSITION.z, smoothstep(0.78, 1.0, fraction))
		result["mars_ground_position"] = Vector2(0.0, south)
	elif index == Phase.BASE_SURFACE:
		result["mars_ground_position"] = Vector2(Terrain.PARK_POSITION.x, Terrain.PARK_POSITION.z)
	elif index == Phase.BASE_DEPART:
		# Climb clear of buildings and mesas before moving across the colony.
		var south := lerpf(Terrain.PARK_POSITION.z, deg_to_rad(0.024) * Terrain.RADIUS,
			smoothstep(220.0, 1200.0, float(result.lunar_altitude)))
		result["mars_ground_position"] = Vector2(0.0, south)
	result["settlement_leg"] = index >= Phase.BASE_ORBIT and index <= Phase.BASE_DEPART
	result["returning"] = index >= Phase.HOMEBOUND
	result["mars_mode"] = 1.0
	result["phase_index"] = index
	result["phase_fraction"] = clampf(fraction, 0.0, 1.0)
	return result

static func interpolate(a: Dictionary, b: Dictionary, fraction: float) -> Dictionary:
	var t := clampf(fraction, 0.0, 1.0)
	var weight := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	var result: Dictionary = {}
	for key: String in KEYS:
		if key == "lunar_altitude":
			result[key] = exp(lerpf(log(maxf(a[key], 1.0)), log(maxf(b[key], 1.0)), weight))
		else:
			result[key] = lerpf(a[key], b[key], weight)
	return result

static func return_sample(origin: Dictionary, fraction: float) -> Dictionary:
	var destination := _point(Phase.HOMEBOUND + 1)
	destination.orbit_angle = float(origin.orbit_angle) + 0.04
	var result := interpolate(origin, destination, fraction)
	if origin.has("mars_ground_position"):
		# An abort initially preserves the exact touchdown/approach position;
		# horizontal departure waits until the aircraft clears the local mesas.
		var position: Vector2 = origin.mars_ground_position
		var weight := smoothstep(maxf(float(origin.lunar_altitude), 220.0), maxf(float(origin.lunar_altitude) + 1000.0, 1200.0), float(result.lunar_altitude))
		var geographic_south := deg_to_rad(0.024) * Terrain.RADIUS
		result["mars_ground_position"] = position.lerp(Vector2(0.0, geographic_south), weight)
	result["returning"] = true
	result["mars_mode"] = 1.0
	result["phase_index"] = Phase.HOMEBOUND
	result["phase_fraction"] = clampf(fraction, 0.0, 1.0)
	result["settlement_leg"] = bool(origin.get("settlement_leg", false)) and float(result.lunar_altitude) < 24000.0
	return result

static func _point(index: int) -> Dictionary:
	var result: Dictionary = {}
	for key_index in KEYS.size():
		result[KEYS[key_index]] = float(POINTS[index][key_index])
	return result

static func viewing_hint(index: int) -> String:
	match index:
		Phase.EARTH_ORBIT:
			return "Glasboden: Erdkrümmung  ·  Aufbruch zum Roten Planeten"
		Phase.OUTBOUND:
			return "Erde im Rückblick · Mars voraus · freier Sternenhimmel aus der Heckkuppel"
		Phase.LUNAR_APPROACH:
			return "Heckkuppel: Der Rote Planet wächst am Horizont · zeitgeraffte Inszenierung"
		Phase.LOW_PASS:
			return "Glasboden: Mars-Überflug über Valles Marineris & Canyons"
		Phase.BASE_ORBIT:
			return "Rundblick: Futuristische Marsbasis Ares Vallis im Canyon"
		Phase.BASE_CLOSE:
			return "Glasboden: Tera-Glaskuppeln, Starship-Türme & Mars-Rover"
		Phase.BASE_LANDING:
			return "Landeanflug: Aufsetzen auf dem roten Mars-Landefeld"
		Phase.BASE_SURFACE:
			return "Gelandet auf dem Mars: Mit B zur Marsbasis wechseln"
		Phase.BASE_DEPART:
			return "Heckkuppel: Rückblick auf die Ares-Marskolonie"
		Phase.EARTHRISE:
			return "Heckkuppel: Der rostrote Marshorizont · Aufbruch zur Erde"
		Phase.HOMEBOUND:
			return "Rückreise zur Erde · Mars im Rückblick · freier Sternenhimmel"
		_:
			return "Fenster, Glasboden und 360°-Panoramakuppel frei erkunden"
