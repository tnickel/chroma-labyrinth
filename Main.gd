extends Node3D

## Baut die Anwendung aus unabhängigen Komponenten zusammen.
const Labyrinth = preload("res://scripts/LabyrinthGenerator.gd")
const PlayerScene = preload("res://Player.tscn")
const VisitorCrowd = preload("res://scripts/VisitorCrowd.gd")
const GalleryEnvironment = preload("res://scripts/GalleryEnvironment.gd")
const Layout = preload("res://scripts/LabyrinthLayout.gd")
const Atrium = preload("res://scripts/ChromaAtrium.gd")
const Showcase = preload("res://scripts/ShowcaseDirector.gd")
const Thresholds = preload("res://scripts/GalleryThresholds.gd")
const Worlds = preload("res://scripts/ExperienceWorlds.gd")
const Response = preload("res://scripts/ExperienceResponse.gd")
const ReflectingFloor = preload("res://scripts/NocturneReflectingFloor.gd")
const Airport = preload("res://scripts/airport/AirportSystem.gd")

## Unique build marker of the station redesign. The launch log answers the
## only question that matters when something looks stale: WHICH code ran?
const STATION_VERSION := "2026-10-30-photoreal-2"

func _ready() -> void:
	_log_launch()
	_create_environment()
	var labyrinth = Labyrinth.new()
	labyrinth.name = "Labyrinth"
	add_child(labyrinth)
	var atrium := Atrium.new()
	labyrinth.add_child(atrium)
	atrium.build()
	var thresholds := Thresholds.new()
	labyrinth.add_child(thresholds)
	thresholds.build(labyrinth)
	var worlds := Worlds.new()
	labyrinth.add_child(worlds)
	worlds.build(labyrinth)
	var reflecting_floor := ReflectingFloor.new()
	labyrinth.add_child(reflecting_floor)
	reflecting_floor.build(labyrinth.get_world_3d())
	var player = PlayerScene.instantiate()
	player.name = "Player"
	player.position = Layout.to_world(Vector3(0, 0.15, 7.2))
	add_child(player)
	player.head.rotation.x = 0.34
	var response := Response.new()
	add_child(response)
	response.configure(worlds, player)
	var crowd = VisitorCrowd.new()
	crowd.name = "Visitors"
	crowd.navigation = labyrinth
	crowd.observer = player
	add_child(crowd)
	var showcase := Showcase.new()
	add_child(showcase)
	showcase.configure(player)
	var airport := Airport.new()
	add_child(airport)
	airport.build(player, showcase)

func _create_environment() -> void:
	GalleryEnvironment.build(self)

## Append an unmistakable version line to user://launch.log, so every start —
## no matter which shortcut produced it — is documented and verifiable.
func _log_launch() -> void:
	var stamp := Time.get_datetime_string_from_system(true).replace("T", " ")
	var line := "[%s] version=%s gpu=%s" % [stamp, STATION_VERSION,
		RenderingServer.get_video_adapter_name()]
	print("CHROMA_LAUNCH ", line)
	var file := FileAccess.open("user://launch.log", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("user://launch.log", FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(line)
		file.close()
