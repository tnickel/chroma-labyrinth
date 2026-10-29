extends Node
## Small generated PCM loops; playback is handled by the audio server, not a
## per-frame CPU synthesizer. No recordings or external sound files required.
var muted := false
var _engine: AudioStreamPlayer
var _chime: AudioStreamPlayer

func build() -> void:
	_engine = AudioStreamPlayer.new()
	_engine.name = "CabinEngineAmbience"
	_engine.stream = _engine_loop()
	_engine.volume_db = -38.0
	add_child(_engine)
	_chime = AudioStreamPlayer.new()
	_chime.name = "CabinChime"
	_chime.stream = _chime_sample()
	_chime.volume_db = -23.0
	add_child(_chime)

func update_power(power: float, orbital: float, active: bool, delta: float) -> void:
	if active and not muted:
		if not _engine.playing:
			_engine.play()
		var target := lerpf(-31.0, -21.5, power) - orbital * 4.0
		_engine.volume_db = lerpf(_engine.volume_db, target, 1.0 - exp(-delta * 3.0))
		_engine.pitch_scale = lerpf(0.72, 1.18, power)
	elif _engine.playing:
		_engine.stop()

func chime() -> void:
	if not muted:
		_chime.play()

func _engine_loop() -> AudioStreamWAV:
	const RATE := 22050
	const COUNT := RATE * 2
	const BLEND := 256
	var values := PackedFloat32Array()
	values.resize(COUNT)
	var random := RandomNumberGenerator.new()
	random.seed = 117042
	var filtered := 0.0
	for index in COUNT:
		var time := float(index) / RATE
		filtered = lerpf(filtered, random.randf_range(-1.0, 1.0), 0.14)
		values[index] = filtered * 0.75 + sin(time * TAU * 62.0) * 0.15 + sin(time * TAU * 124.0) * 0.055
	for index in BLEND:
		values[COUNT - BLEND + index] = lerpf(values[COUNT - BLEND + index], values[index], float(index) / float(BLEND - 1))
	var stream := _pcm(values, RATE)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = BLEND
	stream.loop_end = COUNT
	return stream

func _chime_sample() -> AudioStreamWAV:
	const RATE := 22050
	var values := PackedFloat32Array()
	values.resize(RATE)
	for index in values.size():
		var t := float(index) / RATE
		var first := sin(t * TAU * 660.0) * exp(-t * 7.0) * smoothstep(0.0, 0.01, t)
		var second_time := maxf(0.0, t - 0.22)
		var second := sin(second_time * TAU * 880.0) * exp(-second_time * 7.0) * smoothstep(0.0, 0.01, second_time)
		values[index] = (first + second) * 0.25 * (1.0 - smoothstep(0.9, 1.0, t))
	return _pcm(values, RATE)

func _pcm(values: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 2)
	for index in values.size():
		bytes.encode_s16(index * 2, int(clampf(values[index], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
