extends RigidBody3D
class_name WorldItem

@export var item_name: String
@export var item_id: String
@export var item_properties: Dictionary

@export_file("*.glb") var item_mesh: String


func _ready() -> void:
    if item_mesh.is_empty():
        return

    var packed_scene := load(item_mesh) as PackedScene

    if packed_scene == null:
        push_error("Не удалось загрузить модель: " + item_mesh)
        return

    var visual := packed_scene.instantiate()
    visual.name = "ItemVisual"
    add_child(visual)

    if Engine.is_editor_hint():
        visual.owner = get_tree().edited_scene_root

    _create_collision(visual)


func _create_collision(visual: Node) -> void:
    var mesh_nodes: Array[MeshInstance3D] = []

    if visual is MeshInstance3D:
        mesh_nodes.append(visual)

    for node in visual.find_children("*", "MeshInstance3D", true, false):
        mesh_nodes.append(node as MeshInstance3D)

    for i in range(mesh_nodes.size()):
        var mesh_instance := mesh_nodes[i]

        if mesh_instance.mesh == null:
            continue

        var collision := CollisionShape3D.new()
        collision.name = "AutoCollision_%d" % i
        collision.shape = mesh_instance.mesh.create_convex_shape()

        add_child(collision)

        collision.transform = (
            global_transform.affine_inverse()
            * mesh_instance.global_transform
        )

        if Engine.is_editor_hint():
            collision.owner = get_tree().edited_scene_root