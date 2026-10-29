extends RefCounted
const Geometry = preload("res://scripts/airport/CabinMesh.gd")
## Parts are in seat-floor coordinates, with the passenger facing -Z. The
## loaded seat anchor stays at x=0/y=0 and its cushion contact height is 0.53 m.

static func meshes() -> Dictionary:
	return {
		"shell": Geometry.rounded_volume(Vector3(0.555,0.92,0.035),0.015,_shell),
		"back": Geometry.rounded_volume(Vector3(0.525,0.87,0.10),0.045,_back),
		"insert": Geometry.rounded_volume(Vector3(0.355,0.66,0.025),0.011,_insert),
		"pan": Geometry.rounded_volume(Vector3(0.57,0.075,0.65),0.033,_pan),
		"cushion": Geometry.rounded_volume(Vector3(0.535,0.105,0.62),0.045,_cushion),
		"headrest": Geometry.rounded_volume(Vector3(0.405,0.205,0.10),0.045,_headrest),
		"arm": Geometry.rounded_volume(Vector3(0.060,0.047,0.52),0.021,_arm)
	}

static func _back(p: Vector3) -> Vector3:
	var t := (p.y+0.435)/0.87
	var u := p.x/0.2625
	var waist := 0.88+0.12*sin(clampf(t,0,1)*PI)
	var lumbar := 0.035*exp(-pow((t-0.28)/0.20,2.0))
	var bolster := 0.055*pow(absf(u),2.4)*sin(clampf(t,0,1)*PI)
	return Vector3(p.x*waist,p.y+0.975-0.038*pow(absf(u),3.0)*smoothstep(0.72,1.0,t),
		p.z+0.25+0.18*t-lumbar*(1.0-u*u)-bolster)

static func _shell(p: Vector3) -> Vector3:
	var t := (p.y+0.46)/0.92
	var u := p.x/0.2775
	var lumbar := 0.035*exp(-pow((t-0.28)/0.20,2.0))
	return Vector3(p.x*(0.88+0.12*sin(clampf(t,0,1)*PI)),
		p.y+0.98-0.036*pow(absf(u),3.0)*smoothstep(0.72,1.0,t),
		p.z+0.315+0.18*t-lumbar*(1.0-u*u)-0.055*pow(absf(u),2.4)*sin(clampf(t,0,1)*PI))

static func _insert(p: Vector3) -> Vector3:
	var y := p.y+0.97
	var t := (y-0.54)/0.87
	var u := p.x/0.2625
	var lumbar := 0.035*exp(-pow((t-0.28)/0.20,2.0))
	return Vector3(p.x*(0.88+0.12*sin(t*PI)),y,
		p.z+0.194+0.18*t-lumbar*(1.0-u*u)-0.055*pow(absf(u),2.4)*sin(t*PI))

static func _pan(p: Vector3) -> Vector3:
	var rear := smoothstep(-0.2,0.325,p.z)
	return Vector3(p.x*(1.0-rear*0.08),p.y+0.421+0.015*pow(p.x/0.285,2),p.z-0.02)

static func _cushion(p: Vector3) -> Vector3:
	var u := p.x/0.2675
	var v := p.z/0.31
	var basin := 0.024*u*u*(1.0-v*v)-0.010
	var waterfall := -0.022*smoothstep(0.18,0.31,-p.z)
	return Vector3(p.x*(1.0-0.09*smoothstep(-0.1,0.31,p.z)),p.y+0.4875+basin+waterfall,p.z-0.02)

static func _headrest(p: Vector3) -> Vector3:
	var u := p.x/0.2025
	return Vector3(p.x*(1.0-0.05*(p.y/0.1025)),p.y+1.385,
		p.z+0.398-0.073*pow(absf(u),2.5))

static func _arm(p: Vector3) -> Vector3:
	return Vector3(p.x,p.y-0.018*smoothstep(0.10,0.26,-p.z),p.z)
