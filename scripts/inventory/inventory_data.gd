class_name InventoryDataModel
extends Node
## Хранит экземпляры предметов и отвечает за размещение в сетке 8×6.

const ITEM_CATALOG = preload("res://scripts/item_catalog.gd")
const DEFAULT_GRID_SIZE := Vector2i(6, 4)
const MAX_GRID_SIDE := 64

signal inventory_changed
signal invalid_item_detected(item_uid: int, item_id: StringName)

@export var grid_size: Vector2i = DEFAULT_GRID_SIZE

var _items: Array[Dictionary] = []
var _next_uid: int = 1
var _reported_invalid_uids: Dictionary = {}


# Проверяет настройки модели сразу после создания узла.
# Это защищает сетку от нулевых размеров и сообщает о неизвестных предметах,
# не удаляя такие записи молча из данных инвентаря.
func _ready() -> void:
	_validate_grid_size()
	_validate_items()


# Возвращает описание предмета из общего каталога.
# UI и WorldItem получают свойства через эту функцию, чтобы не хранить
# отдельные копии таблицы предметов в разных системах.
func get_definition(item_id: StringName) -> ItemDefinition:
	return ITEM_CATALOG.get_definition(item_id)


# Возвращает безопасный размер сетки после проверки его границ.
# UI использует его при создании клеток и расчёте размеров панели.
func get_grid_size() -> Vector2i:
	_validate_grid_size()
	return grid_size


# Восстанавливает допустимый размер сетки, если значение в сцене или сохранении
# оказалось нулевым, отрицательным или слишком большим.
func _validate_grid_size() -> void:
	if (
		grid_size.x > 0
		and grid_size.y > 0
		and grid_size.x <= MAX_GRID_SIDE
		and grid_size.y <= MAX_GRID_SIDE
	):
		return
	if grid_size.x <= 0 or grid_size.y <= 0 or grid_size.x > MAX_GRID_SIDE or grid_size.y > MAX_GRID_SIDE:
		push_error("InventoryData: недопустимый grid_size %s. Возвращён размер 8×6." % grid_size)
		grid_size = DEFAULT_GRID_SIZE


# Ищет неизвестные item_id в уже загруженных записях.
# Запись оставляется в модели, чтобы содержимое сохранения не исчезло без следа;
# вместо этого отправляется сигнал и выводится понятная ошибка диагностики.
func _validate_items() -> void:
	for entry in _items:
		var item_uid := int(entry.get("uid", -1))
		var item_id := StringName(entry.get("item_id", ""))
		if get_definition(item_id) == null and not _reported_invalid_uids.has(item_uid):
			_reported_invalid_uids[item_uid] = true
			push_error("InventoryData: неизвестный item_id '%s' у предмета UID %d. Данные сохранены в модели для диагностики." % [item_id, item_uid])
			invalid_item_detected.emit(item_uid, item_id)


# Возвращает копии записей, чтобы внешний код не мог случайно изменить модель
# напрямую, обходя проверки перемещения и сигнал inventory_changed.
func get_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _items:
		result.append(entry.duplicate(true))
	return result


# Возвращает копию одного экземпляра по UID.
# UID относится к конкретной записи или стопке, а item_id — к типу предмета.
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

	# Сначала заполняем существующие стаки: так свободные клетки не расходуются,
	# пока в старых стопках ещё есть место.
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

	# Оставшееся количество раскладываем по новым ячейкам. _find_free_placement
	# проверяет обычную ориентацию и затем повернутую, поэтому добавление через
	# игровой код использует те же правила, что и ручное размещение в UI.
	while remaining > 0:
		var placement := _find_free_placement(definition.size)
		var position: Vector2i = placement.get("position", Vector2i(-1, -1))
		if position.x < 0:
			break

		var stack_amount := mini(definition.max_stack_size, remaining)
		_items.append({
			"uid": _next_uid,
			"item_id": item_id,
			"amount": stack_amount,
			"position": position,
			"rotated": bool(placement.get("rotated", false)),
		})
		_next_uid += 1
		remaining -= stack_amount

	if remaining != amount:
		inventory_changed.emit()

	return remaining


func _find_free_placement(item_size: Vector2i) -> Dictionary:
	var position := _find_free_position(item_size, false)
	if position.x >= 0:
		return {"position": position, "rotated": false}
	position = _find_free_position(item_size, true)
	return {"position": position, "rotated": position.x >= 0}


## Удаляет указанное количество. amount = -1 удаляет весь экземпляр.
## Возвращает фактически удалённое количество.
# Удаляет часть или всю стопку предмета и возвращает фактически удалённое
# количество. Сигнал нужен UI, чтобы он обновил карточки после изменения модели.
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


# Перемещает предмет только после полной проверки. Модель получает координаты
# верхней левой клетки и флаг поворота, а UI отвечает только за отображение.
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


# Находит индекс записи в массиве по UID. Внутренние функции используют индекс,
# потому что записи могут удаляться из массива при выбрасывании предмета.
func _find_item_index(item_uid: int) -> int:
	for index in range(_items.size()):
		if int(_items[index].get("uid", -1)) == item_uid:
			return index
	return -1


# Перебирает клетки слева направо и сверху вниз и ищет первое свободное место.
# Сначала пробуется исходный размер, затем размер с поменянными сторонами.
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


# Проверяет размещение конкретного типа предмета с учётом поворота.
# ignore_uid позволяет перемещать предмет поверх его собственных клеток.
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


# Проверяет границы и каждую клетку прямоугольной области предмета.
# Здесь нет UI-логики, поэтому этот метод остаётся единственным источником
# истины для пересечений и выхода за пределы сетки.
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


# Определяет, занята ли клетка другим экземпляром. Размер берётся из описания,
# а не из карточки UI, поэтому визуальное состояние не может изменить правила
# хранения предметов.
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
