extends CharacterBody3D


# ============================================================
# НАСТРОЙКИ ПЕРСОНАЖА
# ============================================================

@export_group("Movement")

# Чувствительность мыши при вращении камеры.
@export var mouse_sensitivity: float = 0.002

# Скорость обычной ходьбы и максимальная скорость спринта.
@export var speed: float = 5.0
@export var sprint_speed: float = 16.0

# Сила гравитации и скорость прыжка.
@export var gravity: float = 9.8
@export var jump_velocity: float = 4.5


# ============================================================
# НАСТРОЙКИ ВЫНОСЛИВОСТИ
# ============================================================

@export_group("Stamina")

# Максимальный запас выносливости.
@export_range(1.0, 1000.0, 1.0)
var max_stamina: float = 100.0

# Время, за которое выносливость полностью расходуется.
@export_range(0.1, 120.0, 0.1)
var sprint_duration: float = 15.0

# Дополнительное время бега после полного истощения.
@export_range(0.1, 30.0, 0.1)
var exhaustion_duration: float = 3.0

# Время полного восстановления выносливости.
@export_range(0.1, 120.0, 0.1)
var stamina_recovery_duration: float = 20.0


# ============================================================
# НАСТРОЙКИ КАМЕРЫ
# ============================================================

@export_group("Camera")

# Угол обзора при обычном движении и спринте.
@export var standard_fov: float = 80.0
@export var sprint_fov: float = 95.0

# Скорость плавного изменения FOV.
@export var fov_change_speed: float = 8.0


# ============================================================
# ССЫЛКИ НА НОДЫ
# ============================================================

# Голова персонажа. Вращается по вертикали при движении мыши.
@onready var head: Node3D = $Head

# Камера находится внутри Head.
@onready var camera: Camera3D = $Head/Camera3D

# Индикатор выносливости в интерфейсе.
@onready var stamina_bar: Node = $HUD/StaminaBar


# ============================================================
# ВНУТРЕННИЕ ПЕРЕМЕННЫЕ
# ============================================================

# Направление нажатых клавиш движения.
var movement_input: Vector2 = Vector2.ZERO

# Текущее количество выносливости.
var current_stamina: float = 100.0

# Оставшееся время дополнительного бега после истощения.
var exhaustion_time_left: float = 0.0

# Показывает, использует ли персонаж спринт или остаточный бег.
var is_sprinting: bool = false

# Время для расчёта периодического покачивания камеры.
var bob_time: float = 0.0

# Исходное положение и вращение камеры.
var camera_start_position: Vector3
var camera_start_rotation: Vector3


# ============================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================

func _ready() -> void:
	# Захватываем мышь, чтобы она управляла камерой.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Запоминаем исходные параметры камеры.
	# Они понадобятся для возврата после покачивания.
	camera_start_position = camera.position
	camera_start_rotation = camera.rotation

	# Заполняем выносливость до максимума.
	current_stamina = max_stamina

	# Настраиваем индикатор выносливости.
	stamina_bar.set("max_value", max_stamina)
	stamina_bar.call("set_value", current_stamina, false)


# ============================================================
# ОБРАБОТКА ВВОДА
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	# Проверяем, что пользователь двигает мышью.
	if event is InputEventMouseMotion:
		mouse_look(event)


# ============================================================
# ГЛАВНЫЙ ФИЗИЧЕСКИЙ ЦИКЛ
# ============================================================

func _physics_process(delta: float) -> void:
	# Сначала рассчитываем перемещение персонажа.
	moving(delta)

	# Затем обновляем визуальные эффекты камеры.
	update_camera_effects(delta)


# ============================================================
# ДВИЖЕНИЕ ПЕРСОНАЖА
# ============================================================

func moving(delta: float) -> void:
	# 1. ПОЛУЧАЕМ ВВОД

	# Получаем направление движения из Input Map.
	# X отвечает за движение влево/вправо.
	# Y отвечает за движение вперёд/назад.
	movement_input = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	# Проверяем, хочет ли игрок бежать и действительно ли движется.
	var sprint_requested: bool = (
		Input.is_action_pressed("sprint")
		and movement_input.length() > 0.0
	)


	# 2. РАССЧИТЫВАЕМ СКОРОСТЬ

	# Функция выносливости возвращает актуальную скорость.
	# Она также обновляет is_sprinting и запас выносливости.
	var current_speed: float = update_stamina(delta, sprint_requested)


	# 3. ПЕРЕВОДИМ ВВОД В МИРОВОЕ НАПРАВЛЕНИЕ

	# Преобразуем двумерный ввод в трёхмерный вектор.
	# transform.basis учитывает поворот самого персонажа.
	# Благодаря этому W всегда означает движение вперёд
	# относительно направления взгляда персонажа.
	var direction: Vector3 = (
		transform.basis
		* Vector3(movement_input.x, 0.0, movement_input.y)
	).normalized()


	# 4. ЗАДАЁМ ГОРИЗОНТАЛЬНУЮ СКОРОСТЬ

	# velocity — встроенная переменная CharacterBody3D.
	# X отвечает за движение влево/вправо.
	# Z отвечает за движение вперёд/назад.
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed


	# 5. ОБНОВЛЯЕМ ВЕРТИКАЛЬНУЮ СКОРОСТЬ

	update_vertical_movement(delta)


	# 6. ПЕРЕМЕЩАЕМ ПЕРСОНАЖА

	# Применяем velocity к персонажу.
	# Godot проверяет столкновения и позволяет скользить вдоль стен.
	move_and_slide()


# ============================================================
# ВЕРТИКАЛЬНОЕ ДВИЖЕНИЕ: ПРЫЖОК И ГРАВИТАЦИЯ
# ============================================================

func update_vertical_movement(delta: float) -> void:
	# Если персонаж стоит на земле, убираем остаточную скорость падения.
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0

	# Прыгать можно только при контакте с землёй.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Если персонаж находится в воздухе, применяем гравитацию.
	elif not is_on_floor():
		velocity.y -= gravity * delta


# ============================================================
# ВЫНОСЛИВОСТЬ И СПРИНТ
# ============================================================

func update_stamina(delta: float, sprint_requested: bool) -> float:
	# Запоминаем выносливость до обновления.
	# Это нужно, чтобы не обновлять интерфейс без необходимости.
	var stamina_before: float = current_stamina

	# По умолчанию персонаж передвигается обычным шагом.
	var current_speed: float = speed

	# Рассчитываем скорость спринта.
	# 0.7 означает, что используется 70% разницы
	# между обычной скоростью и максимальным спринтом.
	var normal_sprint_speed: float = lerpf(speed, sprint_speed, 0.7)

	# Скорость после истощения — половина разницы
	# между ходьбой и обычным спринтом.
	var exhaustion_speed: float = lerpf(speed, normal_sprint_speed, 0.5)

	# Сбрасываем состояние спринта перед проверкой.
	is_sprinting = false


	# ИГРОК УДЕРЖИВАЕТ СПРИНТ

	if sprint_requested:

		# Пока есть выносливость, используем обычный спринт.
		if current_stamina > 0.0:
			is_sprinting = true
			current_speed = normal_sprint_speed

			# Рассчитываем расход выносливости в секунду.
			var drain_rate: float = max_stamina / sprint_duration

			# Уменьшаем выносливость с учётом времени кадра.
			current_stamina = maxf(
				current_stamina - drain_rate * delta,
				0.0
			)

			# Если выносливость закончилась,
			# запускаем таймер дополнительного бега.
			if is_zero_approx(current_stamina):
				current_stamina = 0.0
				exhaustion_time_left = exhaustion_duration

		# Если выносливость закончилась, но время ещё осталось,
		# персонаж продолжает бежать с уменьшенной скоростью.
		elif exhaustion_time_left > 0.0:
			is_sprinting = true
			current_speed = exhaustion_speed

			# Отсчитываем время дополнительного бега.
			exhaustion_time_left = maxf(
				exhaustion_time_left - delta,
				0.0
			)


	# ИГРОК НЕ УДЕРЖИВАЕТ СПРИНТ

	else:
		# Отменяем оставшееся время дополнительного бега.
		exhaustion_time_left = 0.0

		# Если выносливость не полная, начинаем восстановление.
		if current_stamina < max_stamina:

			# Скорость восстановления в секунду.
			var recovery_rate: float = max_stamina / stamina_recovery_duration

			# Восстанавливаем выносливость, не превышая максимум.
			current_stamina = minf(
				current_stamina + recovery_rate * delta,
				max_stamina
			)


	# ОБНОВЛЯЕМ ИНТЕРФЕЙС

	# Обращаемся к индикатору только при изменении значения.
	if not is_equal_approx(stamina_before, current_stamina):
		stamina_bar.call("set_value", current_stamina)

	# Возвращаем скорость, которую использует moving().
	return current_speed


# ============================================================
# КАМЕРА: ОБНОВЛЕНИЕ ВСЕХ ЭФФЕКТОВ
# ============================================================

func update_camera_effects(delta: float) -> void:
	# Каждая функция отвечает только за свой эффект.
	update_camera_fov(delta)
	update_camera_bob(delta)
	update_camera_lean(delta)


# ============================================================
# КАМЕРА: FOV
# ============================================================

func update_camera_fov(delta: float) -> void:
	# Во время спринта плавно увеличиваем угол обзора.
	var target_fov: float = standard_fov

	if is_sprinting:
		target_fov = sprint_fov

	# Ограничиваем коэффициент сглаживания диапазоном 0–1.
	var weight: float = clampf(fov_change_speed * delta, 0.0, 1.0)

	camera.fov = lerpf(camera.fov, target_fov, weight)


# ============================================================
# КАМЕРА: ПОКАЧИВАНИЕ
# ============================================================

func update_camera_bob(delta: float) -> void:
	# Покачивание работает только при движении по земле.
	var is_moving: bool = (
		is_on_floor()
		and movement_input.length() > 0.0
	)

	if is_moving:
		# При спринте покачивание становится быстрее.
		var frequency: float = 7.0
		var amplitude: float = 0.025

		if is_sprinting:
			frequency = 12.0
			amplitude = 0.04

		# Накопление времени создаёт непрерывную синусоидальную волну.
		bob_time += delta * frequency

		# Получаем текущее смещение камеры вверх и вниз.
		var bob_amount: float = sin(bob_time) * amplitude

		# Изменяем высоту относительно исходной позиции.
		camera.position.y = camera_start_position.y + bob_amount

		# При спринте добавляем небольшое покачивание камеры вперёд-назад.
		var pitch_amount: float = 0.0

		if is_sprinting:
			pitch_amount = sin(bob_time) * 0.015

		camera.rotation.x = camera_start_rotation.x + pitch_amount

	else:
		# Когда персонаж останавливается или прыгает,
		# плавно возвращаем камеру в исходное положение.
		var weight: float = clampf(5.0 * delta, 0.0, 1.0)

		camera.position.y = lerpf(
			camera.position.y,
			camera_start_position.y,
			weight
		)

		camera.rotation.x = lerpf(
			camera.rotation.x,
			camera_start_rotation.x,
			weight
		)


# ============================================================
# КАМЕРА: НАКЛОН ПРИ ДВИЖЕНИИ
# ============================================================

func update_camera_lean(delta: float) -> void:
	# При движении в сторону камера наклоняется в противоположную сторону.
	var target_lean: float = -movement_input.x * deg_to_rad(3.0)

	# Во время спринта добавляем небольшое ритмичное покачивание.
	if is_sprinting and is_on_floor():
		target_lean += sin(bob_time) * deg_to_rad(1.0)

	# Плавно приближаем текущий наклон к целевому.
	var weight: float = clampf(8.0 * delta, 0.0, 1.0)

	camera.rotation.z = lerpf(
		camera.rotation.z,
		camera_start_rotation.z + target_lean,
		weight
	)


# ============================================================
# КАМЕРА: УПРАВЛЕНИЕ МЫШЬЮ
# ============================================================

func mouse_look(event: InputEventMouseMotion) -> void:
	# Горизонтальное движение мыши поворачивает всё тело.
	rotate_y(-event.relative.x * mouse_sensitivity)

	# Вертикальное движение мыши поворачивает только голову.
	head.rotate_x(-event.relative.y * mouse_sensitivity)

	# Ограничиваем угол взгляда, чтобы нельзя было
	# перевернуть камеру через голову персонажа.
	head.rotation.x = clampf(
		head.rotation.x,
		-PI / 2,
		PI / 2
	)
