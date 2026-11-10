class_name InventoryDataModel
extends Node
## Хранит экземпляры предметов и отвечает за размещение в сетке 8×6.

signal inventory_changed

@export var grid_size: Vector2i = Vector2i(8, 6)

const ITEM_DEFINITIONS: Dictionary = {
	&"bandage": preload("res://resources/items/bandage.tres"),
	&"metal_scrap": preload("res://resources/items/metal_scrap.tres"),
	&"toolbox": preload("res://resources/items/toolbox.tres"),
}

var _items: Array[Dictionary] = []
var _next_uid: int = 1


func get_definition(item_id: StringName) -> ItemDefinition:
	return ITEM_DEFINITIONS.get(item_id) as ItemDefinition


func get_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _items:
		result.append(entry.duplicate(true))
	return result


func get_item(item_uid: int) -> Dictionary:
	for entry in _items:
		if int(entry.get("uid", -1)) == item_uid:
			return entry.duplicate(true)
	return {}


## Добавляет сколько получится и возвращает количество, которое не поместилось.
func add_item(item_id: StringName, amount: int = 1) -> int:
	var definition := get_definition(item_id)
	if definition == null or amount <= 0:
		return amount

	var remaining := amount

	# Сначала заполняем уже существующие стаки этого предмета.
	for index in range(_items.size()):
		var entry: Dictionary = _items[index]
		if StringName(entry.get("item_id", "")) != item_id:
			continue

		var current_amount := int(entry.get("amount", 0))
		var available := definition.max_stack_size - current_amount
		if available <= 0:
			continue

		var added := mini(available, remaining)
		entry["amount"] = current_amount + added
		_items[index] = entry
		remaining -= added

		if remaining <= 0:
			inventory_changed.emit()
			return 0

	# Оставшееся количество раскладываем по новым ячейкам.
	while remaining > 0:
		var position := _find_free_position(definition.size, false)
		if position.x < 0:
			break

		var stack_amount := mini(definition.max_stack_size, remaining)
		_items.append({
			"uid": _next_uid,
			"item_id": item_id,
			"amount": stack_amount,
			"position": position,
			"rotated": false,
		})
		_next_uid += 1
		remaining -= stack_amount

	if remaining != amount:
		inventory_changed.emit()

	return remaining


## Удаляет указанное количество. amount = -1 удаляет весь экземпляр.
## Возвращает фактически удалённое количество.
func remove_item(item_uid: int, amount: int = -1) -> int:
	var index := _find_item_index(item_uid)
	if index < 0:
		return 0

	var entry: Dictionary = _items[index]
	var current_amount := int(entry.get("amount", 0))
	var remove_amount := current_amount if amount < 0 else mini(amount, current_amount)

	if remove_amount <= 0:
		return 0

	var remaining := current_amount - remove_amount
	if remaining <= 0:
		_items.remove_at(index)
	else:
		entry["amount"] = remaining
		_items[index] = entry

	inventory_changed.emit()
	return remove_amount


## Проверяет, можно ли поставить экземпляр в указанную позицию.
## При проверке не учитываются клетки самого перемещаемого предмета.
func can_place(item_uid: int, position: Vector2i, rotated: bool) -> bool:
	var entry := get_item(item_uid)
	if entry.is_empty():
		return false

	return _can_place(
		StringName(entry["item_id"]),
		position,
		rotated,
		item_uid
	)


func move_item(item_uid: int, position: Vector2i, rotated: bool) -> bool:
	var index := _find_item_index(item_uid)
	if index < 0:
		return false

	var entry: Dictionary = _items[index]
	if not _can_place(StringName(entry["item_id"]), position, rotated, item_uid):
		return false

	entry["position"] = position
	entry["rotated"] = rotated
	_items[index] = entry
	inventory_changed.emit()
	return true


func _find_item_index(item_uid: int) -> int:
	for index in range(_items.size()):
		if int(_items[index].get("uid", -1)) == item_uid:
			return index
	return -1


func _find_free_position(item_size: Vector2i, rotated: bool) -> Vector2i:
	var footprint := item_size
	if rotated:
		footprint = Vector2i(item_size.y, item_size.x)

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var position := Vector2i(x, y)
			if _can_place_size(footprint, position, -1):
				return position

	return Vector2i(-1, -1)


func _can_place(
	item_id: StringName,
	position: Vector2i,
	rotated: bool,
	ignore_uid: int
) -> bool:
	var definition := get_definition(item_id)
	if definition == null:
		return false

	var footprint := definition.size
	if rotated:
		footprint = Vector2i(definition.size.y, definition.size.x)

	return _can_place_size(footprint, position, ignore_uid)


func _can_place_size(
	footprint: Vector2i,
	position: Vector2i,
	ignore_uid: int
) -> bool:
	if footprint.x <= 0 or footprint.y <= 0:
		return false
	if position.x < 0 or position.y < 0:
		return false
	if position.x + footprint.x > grid_size.x:
		return false
	if position.y + footprint.y > grid_size.y:
		return false

	for y in range(position.y, position.y + footprint.y):
		for x in range(position.x, position.x + footprint.x):
			if _is_cell_occupied(Vector2i(x, y), ignore_uid):
				return false

	return true


func _is_cell_occupied(cell: Vector2i, ignore_uid: int) -> bool:
	for entry in _items:
		if int(entry.get("uid", -1)) == ignore_uid:
			continue

		var definition := get_definition(StringName(entry.get("item_id", "")))
		if definition == null:
			continue

		var footprint := definition.size
		if bool(entry.get("rotated", false)):
			footprint = Vector2i(definition.size.y, definition.size.x)

		var origin: Vector2i = entry.get("position", Vector2i.ZERO)
		if (
			cell.x >= origin.x
			and cell.y >= origin.y
			and cell.x < origin.x + footprint.x
			and cell.y < origin.y + footprint.y
		):
			return true

	return false
