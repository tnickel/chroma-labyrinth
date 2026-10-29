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

func _ready() -> void:
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
