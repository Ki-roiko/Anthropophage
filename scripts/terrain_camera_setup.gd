extends Node
## Явно указываем Terrain3D камеру игрока.
## Игрок создаётся из отдельной PackedScene, поэтому Terrain3D не всегда
## может самостоятельно обнаружить вложенную Camera3D через активный Viewport.

func _ready() -> void:
	var world := get_parent()
	var terrain := world.get_node_or_null("terrain/Terrain3D")
	var camera := world.get_node_or_null("player/Head/Camera3D") as Camera3D

	if terrain == null:
		push_error("TerrainCameraSetup: не найден узел terrain/Terrain3D.")
		return

	if camera == null:
		push_error("TerrainCameraSetup: не найдена камера player/Head/Camera3D.")
		return

	# Указываем одну и ту же цель для LOD-сетки и динамических коллизий.
	terrain.set("clipmap_target", camera)
	terrain.set("collision_target", camera)

	# Также задаём основную камеру Terrain3D через его публичный API.
	terrain.call("set_camera", camera)
