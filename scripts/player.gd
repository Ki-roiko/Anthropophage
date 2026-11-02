extends CharacterBody3D


# ============================================================
# НАСТРОЙКИ ПЕРСОНАЖА
# ============================================================

@export_group("Movement")

# Чем выше значение, тем быстрее камера поворачивается от движения мыши.
@export var mouse_sensitivity: float = 0.002

# Эти две скорости задают темп обычного движения и спринта.
@export var speed: float = 5.0
@export var sprint_speed: float = 16.0

# gravity тянет персонажа вниз, а jump_velocity задаёт начальный толчок прыжка.
@export var gravity: float = 9.8
@export var jump_velocity: float = 4.5


# ============================================================
# НАСТРОЙКИ ВЫНОСЛИВОСТИ
# ============================================================

@export_group("Stamina")

# Сколько выносливости у персонажа, когда шкала заполнена.
@export_range(1.0, 1000.0, 1.0)
var max_stamina: float = 100.0

# За сколько секунд непрерывного спринта шкала опустеет.
@export_range(0.1, 120.0, 0.1)
var sprint_duration: float = 15.0

# Когда шкала опустеет, персонаж ещё сможет бежать это время.
@export_range(0.1, 30.0, 0.1)
var exhaustion_duration: float = 3.0

# За сколько секунд пустая шкала снова заполнится полностью.
@export_range(0.1, 120.0, 0.1)
var stamina_recovery_duration: float = 20.0


# ============================================================
# НАСТРОЙКИ КАМЕРЫ
# ============================================================

@export_group("Camera")

# При спринте угол обзора расширяется, чтобы движение ощущалось быстрее.
@export var standard_fov: float = 80.0
@export var sprint_fov: float = 95.0

# Чем больше значение, тем быстрее камера приближается к нужному FOV.
@export var fov_change_speed: float = 8.0


# ============================================================
# ССЫЛКИ НА НОДЫ
# ============================================================

# Поворачиваем голову вверх и вниз, не наклоняя всё тело.
@onready var head: Node3D = $Head

# Сама камера — дочерняя нода головы.
@onready var camera: Camera3D = $Head/Camera3D

# Сюда отправляем новое значение, чтобы обновить полоску на экране.
@onready var stamina_bar: Node = $HUD/StaminaBar


# ============================================================
# ВНУТРЕННИЕ ПЕРЕМЕННЫЕ
# ============================================================

# Последнее направление, которое игрок задал клавишами.
var movement_input: Vector2 = Vector2.ZERO

# Сколько выносливости осталось прямо сейчас.
var current_stamina: float = 100.0

# Таймер короткого бега после того, как выносливость закончилась.
var exhaustion_time_left: float = 0.0

# Нужен камере, чтобы понять, включать ли эффекты спринта.
var is_sprinting: bool = false

# Счётчик времени для sin(): без него покачивание не будет непрерывным.
var bob_time: float = 0.0

# Запоминаем исходные значения, чтобы эффекты не сдвигали камеру навсегда.
var camera_start_position: Vector3
var camera_start_rotation: Vector3


# ============================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================

func _ready() -> void:
	# Прячем курсор и привязываем мышь к окну игры.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Сохраняем положение камеры до эффектов покачивания и наклона.
	# Позже будем плавно возвращать камеру именно сюда.
	camera_start_position = camera.position
	camera_start_rotation = camera.rotation

	# При старте игры шкала должна быть полной.
	current_stamina = max_stamina

	# Сообщаем полоске её максимум и текущее значение.
	stamina_bar.set("max_value", max_stamina)
	stamina_bar.call("set_value", current_stamina, false)


# ============================================================
# ОБРАБОТКА ВВОДА
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	# Нас интересует только движение мыши — остальные события здесь не нужны.
	if event is InputEventMouseMotion:
		mouse_look(event)


# ============================================================
# ГЛАВНЫЙ ФИЗИЧЕСКИЙ ЦИКЛ
# ============================================================

func _physics_process(delta: float) -> void:
	# Сначала обновляем скорость и перемещаем самого персонажа.
	moving(delta)

	# После движения камера уже знает, бежим мы или стоим.
	update_camera_effects(delta)


# ============================================================
# ДВИЖЕНИЕ ПЕРСОНАЖА
# ============================================================

func moving(delta: float) -> void:
	# Сначала читаем клавиши, которые нажаты в этом кадре.

	# get_vector() собирает четыре действия движения в один вектор.
	# X: влево — отрицательное значение, вправо — положительное.
	# Y: вперёд — отрицательное значение, назад — положительное.
	movement_input = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	# Просто зажатого Shift недостаточно: спринт включается только вместе с движением.
	var sprint_requested: bool = (
		Input.is_action_pressed("sprint")
		and movement_input.length() > 0.0
	)


	# Теперь решаем, с какой скоростью персонаж будет двигаться.

	# Она уменьшает или восстанавливает шкалу и выбирает подходящую скорость.
	# is_sprinting пригодится ниже для эффектов камеры.
	var current_speed: float = update_stamina(delta, sprint_requested)


	# Переводим нажатые клавиши в направление относительно поворота персонажа.

	# Клавиши дают Vector2, а для движения в 3D нам нужен Vector3.
	# basis поворачивает направление вместе с персонажем.
	# Поэтому W всегда означает движение вперёд
	# туда, куда сейчас смотрит персонаж.
	var direction: Vector3 = (
		transform.basis
		* Vector3(movement_input.x, 0.0, movement_input.y)
	).normalized()


	# Записываем скорость по горизонтальным осям.

	# velocity — встроенная скорость CharacterBody3D, её использует физика Godot.
	# X — влево и вправо.
	# Z — вперёд и назад.
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed


	# Отдельно разбираемся с прыжком и падением.

	update_vertical_movement(delta)


	# Когда все компоненты скорости готовы, можно двигать персонажа.

	# move_and_slide() применяет velocity и двигает персонажа.
	# Заодно Godot учитывает столкновения и скольжение вдоль поверхностей.
	move_and_slide()


# ============================================================
# ВЕРТИКАЛЬНОЕ ДВИЖЕНИЕ: ПРЫЖОК И ГРАВИТАЦИЯ
# ============================================================

func update_vertical_movement(delta: float) -> void:
	# После приземления убираем скорость падения, чтобы персонаж не продолжал копить её в земле.
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0

	# Прыжок срабатывает один раз при нажатии и только с земли.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# В воздухе каждый физический кадр разгоняем падение гравитацией.
	elif not is_on_floor():
		velocity.y -= gravity * delta


# ============================================================
# ВЫНОСЛИВОСТЬ И СПРИНТ
# ============================================================

func update_stamina(delta: float, sprint_requested: bool) -> float:
	# Сравним значение до и после расчёта, чтобы зря не обновлять UI.
	#
	var stamina_before: float = current_stamina

	# Начинаем с обычной скорости. Ниже она может измениться.
	var current_speed: float = speed

	# Спринт здесь немного медленнее экспортируемого максимума: используем 70% разницы.
	#
	#
	var normal_sprint_speed: float = lerpf(speed, sprint_speed, 0.7)

	# После опустошения шкалы скорость становится средней между ходьбой
	# и обычным спринтом.
	var exhaustion_speed: float = lerpf(speed, normal_sprint_speed, 0.5)

	# Каждый кадр сначала считаем, что спринта нет, и включаем его только при выполнении условий.
	is_sprinting = false


	# Игрок зажал спринт и движется.

	if sprint_requested:

		# Пока шкала не пуста, бежим с обычной скоростью спринта.
		if current_stamina > 0.0:
			is_sprinting = true
			current_speed = normal_sprint_speed

			# Сколько единиц шкалы тратится за одну секунду бега.
			var drain_rate: float = max_stamina / sprint_duration

			# Умножаем расход на delta, чтобы скорость расхода не зависела от FPS.
			current_stamina = maxf(
				current_stamina - drain_rate * delta,
				0.0
			)

			# Если шкала дошла до нуля,
			# запускаем дополнительные три секунды бега.
			if is_zero_approx(current_stamina):
				current_stamina = 0.0
				exhaustion_time_left = exhaustion_duration

		# Шкала уже пуста, но дополнительное время ещё не вышло —
		# продолжаем бежать медленнее.
		elif exhaustion_time_left > 0.0:
			is_sprinting = true
			current_speed = exhaustion_speed

			# Уменьшаем оставшееся время, не давая ему уйти ниже нуля.
			exhaustion_time_left = maxf(
				exhaustion_time_left - delta,
				0.0
			)


	# Игрок отпустил спринт.

	else:
		# Если отпустить спринт, бонусное время сбрасывается.
		exhaustion_time_left = 0.0

		# Пока шкала заполнена не полностью, возвращаем выносливость.
		if current_stamina < max_stamina:

			# Сколько единиц выносливости возвращается за одну секунду.
			var recovery_rate: float = max_stamina / stamina_recovery_duration

			# Добавляем восстановление с учётом delta и не выходим за максимум.
			current_stamina = minf(
				current_stamina + recovery_rate * delta,
				max_stamina
			)


	# Обновляем полоску выносливости.

	# Если значение изменилось, передаём его полоске выносливости.
	if not is_equal_approx(stamina_before, current_stamina):
		stamina_bar.call("set_value", current_stamina)

	# Возвращаем выбранную скорость обратно в moving().
	return current_speed


# ============================================================
# КАМЕРА: ОБНОВЛЕНИЕ ВСЕХ ЭФФЕКТОВ
# ============================================================

func update_camera_effects(delta: float) -> void:
	# Собрали эффекты в одном месте, чтобы физический цикл не разрастался.
	update_camera_fov(delta)
	update_camera_bob(delta)
	update_camera_lean(delta)


# ============================================================
# КАМЕРА: FOV
# ============================================================

func update_camera_fov(delta: float) -> void:
	# Выбираем FOV: при спринте обзор шире, при ходьбе возвращается обычный.
	var target_fov: float = standard_fov

	if is_sprinting:
		target_fov = sprint_fov

	# lerp() ждёт коэффициент от 0 до 1, поэтому ограничиваем его.
	var weight: float = clampf(fov_change_speed * delta, 0.0, 1.0)

	camera.fov = lerpf(camera.fov, target_fov, weight)


# ============================================================
# КАМЕРА: ПОКАЧИВАНИЕ
# ============================================================

func update_camera_bob(delta: float) -> void:
	# На месте и в воздухе шаги не должны проигрываться.
	var is_moving: bool = (
		is_on_floor()
		and movement_input.length() > 0.0
	)

	if is_moving:
		# Во время спринта шаги чаще и заметнее.
		var frequency: float = 7.0
		var amplitude: float = 0.025

		if is_sprinting:
			frequency = 12.0
			amplitude = 0.04

		# delta прибавляется к счётчику, а sin() превращает его в плавное движение вверх-вниз.
		bob_time += delta * frequency

		# sin() плавно меняется от -1 до 1 — умножаем его на амплитуду покачивания.
		var bob_amount: float = sin(bob_time) * amplitude

		# Прибавляем смещение к исходной высоте, а не к прошлому кадру: камера не будет уплывать.
		camera.position.y = camera_start_position.y + bob_amount

		# На спринте слегка меняем угол камеры вверх-вниз для ощущения ускорения.
		var pitch_amount: float = 0.0

		if is_sprinting:
			pitch_amount = sin(bob_time) * 0.015

		camera.rotation.x = camera_start_rotation.x + pitch_amount

	else:
		# Если персонаж остановился или оказался в воздухе,
		# постепенно возвращаем камеру к её обычному положению.
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
	# При стрейфе камера немного кренится в сторону, противоположную движению.
	var target_lean: float = -movement_input.x * deg_to_rad(3.0)

	# Во время спринта к наклону добавляется лёгкий ритм шагов.
	if is_sprinting and is_on_floor():
		target_lean += sin(bob_time) * deg_to_rad(1.0)

	# Не меняем наклон резко — плавно тянем камеру к нужному углу.
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
	# Мышь влево-вправо поворачивает персонажа целиком.
	rotate_y(-event.relative.x * mouse_sensitivity)

	# Мышь вверх-вниз двигает только голову, а не всё тело.
	head.rotate_x(-event.relative.y * mouse_sensitivity)

	# Не даём камере перевернуться, когда игрок ведёт мышь слишком высоко
	# или низко.
	head.rotation.x = clampf(
		head.rotation.x,
		-PI / 2,
		PI / 2
	)
