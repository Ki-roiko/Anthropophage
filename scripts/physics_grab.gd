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

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var camera: Camera3D = player.get_node("Head/Camera3D") as Camera3D
@onready var inventory_ui: InventoryUIController = player.get_node("HUD/InventoryUI") as InventoryUIController

var _grab_request_pending: bool = false
var _grabbed_body: RigidBody3D
var _local_grab_offset: Vector3
var _current_hold_distance: float = 2.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not inventory_ui.is_open:
				_grab_request_pending = true
		else:
			_grab_request_pending = false
			_release()


func _physics_process(_delta: float) -> void:
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

	# Если перед целевой точкой стена, не тянем объект сквозь неё.
	var obstacle_query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		target_position,
		grab_collision_mask,
		[player.get_rid(), _grabbed_body.get_rid()]
	)
	var obstacle_hit := player.get_world_3d().direct_space_state.intersect_ray(obstacle_query)
	if not obstacle_hit.is_empty():
		target_position = obstacle_hit.position - forward * 0.25

	# Сила прикладывается в точке захвата: объект может естественно вращаться.
	var world_offset := _grabbed_body.global_transform.basis * _local_grab_offset
	var grabbed_point := _grabbed_body.global_position + world_offset
	var force := (target_position - grabbed_point) * spring_strength
	force -= _grabbed_body.linear_velocity * damping

	if force.length_squared() > max_force * max_force:
		force = force.normalized() * max_force

	_grabbed_body.sleeping = false
	_grabbed_body.apply_force(force, world_offset)


func _try_grab() -> void:
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
		return

	var body := hit.get("collider") as RigidBody3D
	if body == null:
		return
	if body.is_in_group("world_pickup") or body.freeze or body.mass > max_grab_mass:
		return

	_grabbed_body = body
	_local_grab_offset = body.to_local(hit.position)
	_current_hold_distance = clampf(
		camera.global_position.distance_to(hit.position),
		0.8,
		hold_distance
	)
	_grabbed_body.sleeping = false


func _release() -> void:
	_grabbed_body = null
	_local_grab_offset = Vector3.ZERO
