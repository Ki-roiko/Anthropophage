extends Node
## Явно указываем Terrain3D камеру игрока.
## Игрок создаётся из отдельной PackedScene, поэтому Terrain3D не всегда
## может самостоятельно обнаружить вложенную Camera3D через активный Viewport.

func _ready() -> void:
	# Этот узел запускается после создания World и связывает Terrain3D с камерой
	# игрока. Без связи Terrain3D может строить clipmap и динамические области
	# коллизий вокруг другой камеры или вообще не получить цель слежения.
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
	# clipmap_target отвечает за область визуальных данных Terrain3D вокруг игрока.
	terrain.set("clipmap_target", camera)

	# Также задаём основную камеру Terrain3D через его публичный API.
	# set_camera — публичный API установленной Terrain3D 1.0.2.
	terrain.call("set_camera", camera)
	# В Terrain3D 1.0.2 это публичный способ пересобрать shapes после
	# назначения режима и камеры; он не создаёт стороннюю геометрию.
	var collision = terrain.get("collision")
	# update(true) заставляет Terrain3D пересобрать физические shapes уже после
	# назначения камеры. Вызов использует реальную сигнатуру Terrain3D 1.0.2.
	if collision != null and collision.has_method("update"):
		collision.call("update", true)
