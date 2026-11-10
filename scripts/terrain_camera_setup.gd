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

	# Указываем камеру как цель клипмапа. Полная игровая коллизия задана
	# непосредственно в сцене Terrain3D и не зависит от позиции камеры.
	terrain.set("clipmap_target", camera)

	# Также задаём основную камеру Terrain3D через его публичный API.
	terrain.call("set_camera", camera)
	# В Terrain3D 1.0.2 это публичный способ пересобрать shapes после
	# назначения режима и камеры; он не создаёт стороннюю геометрию.
	var collision = terrain.get("collision")
	if collision != null and collision.has_method("update"):
		collision.call("update", true)
