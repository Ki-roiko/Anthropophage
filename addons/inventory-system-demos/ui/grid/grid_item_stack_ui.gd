
@tool
extends GridDraggableElementUI
class_name GridItemStackUI

signal activated
signal clicked
signal middle_clicked
signal context_activated(event: InputEvent)

@export var stack_style: StyleBox
@export var hover_stack_style: StyleBox
@export var selected_stack_style: StyleBox

@onready var texture_bg: Panel = $TextureBG
@onready var item_icon: TextureRect = %ItemIcon
@onready var stack_size_label: Label = $StackSizeLabel
@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var audio_stream_player_2: AudioStreamPlayer = $AudioStreamPlayer2

var inventory: GridInventory
var stack: ItemStack
var _last_is_rotated: bool = false
static var active_drag_preview: GridItemStackUI
var drag_is_rotated: bool = false

func setup(inv: Inventory, new_stack: ItemStack) -> void:
	inventory = inv
	stack = new_stack

	if stack and inventory != null:
		var definition: ItemDefinition = inventory.database.get_item(stack.item_id)

		_last_is_rotated = inventory.is_stack_rotated(stack)

		if definition != null:
			tooltip_text = definition.description

			var texture: Texture2D = definition.icon

			if texture != null and _last_is_rotated:
				var image := texture.get_image()
				if image != null:
					image.rotate_90(CLOCKWISE)
					texture = ImageTexture.create_from_image(image)

			%ItemIcon.texture = texture

		activate()
		_disconnect_item_signals()
		_connect_item_signals(stack)
	else:
		%ItemIcon.texture = null
		deactivate()

	_update_stack_size()

func _get_drag_data(at_position: Vector2):
	drag_is_rotated = inventory.is_stack_rotated(stack)
	return super._get_drag_data(at_position)

func _connect_item_signals(new_item: ItemStack) -> void:
	if new_item == null:
		return

	if not new_item.updated.is_connected(_refresh):
		new_item.updated.connect(_refresh)

	if inventory != null and not inventory.updated_stack.is_connected(_update_stack_index):
		inventory.updated_stack.connect(_update_stack_index)


func _disconnect_item_signals() -> void:
	if not is_instance_valid(stack):
		return

	if stack.updated.is_connected(_refresh):
		stack.updated.disconnect(_refresh)

	if inventory != null and inventory.updated_stack.is_connected(_update_stack_index):
		inventory.updated_stack.disconnect(_update_stack_index)


func _ready() -> void:
	_set_panel_style(stack_style)

	mouse_entered.connect(func():
		_set_panel_style(hover_stack_style)
		audio_stream_player_2.play()
	)

	mouse_exited.connect(func():
		_set_panel_style(stack_style)
	)

	grabbed.connect(func(_offset):
		visible = false
		audio_stream_player.play()
	)

	if stack == null:
		deactivate()

	_refresh()


func _update_stack_index(_stack_index: int) -> void:
	_refresh()


func _refresh() -> void:
	_update_stack_size()
	_refresh_item_visual()


func _refresh_item_visual() -> void:
	if not is_instance_valid(item_icon):
		return

	if not is_instance_valid(stack) or inventory == null:
		item_icon.texture = null
		return

	var definition: ItemDefinition = inventory.database.get_item(stack.item_id)

	if definition == null or definition.icon == null:
		item_icon.texture = null
		return

	var rotated := inventory.is_stack_rotated(stack)

	if rotated != _last_is_rotated:
		size = Vector2(size.y, size.x)
		_last_is_rotated = rotated

	var texture: Texture2D = definition.icon

	if rotated:
		var image := texture.get_image()

		if image != null:
			image.rotate_90(CLOCKWISE)
			texture = ImageTexture.create_from_image(image)

	item_icon.texture = texture


func select() -> void:
	if is_instance_valid(selected_stack_style):
		_set_panel_style(selected_stack_style)


func unselect() -> void:
	_set_panel_style(stack_style)


func _notification(what) -> void:
	if what == NOTIFICATION_DRAG_END:
		visible = true


func _update_stack_size() -> void:
	if not is_instance_valid(stack_size_label):
		return

	if not is_instance_valid(stack):
		stack_size_label.text = ""
		return

	var stack_size: int = stack.amount

	if stack_size <= 1:
		if stack.properties.has("durability"):
			var definition: ItemDefinition = inventory.database.get_item(stack.item_id)

			if definition != null:
				var actual: float = stack.properties["durability"]
				var total: float = definition.properties["durability"]
				stack_size_label.text = str(int(actual / total * 100.0)) + "%"
				return
	else:
		stack_size_label.text = "%d" % stack_size
		return

	stack_size_label.text = ""


func create_preview() -> Control:
	var preview := duplicate() as GridItemStackUI
	preview.setup(inventory, stack)
	preview.visible = true

	active_drag_preview = preview

	preview.call_deferred("set_visual_rotation", drag_is_rotated)

	return preview

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	var mb_event: InputEventMouseButton = event

	if not mb_event.pressed:
		return

	if mb_event.button_index == MOUSE_BUTTON_LEFT:
		if mb_event.double_click:
			activated.emit()
		else:
			clicked.emit()

	if mb_event.button_index == MOUSE_BUTTON_MIDDLE:
		middle_clicked.emit()
	elif mb_event.button_index == MOUSE_BUTTON_MASK_RIGHT:
		context_activated.emit(mb_event)


func _set_panel_style(style: StyleBox) -> void:
	remove_theme_stylebox_override("panel")

	if style != null:
		add_theme_stylebox_override("panel", style)

func set_visual_rotation(rotated: bool) -> void:
	if not is_instance_valid(stack) or inventory == null:
		return

	var definition: ItemDefinition = inventory.database.get_item(stack.item_id)

	if definition == null or definition.icon == null:
		return

	if rotated != _last_is_rotated:
		size = Vector2(size.y, size.x)
		_last_is_rotated = rotated

	var texture := definition.icon

	if rotated:
		var image := texture.get_image()
		image.rotate_90(CLOCKWISE)
		texture = ImageTexture.create_from_image(image)

	item_icon.texture = texture
