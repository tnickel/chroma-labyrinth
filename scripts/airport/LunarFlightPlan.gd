extends RefCounted
## A time-compressed sightseeing itinerary, not an orbital mechanics model.
## Distances are metres, route_angle parameterizes the close Copernicus sweep.
## Keeping the plan pure allows checking every boundary without loading 3D art.
enum Phase { DOORS, TAXI, TAKEOFF, CLIMB, CLOUDS, EARTH_ORBIT, OUTBOUND,
	LUNAR_APPROACH, LOW_PASS, EARTHRISE, HOMEBOUND, REENTRY, DESCENT,
	APPROACH, LANDING, DOCK }

const DURATIONS := [4.0, 8.0, 12.0, 24.0, 18.0, 44.0, 100.0, 45.0,
	150.0, 65.0, 100.0, 34.0, 30.0, 22.0, 12.0, 6.0]
const PHASES := ["TÜREN SCHLIESSEN", "ROLLEN", "START", "STEIGFLUG",
	"ÜBER DEN WOLKEN", "ERDE / ORBITALPANORAMA", "TRANSIT ZUM MOND",
	"ANFLUG / COPERNICUS", "MOND / KRATERPANORAMA", "ERDAUFGANG",
	"RÜCKREISE ZUR ERDE", "WIEDEREINTRITT", "SINKFLUG", "LANDEANFLUG",
	"LANDUNG", "ANDOCKEN"]
const MOON_DISTANCE := 384400000.0
const LUNAR_FAR_ALTITUDE := 376291600.0
const EARTH_LUNAR_ALTITUDE := 376291600.0
const KEYS := ["earth_altitude", "speed", "transfer", "lunar_altitude", "orbit_angle", "lunar_mix"]
# Endpoints: Earth altitude, visual travel speed, transfer, lunar altitude,
# lunar route angle, lunar lighting/view blend. Shared endpoints are deliberate.
const POINTS := [
	[0.0, 0.0, 0.0, LUNAR_FAR_ALTITUDE, 0.0, 0.0],
	[0.0, 0.0, 0.0, LUNAR_FAR_ALTITUDE, 0.0, 0.0],
	[0.0, 18.0, 0.0, LUNAR_FAR_ALTITUDE, 0.0, 0.0],
	[900.0, 150.0, 0.0, LUNAR_FAR_ALTITUDE, 0.0, 0.0],
	[4200.0, 320.0, 0.0, LUNAR_FAR_ALTITUDE, 0.0, 0.0],
	[6500.0, 850.0, 0.0, LUNAR_FAR_ALTITUDE, 0.0, 0.0],
	[120000.0, 850.0, 0.0, LUNAR_FAR_ALTITUDE, 0.0, 0.0],
	[EARTH_LUNAR_ALTITUDE - 1200000.0, 850.0, 0.96, 1200000.0, 0.0, 0.0],
	[EARTH_LUNAR_ALTITUDE - 15000.0, 450.0, 1.0, 15000.0, 0.0, 1.0],
	[EARTH_LUNAR_ALTITUDE - 15000.0, 450.0, 1.0, 15000.0, 0.09, 1.0],
	[EARTH_LUNAR_ALTITUDE - 120000.0, 850.0, 1.0, 120000.0, 0.14, 1.0],
	[120000.0, 850.0, 0.0, LUNAR_FAR_ALTITUDE, 0.18, 0.0],
	[35000.0, 650.0, 0.0, LUNAR_FAR_ALTITUDE, 0.18, 0.0],
	[7000.0, 220.0, 0.0, LUNAR_FAR_ALTITUDE, 0.18, 0.0],
	[180.0, 90.0, 0.0, LUNAR_FAR_ALTITUDE, 0.18, 0.0],
	[0.0, 0.0, 0.0, LUNAR_FAR_ALTITUDE, 0.18, 0.0],
	[0.0, 0.0, 0.0, LUNAR_FAR_ALTITUDE, 0.18, 0.0]
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
		# The real high-resolution stereo strip is worth a slow, low pass.
		# Remain above even its highest relief and ease back to the shared
		# endpoint for a continuous climb into the Earthrise sequence.
		var close_pass := smoothstep(0.0, 0.25, fraction) * (1.0 - smoothstep(0.75, 1.0, fraction))
		result.lunar_altitude = lerpf(15000.0, 5000.0, close_pass)
		result.earth_altitude = EARTH_LUNAR_ALTITUDE - float(result.lunar_altitude)
	result["returning"] = index >= Phase.HOMEBOUND
	return result

static func interpolate(a: Dictionary, b: Dictionary, fraction: float) -> Dictionary:
	var t := clampf(fraction, 0.0, 1.0)
	# Quintic easing makes position and its first two derivatives continuous.
	var weight := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	var result: Dictionary = {}
	for key: String in KEYS:
		if key == "lunar_altitude":
			# Log distance gives the approach time to reveal the lunar disc;
			# linear millions-of-metres interpolation rushes all detail at the end.
			result[key] = exp(lerpf(log(maxf(a[key], 1.0)), log(maxf(b[key], 1.0)), weight))
		else:
			result[key] = lerpf(a[key], b[key], weight)
	return result

static func return_sample(origin: Dictionary, fraction: float) -> Dictionary:
	var destination := _point(Phase.HOMEBOUND + 1)
	# The return begins exactly where L was pressed, including the terrain
	# track. Preserve forward drift instead of snapping to the planned end.
	destination.orbit_angle = float(origin.orbit_angle) + 0.04
	var result := interpolate(origin, destination, fraction)
	result["returning"] = true
	return result

static func _point(index: int) -> Dictionary:
	var result: Dictionary = {}
	for key_index in KEYS.size():
		result[KEYS[key_index]] = float(POINTS[index][key_index])
	return result

static func viewing_hint(index: int) -> String:
	match index:
		Phase.EARTH_ORBIT:
			return "Glasboden: Erdkrümmung  ·  Glasdach: Sternhimmel"
		Phase.OUTBOUND:
			return "Heckkuppel: Der Mond kommt näher"
		Phase.LUNAR_APPROACH:
			return "Heckkuppel: Kraterränder und Mondhorizont"
		Phase.LOW_PASS:
			return "Glasboden: Copernicus-Region  ·  Heck: Horizont"
		Phase.EARTHRISE:
			return "Heckkuppel: Erde über dem Mondhorizont"
		Phase.HOMEBOUND:
			return "Rückreise: Die Erde wird wieder größer"
		_:
			return "Fenster, Glasboden und Heckkuppel frei erkunden"
