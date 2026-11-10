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
var _item_buttons: Dictionary = {}

var _dragging_uid: int = -1
var _dragging_button: Button
var _drag_offset_px: Vector2 = Vector2.ZERO
var _candidate_position: Vector2i = Vector2i.ZERO
var _candidate_valid: bool = false
var _dragging_rotated: bool = false

var _mouse_mode_before_open: int = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_build_interface()
	inventory_data.inventory_changed.connect(_on_inventory_changed)
	set_process_input(true)


func open_inventory() -> void:
	if is_open:
		return

	_mouse_mode_before_open = Input.mouse_mode
	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_items()


func close_inventory() -> void:
	if not is_open:
		return

	_cancel_drag()
	is_open = false
	visible = false
	Input.mouse_mode = _mouse_mode_before_open


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
			_dragging_rotated = not _dragging_rotated
			if _dragging_button != null:
				_drag_offset_px = _dragging_button.size * 0.5
			_update_drag_preview()
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
	if _dragging_uid < 0:
		_rebuild_items()


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

		var footprint := definition.size
		if bool(entry.get("rotated", false)):
			footprint = Vector2i(definition.size.y, definition.size.x)

		var button_size := Vector2(
			footprint.x * cell_size + (footprint.x - 1) * cell_gap,
			footprint.y * cell_size + (footprint.y - 1) * cell_gap
		)

		var button := Button.new()
		button.position = _cell_to_pixel(entry.get("position", Vector2i.ZERO))
		button.size = button_size
		button.custom_minimum_size = button_size
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

	_dragging_uid = item_uid
	_dragging_button = button
	_drag_offset_px = event.position
	var entry := inventory_data.get_item(item_uid)
	_dragging_rotated = bool(entry.get("rotated", false))
	_dragging_button.z_index = 10
	_dragging_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_drag_preview()
	get_viewport().set_input_as_handled()


func _update_drag_preview() -> void:
	if _dragging_uid < 0 or _dragging_button == null:
		return

	var top_left_global := get_global_mouse_position() - _drag_offset_px
	var board_local := _board.to_local(top_left_global)
	var step := cell_size + cell_gap
	_candidate_position = Vector2i(
		floori(board_local.x / step),
		floori(board_local.y / step)
	)
	_candidate_valid = inventory_data.can_place(
		_dragging_uid,
		_candidate_position,
		_dragging_rotated
	)

	var entry := inventory_data.get_item(_dragging_uid)
	var definition := inventory_data.get_definition(StringName(entry.get("item_id", "")))
	if definition != null:
		var footprint := definition.size
		if _dragging_rotated:
			footprint = Vector2i(definition.size.y, definition.size.x)
		_dragging_button.size = Vector2(
			footprint.x * cell_size + (footprint.x - 1) * cell_gap,
			footprint.y * cell_size + (footprint.y - 1) * cell_gap
		)

	_dragging_button.position = Vector2(_candidate_position) * step
	_dragging_button.modulate = (
		Color(0.62, 1.0, 0.7, 0.94)
		if _candidate_valid
		else Color(1.0, 0.52, 0.48, 0.9)
	)
	_update_cell_highlights()


func _update_cell_highlights() -> void:
	var step := cell_size + cell_gap
	var entry := inventory_data.get_item(_dragging_uid)
	var definition := inventory_data.get_definition(StringName(entry.get("item_id", "")))
	var footprint := Vector2i.ONE
	if definition != null:
		footprint = definition.size
		if _dragging_rotated:
			footprint = Vector2i(footprint.y, footprint.x)

	for index in range(_cell_panels.size()):
		var x := index % inventory_data.grid_size.x
		var y := floori(float(index) / float(inventory_data.grid_size.x))
		var inside_preview := (
			x >= _candidate_position.x
			and y >= _candidate_position.y
			and x < _candidate_position.x + footprint.x
			and y < _candidate_position.y + footprint.y
		)

		var background := Color(0.075, 0.09, 0.11, 1.0)
		var border := Color(0.19, 0.23, 0.27, 1.0)
		if inside_preview:
			if _candidate_valid:
				background = Color(0.12, 0.34, 0.2, 0.95)
				border = Color(0.38, 0.92, 0.55, 1.0)
			else:
				background = Color(0.38, 0.12, 0.12, 0.95)
				border = Color(1.0, 0.42, 0.36, 1.0)

		_cell_panels[index].add_theme_stylebox_override(
			"panel",
			_make_cell_style(background, border)
		)


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


func _cancel_drag() -> void:
	if _dragging_uid < 0:
		return

	_dragging_uid = -1
	_dragging_button = null
	_clear_cell_highlights()
	_rebuild_items()


func _clear_cell_highlights() -> void:
	for cell in _cell_panels:
		cell.add_theme_stylebox_override(
			"panel",
			_make_cell_style(Color(0.075, 0.09, 0.11, 1.0), Color(0.19, 0.23, 0.27, 1.0))
		)


func _cell_to_pixel(position: Vector2i) -> Vector2:
	return Vector2(position) * (cell_size + cell_gap)


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
