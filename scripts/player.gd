extends CharacterBody3D

@export_group("Moving")
@export var mouse_sensitivity : float = 0.002
@export var speed : float = 5.0
@export var sprint_speed : float = 16.0
@export var gravity : float = 9.8
@export var jump_velocity : float = 4.5
@export_group("Stamina")
@export_range(1.0, 1000.0, 1.0) var max_stamina: float = 100.0
@export_range(0.1, 120.0, 0.1) var sprint_duration: float = 15.0
@export_range(0.1, 30.0, 0.1) var exhaustion_duration: float = 3.0
@export_range(0.1, 120.0, 0.1) var stamina_recovery_duration: float = 20.0
@export_group("Camera")
@export var standard_fov : float = 80.0
@export var sprint_fov : float = 95.0
@export var fov_change_speed : float = 8

@onready var head : Node3D = $Head
@onready var camera : Camera3D = $Head/Camera3D
@onready var stamina_bar: Node = $HUD/StaminaBar

var bob_time: float
var lean_time: float
var current_stamina: float = 100.0
var exhaustion_time_left: float = 0.0
var is_sprinting: bool = false

@onready var camera_start_position = camera.position
@onready var camera_start_rotation = camera.rotation


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	current_stamina = max_stamina
	stamina_bar.set("max_value", max_stamina)
	stamina_bar.call("set_value", current_stamina, false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_look(event)


func _physics_process(delta: float) -> void:
	moving(delta)
	sprint_effect(delta)
	camera_lean(delta)
	head_bob(delta, 10, 0.1, 5)


############################## КАМЕРА ##############################
# Эффект спринта: покачивангие камеры и увеличение FOV
func sprint_effect(delta: float) -> void:
	if is_sprinting and Vector2(velocity.x, velocity.z).length() > 0:
		camera.fov = lerp(camera.fov, sprint_fov, fov_change_speed * delta)

		camera_move_lean(delta, lerp(0.5, 13.0, 0.7), lerp(0.0002, 0.01, 0.7))
		head_move_bob(delta, lerp(0.5, 12.0, 0.7), 0.03, 5)
		#head_bob(delta, 2, 0.01, 5)

		camera.position = Vector3(
			lerp(camera.position.x, camera.position.x + randf_range(-0.15, 0.15), 5 * delta),
			camera_start_position.y + sin(bob_time * 10) * 0.01,
			lerp(camera.position.z, camera.position.z + randf_range(-0.15, 0.15), 5 * delta)
		)
	else:
		camera.fov = lerp(camera.fov, standard_fov, fov_change_speed * delta)


# основная функция для управления камерой мышью
func mouse_look(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)
	head.rotate_x(-event.relative.y * mouse_sensitivity)
	head.rotation.x = clampf(head.rotation.x, -PI/2, PI/2)


# функция для покачивания камеры при ходьбе
func head_bob(delta: float, frequency: float, amplitude: float, weight: float) -> void:
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0:
		camera_move_lean(delta, 5, 0.003)

		bob_time += delta * frequency
		var bobbing_amount = sin(bob_time) * amplitude
		camera.position.y = camera_start_position.y + bobbing_amount
		#camera.position.x = camera_start_position.x + sin(bob_time * 0.5) * amplitude * 1
		#camera.position.z = camera_start_position.z + sin(bob_time * 0.5) * amplitude * 1
	else:
		camera.position.y = lerp(camera.position.y, camera_start_position.y, weight * delta)


# функция для наклона камеры в сторону движения
func camera_lean(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	).normalized()
	var target_lean = -input_dir.x * 0.05
	var current_lean = camera.rotation.z
	camera.rotation.z = lerp(current_lean, target_lean, 5 * delta)


# функция для наклона камеры при спринте
func camera_move_lean(delta: float, frequency: float, amplitude: float) -> void:
	lean_time += delta * frequency
	var lean_amount = pow(sin(lean_time), 7) * amplitude
	camera.rotation.z = camera.rotation.z + lean_amount


# функция для покачивания камеры при спринте
func head_move_bob(delta: float, frequency: float, amplitude: float, weight: float) -> void:
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0:
		bob_time += delta * frequency
		var bobbing_amount = clampf(sin(bob_time), -0.5, 0.5) * amplitude
		camera.rotation.x = camera_start_rotation.x + bobbing_amount
	else:
		camera.rotation.x = lerp(camera.rotation.x, camera_start_rotation.x, weight * delta)



#func idle_sway(delta: float) -> void:
#	if is_on_floor() and Vector2(velocity.x, velocity.z).length() == 0:
#		bob_time += delta * 1
#		var sway_amount = sin(bob_time) * 0.01
#		camera.position.x = camera_start_position.x + sway_amount
#	else:
#		camera.position.x = lerp(camera.position.x, camera_start_position.x, 5 * delta)





############################### ДВИЖЕНИЕ ##############################
func moving(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var stamina_before := current_stamina
	var sprint_requested := Input.is_action_pressed("sprint") and input_dir.length() > 0.0
	var current_speed: float = speed
	is_sprinting = false

	if sprint_requested:
		if current_stamina > 0.0:
			is_sprinting = true
			current_speed = lerpf(speed, sprint_speed, 0.7)

			var drain_rate := max_stamina / maxf(sprint_duration, 0.001)
			current_stamina = maxf(current_stamina - drain_rate * delta, 0.0)

			if is_zero_approx(current_stamina):
				current_stamina = 0.0
				exhaustion_time_left = exhaustion_duration
		elif exhaustion_time_left > 0.0:
			is_sprinting = true
			current_speed = lerpf(speed, sprint_speed, 0.5)
			exhaustion_time_left = maxf(exhaustion_time_left - delta, 0.0)
	else:
		exhaustion_time_left = 0.0

		if current_stamina < max_stamina:
			var recovery_rate := max_stamina / maxf(stamina_recovery_duration, 0.001)
			current_stamina = minf(current_stamina + recovery_rate * delta, max_stamina)

	if not is_equal_approx(stamina_before, current_stamina):
		stamina_bar.call("set_value", current_stamina, false)

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()
