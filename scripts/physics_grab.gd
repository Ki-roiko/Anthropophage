extends Node
## Физический захват RigidBody3D: тянем точку контакта пружинной силой.
## Запросы к физическому миру выполняются только в _physics_process.

@export_range(0.1, 100.0, 0.1) var max_grab_mass: float = 10.0
@export_range(0.5, 8.0, 0.1) var grab_distance: float = 3.5
@export_range(0.5, 5.0, 0.1) var hold_distance: float = 2.0
@export_range(1.0, 100.0, 1.0) var spring_strength: float = 34.0
@export_range(0.0, 30.0, 0.5) var damping: float = 9.0
@export_range(10.0, 1000.0, 5.0) var max_force: float = 220.0
@export_flags_3d_physics var grab_collision_mask: int = 0xFFFFFFFF
@export var debug_logging: bool = false

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var camera: Camera3D = player.get_node("Head/Camera3D") as Camera3D
@onready var inventory_ui: InventoryUIController = player.get_node("HUD/InventoryUI") as InventoryUIController

var _grab_request_pending: bool = false
var _grabbed_body: RigidBody3D
var _local_grab_offset: Vector3
var _current_hold_distance: float = 2.0
# Запрос захвата откладывается до physics_process, чтобы читать физический мир
# в разрешённый момент и не менять RigidBody3D из обработчика мыши.


func _unhandled_input(event: InputEvent) -> void:
	# Нажатие только ставит флаг. Сам луч выполняется в физическом цикле,
	# а отпускание сразу снимает захват и возвращает телу обычную симуляцию.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not inventory_ui.is_open:
				_grab_request_pending = true
		else:
			_grab_request_pending = false
			_release()


func _physics_process(_delta: float) -> void:
	# Здесь находится весь жизненный цикл захвата: попытка, проверка удержания,
	# поиск безопасной цели и применение силы к RigidBody3D.
	if inventory_ui.is_open:
		_grab_request_pending = false
		_release()
		return

	if _grab_request_pending:
		_grab_request_pending = false
		_try_grab()

	if _grabbed_body == null:
		return

	if not is_instance_valid(_grabbed_body) or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_release()
		return

	var forward := -camera.global_basis.z
	var target_position := camera.global_position + forward * _current_hold_distance
	# Проверяем весь CollisionShape3D ящика. Луч проверяет только одну точку и
	# позволяет крупному объекту частично пройти сквозь стену.
	target_position = _find_safe_target_position(target_position)

	# Сила прикладывается в точке захвата: объект может естественно вращаться.
	var world_offset := _grabbed_body.global_transform.basis * _local_grab_offset
	var grabbed_point := _grabbed_body.global_position + world_offset
	var force := (target_position - grabbed_point) * spring_strength
	force -= _grabbed_body.linear_velocity * damping

	if force.length_squared() > max_force * max_force:
		force = force.normalized() * max_force

	_grabbed_body.sleeping = false
	_grabbed_body.apply_force(force, world_offset)
	_debug("Сила применена: цель %s, сила %s, скорость %s." % [target_position, force, _grabbed_body.linear_velocity])


func _try_grab() -> void:
	# Ищет тело под центром экрана и проверяет его правила доступа к захвату.
	# group grabbable — явное разрешение, а world_pickup исключается, чтобы E
	# и ЛКМ не конкурировали за обычный предмет инвентаря.
	var ray_from := camera.global_position
	var ray_to := ray_from - camera.global_basis.z * grab_distance
	var query := PhysicsRayQueryParameters3D.create(
		ray_from,
		ray_to,
		grab_collision_mask,
		[player.get_rid()]
	)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_debug("Под перекрестием ничего нет.")
		return

	var body := hit.get("collider") as RigidBody3D
	_debug_hit(body)
	if body == null:
		_debug("Захват отклонён: найденный объект не является RigidBody3D.")
		return
	if not body.is_in_group("grabbable"):
		_debug("Захват отклонён: объект не входит в группу grabbable.")
		return
	if body.is_in_group("world_pickup"):
		_debug("Захват отклонён: предмет предназначен для подбора в инвентарь.")
		return
	if body.freeze:
		_debug("Захват отклонён: RigidBody3D заморожен.")
		return
	if body.mass > max_grab_mass:
		_debug("Захват отклонён: масса %.2f больше лимита %.2f." % [body.mass, max_grab_mass])
		return

	_grabbed_body = body
	# Сохраняем точку попадания в локальных координатах тела. Благодаря этому
	# сила прикладывается именно к месту захвата, а ящик может естественно вращаться.
	_local_grab_offset = body.to_local(hit.position)
	_current_hold_distance = clampf(
		camera.global_position.distance_to(hit.position),
		0.8,
		hold_distance
	)
	_grabbed_body.sleeping = false
	_debug("Захват установлен: %s, расстояние %.2f." % [body.name, _current_hold_distance])


func _release() -> void:
	# Сбрасываем ссылку и offset, но не меняем transform тела: после отпускания
	# оно продолжает падать и сталкиваться с миром как обычный RigidBody3D.
	if _grabbed_body != null:
		_debug("Захват отпущен: %s, скорость %s." % [_grabbed_body.name, _grabbed_body.linear_velocity])
	_grabbed_body = null
	_local_grab_offset = Vector3.ZERO


func _debug_hit(body: RigidBody3D) -> void:
	if not debug_logging or body == null:
		return
	_debug("Найден объект %s (%s): layer=%d mask=%d grabbable=%s world_pickup=%s mass=%.2f freeze=%s." % [
		body.name,
		body.get_class(),
		body.collision_layer,
		body.collision_mask,
		body.is_in_group("grabbable"),
		body.is_in_group("world_pickup"),
		body.mass,
		body.freeze,
	])


func _debug(message: String) -> void:
	if debug_logging:
		print("PhysicsGrab: ", message)


func _find_safe_target_position(target_position: Vector3) -> Vector3:
	# Возвращает цель перед камерой, если туда помещается вся форма предмета.
	# При препятствии бинарным поиском находит ближайшую безопасную точку, сохраняя
	# физическое движение через apply_force вместо телепортации.
	var collision_shape := _grabbed_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return target_position

	var current_position := _grabbed_body.global_position
	if not _shape_overlaps_at(target_position, collision_shape):
		return target_position

	# Ищем ближайшую к цели точку, в которой форма ещё не пересекает стену.
	# Это сохраняет физическое движение и не телепортирует объект.
	var safe_position := current_position
	var blocked_position := target_position
	for _index in range(7):
		var midpoint := safe_position.lerp(blocked_position, 0.5)
		if _shape_overlaps_at(midpoint, collision_shape):
			blocked_position = midpoint
		else:
			safe_position = midpoint
	return safe_position


func _shape_overlaps_at(position: Vector3, collision_shape: CollisionShape3D) -> bool:
	# Проверяет пересечение формы предмета с Terrain3D, стенами и другими телами
	# в предполагаемой позиции. Сам игрок и захваченный объект исключаются.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.collision_mask = grab_collision_mask
	query.exclude = [player.get_rid(), _grabbed_body.get_rid()]
	var offset := collision_shape.global_position - _grabbed_body.global_position
	query.transform = Transform3D(collision_shape.global_basis, position + offset)
	return not player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
