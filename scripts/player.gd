extends CharacterBody3D

@export_group("Moving")
@export var mouse_sensitivity : float = 0.002
@export var speed : float = 5.0
@export var sprint_speed : float = 16.0
@export var gravity : float = 9.8
@export var jump_velocity : float = 4.5
@export_group("Camera")
@export var standard_fov : float = 70.0
@export var sprint_fov : float = 90.0
@export var fov_change_speed : float = 4

@onready var head : Node3D = $Head
@onready var camera : Camera3D = $Head/Camera3D
var bob_time : float
@onready var camera_start_position = camera.position


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_look(event)

func _physics_process(delta: float) -> void:
	moving(delta)
	fov_change(delta)
	head_bob(delta)
	camera_lean(delta)





func fov_change (delta: float) -> void:
	if Vector2(velocity.x, velocity.z).length() > 0 and Input.is_action_pressed("sprint"):
		camera.fov = lerp(camera.fov, sprint_fov, fov_change_speed * delta)
	else:
		camera.fov = lerp(camera.fov, standard_fov, fov_change_speed * delta)

func moving(delta: float) -> void:
	var input_dir : Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	var current_speed = speed
	if Input.is_action_pressed("sprint"):
		current_speed = sprint_speed
	
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed
	
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	move_and_slide()

func mouse_look(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)
	head.rotate_x(-event.relative.y * mouse_sensitivity)
	head.rotation.x = clampf(head.rotation.x, -PI/2, PI/2)

func head_bob(delta: float) -> void:
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0:
		bob_time += delta * 10
		var bobbing_amount = sin(bob_time) * 0.05
		camera.position.y = camera_start_position.y + bobbing_amount
	else: 
		camera.position.y = lerp(camera.position.y, camera_start_position.y, 5 * delta)

func camera_lean(delta: float) -> void:
	var input_dir : Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	).normalized()
	var target_lean = -input_dir.x * 0.05
	var current_lean = camera.rotation.z
	camera.rotation.z = lerp(current_lean, target_lean, 5 * delta)

#func idle_sway(delta: float) -> void:
#	if is_on_floor() and Vector2(velocity.x, velocity.z).length() == 0:
#		bob_time += delta * 1
#		var sway_amount = sin(bob_time) * 0.01
#		camera.position.x = camera_start_position.x + sway_amount
#	else:
#		camera.position.x = lerp(camera.position.x, camera_start_position.x, 5 * delta)