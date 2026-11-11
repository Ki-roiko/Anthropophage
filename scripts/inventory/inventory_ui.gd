class_name InventoryUIController
extends Control
## Центральное окно инвентаря. Рисует сетку, предметы и управляет drag & drop.

signal equip_requested(item_uid: int)
signal drop_requested(item_uid: int)

@export var cell_size: float = 62.0
@export var cell_gap: float = 5.0

@onready var inventory_data: InventoryDataModel = get_node("../../InventoryData") as InventoryDataModel

var is_open: bool = false

var _board: Control
var _item_layer: Control
var _cell_panels: Array[Panel] = []
var _cell_highlight_states: Array[int] = []
var _cell_styles: Dictionary = {}
var _item_buttons: Dictionary = {}

var _dragging_uid: int = -1
var _dragging_button: Button
## Клетка внутри предмета, на которую нажал игрок.
## Например, (1, 1) для правой нижней клетки предмета 2×2.
var _drag_anchor_cell: Vector2i = Vector2i.ZERO
# Положение предмета, которое UI предлагает модели при отпускании мыши.
var _candidate_position: Vector2i = Vector2i.ZERO
# Результат проверки InventoryDataModel для текущей ориентации и позиции.
var _candidate_valid: bool = false
# Ориентация карточки во время текущего перетаскивания.
var _dragging_rotated: bool = false

var _mouse_mode_before_open: Input.MouseMode = Input.MOUSE_MODE_CAPTURED


# Создаёт интерфейс один раз и подписывает его на изменения модели инвентаря.
# Сигнал inventory_changed нужен, чтобы UI обновлялся после подбора, выбрасывания
# или программного добавления предмета.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_build_interface()
	inventory_data.inventory_changed.connect(_on_inventory_changed)
	set_process_input(true)


# Открывает окно, показывает курсор и строит карточки из текущего состояния модели.
func open_inventory() -> void:
	if is_open:
		return

	_mouse_mode_before_open = Input.mouse_mode
	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_items()


# Закрывает окно, отменяет незавершённый drag и возвращает прежний режим мыши.
func close_inventory() -> void:
	if not is_open:
		return

	_cancel_drag()
	is_open = false
	visible = false
	Input.mouse_mode = _mouse_mode_before_open


# Обрабатывает Tab, R и отпускание ЛКМ. Движение мыши обрабатывается отдельно,
# потому что оно нужно только во время активного drag.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			if is_open:
				close_inventory()
			else:
				open_inventory()
			get_viewport().set_input_as_handled()
			return

		if is_open and _dragging_uid >= 0 and event.keycode == KEY_R:
			_rotate_dragged_item()
			get_viewport().set_input_as_handled()
			return

	if not is_open:
		return

	if event is InputEventMouseMotion and _dragging_uid >= 0:
		_update_drag_preview()
	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
		and _dragging_uid >= 0
	):
		_finish_drag()
		get_viewport().set_input_as_handled()


# Создаёт фон, сетку и слой карточек. Карточки находятся в отдельном слое,
# поэтому могут перекрывать клетки и получать собственные события мыши.
func _build_interface() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.015, 0.02, 0.03, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(610.0, 535.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	center.add_child(panel)

	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 18)
	margins.add_theme_constant_override("margin_right", 18)
	margins.add_theme_constant_override("margin_top", 16)
	margins.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margins)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margins.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)

	var title := Label.new()
	title.text = "ИНВЕНТАРЬ"
	title.add_theme_font_size_override("font_size", 23)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(36.0, 32.0)
	close_button.pressed.connect(close_inventory)
	header.add_child(close_button)

	var subtitle := Label.new()
	subtitle.text = "Снаряжение"
	subtitle.add_theme_color_override("font_color", Color(0.68, 0.72, 0.77))
	layout.add_child(subtitle)

	_board = Control.new()
	_board.custom_minimum_size = Vector2(
		inventory_data.grid_size.x * cell_size + (inventory_data.grid_size.x - 1) * cell_gap,
		inventory_data.grid_size.y * cell_size + (inventory_data.grid_size.y - 1) * cell_gap
	)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_board)

	for y in range(inventory_data.grid_size.y):
		for x in range(inventory_data.grid_size.x):
			var cell := Panel.new()
			cell.position = Vector2(x, y) * (cell_size + cell_gap)
			cell.size = Vector2(cell_size, cell_size)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_theme_stylebox_override(
				"panel",
				_make_cell_style(Color(0.075, 0.09, 0.11, 1.0), Color(0.19, 0.23, 0.27, 1.0))
			)
			_board.add_child(cell)
			_cell_panels.append(cell)
			_cell_highlight_states.append(-1)

	_item_layer = Control.new()
	_item_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_item_layer)

	var help := Label.new()
	help.text = "ЛКМ — переместить   •   R — повернуть при переносе   •   ПКМ — выбросить   •   двойной ЛКМ — взять в руки"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.67, 0.71, 0.76))
	layout.add_child(help)


func _on_inventory_changed() -> void:
	# Во время drag карточка уже двигается отдельно от модели. Поэтому не
	# пересоздаём её на каждый промежуточный сигнал и обновляем после завершения.
	if _dragging_uid < 0:
		_rebuild_items()


# Перерисовывает карточки из модели. Это безопаснее, чем менять данные из UI:
# модель остаётся источником истины, а UI только показывает её копию.
func _rebuild_items() -> void:
	if _item_layer == null:
		return

	for child in _item_layer.get_children():
		_item_layer.remove_child(child)
		child.queue_free()

	_item_buttons.clear()

	for entry in inventory_data.get_items():
		var item_uid := int(entry.get("uid", -1))
		var definition := inventory_data.get_definition(StringName(entry.get("item_id", "")))
		if definition == null:
			continue

		var footprint := _get_footprint(definition, bool(entry.get("rotated", false)))
		var button_size := _footprint_to_pixels(footprint)

		var button := Button.new()
		button.position = _cell_to_pixel(entry.get("position", Vector2i.ZERO))
		button.size = button_size
		button.text = "%s\n×%d" % [
			definition.icon_symbol,
			int(entry.get("amount", 1))
		]
		button.tooltip_text = "%s\n%s" % [
			definition.display_name,
			definition.description
		]
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98))
		button.add_theme_stylebox_override(
			"normal",
			_make_cell_style(definition.display_color.darkened(0.35), definition.display_color)
		)
		button.add_theme_stylebox_override(
			"hover",
			_make_cell_style(definition.display_color.darkened(0.18), Color(0.88, 0.91, 0.95))
		)
		button.add_theme_stylebox_override(
			"pressed",
			_make_cell_style(definition.display_color.darkened(0.5), definition.display_color.lightened(0.2))
		)
		button.add_theme_stylebox_override(
			"focus",
			_make_cell_style(definition.display_color.darkened(0.35), definition.display_color)
		)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_NONE
		button.gui_input.connect(_on_item_gui_input.bind(item_uid))
		_item_layer.add_child(button)
		_item_buttons[item_uid] = button


# Начинает drag, определяя клетку внутри предмета под курсором.
# Anchor хранится в клетках, чтобы предмет не прыгал при захвате за середину.
func _on_item_gui_input(event: InputEvent, item_uid: int) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		drop_requested.emit(item_uid)
		get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.double_click:
		equip_requested.emit(item_uid)
		get_viewport().set_input_as_handled()
		return

	var button := _item_buttons.get(item_uid) as Button
	if button == null:
		return

	var entry := inventory_data.get_item(item_uid)
	var definition := inventory_data.get_definition(StringName(entry.get("item_id", "")))
	if definition == null:
		return

	_dragging_uid = item_uid
	_dragging_button = button
	_dragging_rotated = bool(entry.get("rotated", false))
	var footprint := _get_footprint(definition, _dragging_rotated)
	_drag_anchor_cell = _pixel_to_cell_in_footprint(event.position, footprint)
	_dragging_button.z_index = 10
	_dragging_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_drag_preview()
	get_viewport().set_input_as_handled()


# Показывает карточку в целочисленной позиции сетки и подсвечивает будущие клетки.
# Координаты мыши переводятся в локальные координаты board одной transform-операцией.
func _update_drag_preview() -> void:
	if _dragging_uid < 0 or _dragging_button == null:
		return

	var mouse_board_local := _mouse_to_board_local()
	var mouse_cell := _pixel_to_grid_cell(mouse_board_local)
	# Позиция предмета считается от захваченной клетки. Поэтому при переносе
	# правой нижней клетки именно она остаётся под курсором.
	_candidate_position = mouse_cell - _drag_anchor_cell
	_candidate_valid = inventory_data.can_place(
		_dragging_uid,
		_candidate_position,
		_dragging_rotated
	)

	var entry := inventory_data.get_item(_dragging_uid)
	var definition := inventory_data.get_definition(StringName(entry.get("item_id", "")))
	if definition != null:
		var footprint := _get_footprint(definition, _dragging_rotated)
		var preview_size := _footprint_to_pixels(footprint)
		# Карточки не находятся внутри Container, поэтому им не нужен
		# custom_minimum_size. Задаём точный размер напрямую, без отложенного
		# пересчёта minimum-size, который превращал прямоугольник в квадрат.
		_dragging_button.size = preview_size

	# Предпросмотр сразу стоит в той же клетке, куда предмет попадёт после
	# отпускания. Благодаря этому подсветка и карточка используют одну геометрию.
	_dragging_button.position = _cell_to_pixel(_candidate_position)
	_dragging_button.modulate = (
		Color(0.62, 1.0, 0.7, 0.94)
		if _candidate_valid
		else Color(1.0, 0.52, 0.48, 0.9)
	)
	_update_cell_highlights()


# Поворачивает footprint и anchor одновременно. Так при R сохраняется та же
# физическая точка захвата, а прямоугольник 1×2 становится 2×1.
func _rotate_dragged_item() -> void:
	if _dragging_button == null:
		return

	var entry := inventory_data.get_item(_dragging_uid)
	var definition := inventory_data.get_definition(StringName(entry.get("item_id", "")))
	if definition == null or definition.size.x == definition.size.y:
		return

	# Поворачиваем и сам anchor вместе с прямоугольником. Для поворота по
	# часовой стрелке клетка (x, y) становится (height - 1 - y, x).
	var old_footprint := _get_footprint(definition, _dragging_rotated)
	_dragging_rotated = not _dragging_rotated
	_drag_anchor_cell = Vector2i(
		old_footprint.y - 1 - _drag_anchor_cell.y,
		_drag_anchor_cell.x
	)

	_update_drag_preview()


# Переводит результат проверки модели в состояния клеток: обычная, зелёная
# допустимая или красная занятая/выходящая за границы.
func _update_cell_highlights() -> void:
	var entry := inventory_data.get_item(_dragging_uid)
	var definition := inventory_data.get_definition(StringName(entry.get("item_id", "")))
	var footprint := _get_footprint(definition, _dragging_rotated)

	for index in range(_cell_panels.size()):
		var x := index % inventory_data.grid_size.x
		var y := floori(float(index) / float(inventory_data.grid_size.x))
		var inside_preview := (
			x >= _candidate_position.x
			and y >= _candidate_position.y
			and x < _candidate_position.x + footprint.x
			and y < _candidate_position.y + footprint.y
		)

		var state := 0
		if inside_preview:
			state = 1 if _candidate_valid else 2
		_set_cell_highlight(index, state)


# Завершает drag: только допустимая позиция передаётся в модель. При ошибке
# карточки пересоздаются из исходных данных, поэтому предмет не теряется.
func _finish_drag() -> void:
	var item_uid := _dragging_uid
	var target_position := _candidate_position
	var target_rotated := _dragging_rotated
	var can_drop := _candidate_valid

	_dragging_uid = -1
	_dragging_button = null
	_clear_cell_highlights()

	if can_drop:
		inventory_data.move_item(item_uid, target_position, target_rotated)
	else:
		_rebuild_items()


# Отменяет текущий drag, например при закрытии инвентаря, не меняя модель.
func _cancel_drag() -> void:
	if _dragging_uid < 0:
		return

	_dragging_uid = -1
	_dragging_button = null
	_clear_cell_highlights()
	_rebuild_items()


func _clear_cell_highlights() -> void:
	# Возвращает все клетки к обычному стилю после успешного или отменённого drag.
	for index in range(_cell_panels.size()):
		_set_cell_highlight(index, 0)


# Преобразует клеточные координаты в пиксельную позицию внутри board.
func _cell_to_pixel(cell_position: Vector2i) -> Vector2:
	return Vector2(cell_position) * (cell_size + cell_gap)


# Возвращает положение мыши в системе координат board, учитывая положение панели
# и масштаб canvas. Это устраняет расхождение между курсором и сеткой.
func _mouse_to_board_local() -> Vector2:
	# Координаты мыши и board могут находиться в разных Control-узлах.
	# Переводим их через canvas transform, поэтому масштаб окна и положение
	# панели не требуют отдельных поправок.
	var mouse_global := get_global_mouse_position()
	return _board.get_global_transform_with_canvas().affine_inverse() * mouse_global


# Преобразует пиксельную позицию board в клетку. Округление выполняется только
# здесь, поэтому все части drag используют одинаковые границы клеток.
func _pixel_to_grid_cell(board_position: Vector2) -> Vector2i:
	var step := cell_size + cell_gap
	return Vector2i(floori(board_position.x / step), floori(board_position.y / step))


# Возвращает клетку внутри footprint, в которой был клик, не выходя за границы
# предмета даже при попадании по отступу или краю карточки.
func _pixel_to_cell_in_footprint(pixel_position: Vector2, footprint: Vector2i) -> Vector2i:
	var cell := _pixel_to_grid_cell(pixel_position)
	return Vector2i(
		clampi(cell.x, 0, maxi(footprint.x - 1, 0)),
		clampi(cell.y, 0, maxi(footprint.y - 1, 0))
	)


# Возвращает фактический прямоугольник предмета после учёта поворота.
func _get_footprint(definition: ItemDefinition, rotated: bool) -> Vector2i:
	if definition == null:
		return Vector2i.ONE
	return Vector2i(definition.size.y, definition.size.x) if rotated else definition.size


# Переводит размер в клетках в размер карточки. Промежуток добавляется только
# между клетками, поэтому предмет 1×2 не превращается в квадрат.
func _footprint_to_pixels(footprint: Vector2i) -> Vector2:
	return Vector2(
		footprint.x * cell_size + (footprint.x - 1) * cell_gap,
		footprint.y * cell_size + (footprint.y - 1) * cell_gap
	)


# Меняет стиль только у клеток, состояние которых действительно изменилось.
# Это уменьшает количество создаваемых Control-ресурсов во время drag.
func _set_cell_highlight(index: int, state: int) -> void:
	if _cell_highlight_states[index] == state:
		return
	_cell_highlight_states[index] = state
	_cell_panels[index].add_theme_stylebox_override("panel", _get_cell_style(state))


func _get_cell_style(state: int) -> StyleBoxFlat:
	# Кэширует три стиля клеток, чтобы движение мыши не создавало новые StyleBoxFlat
	# для каждой клетки на каждом событии InputEventMouseMotion.
	if _cell_styles.has(state):
		return _cell_styles[state] as StyleBoxFlat

	var background := Color(0.075, 0.09, 0.11, 1.0)
	var border := Color(0.19, 0.23, 0.27, 1.0)
	if state == 1:
		background = Color(0.12, 0.34, 0.2, 0.95)
		border = Color(0.38, 0.92, 0.55, 1.0)
	elif state == 2:
		background = Color(0.38, 0.12, 0.12, 0.95)
		border = Color(1.0, 0.42, 0.36, 1.0)

	var style := _make_cell_style(background, border)
	_cell_styles[state] = style
	return style


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.08, 0.98)
	style.border_color = Color(0.28, 0.33, 0.39, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _make_cell_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style
