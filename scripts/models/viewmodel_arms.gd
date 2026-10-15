class_name ViewmodelArms
extends Node3D
## First-person forearms built by Models.build_viewmodel_arms(). The gun's grip sits at the
## origin inside the right hand, forward -Z. attach_gun() puts a gun under "GunMount" and moves
## the left hand onto the gun's "Support" marker; one-handed weapons (knife) hide the left arm.
## Meshes never cast shadows; set visual layers with Models.set_render().

## Elbows sit behind, below and outside the hands, so the forearms run out of a typical view.
const ELBOW_R := Vector3(0.13, -0.24, 0.42)
const ELBOW_L := Vector3(-0.22, -0.27, 0.34)
## Left-hand point used until a gun is attached (a rifle handguard).
const DEFAULT_SUPPORT := Vector3(0.0, 0.005, -0.3)
const RIGHT_HAND := Vector3(0.0, -0.012, 0.012)

var outfit_id := ""
var _arm_r: Node3D
var _arm_l: Node3D
var _mount: Node3D
var _meshes: Array[MeshInstance3D] = []


## Builds the arms. Called by Models.build_viewmodel_arms().
func setup(p_outfit_id: String) -> void:
	name = "ViewmodelArms"
	_mount = Node3D.new()
	_mount.name = "GunMount"
	add_child(_mount)
	_arm_r = _arm("ArmR", "forearm_r")
	_arm_l = _arm("ArmL", "forearm_l")
	_place(_arm_r, RIGHT_HAND, ELBOW_R)
	_place(_arm_l, DEFAULT_SUPPORT, ELBOW_L)
	set_outfit(p_outfit_id)


func set_outfit(p_outfit_id: String) -> void:
	outfit_id = p_outfit_id
	var mat := Models.outfit_material(outfit_id)
	for m in _meshes:
		m.material_override = mat


## Replaces (and frees) whatever is under GunMount with `gun`, then fits the left hand.
func attach_gun(gun: Node3D) -> void:
	for c in _mount.get_children():
		_mount.remove_child(c)
		c.queue_free()
	if gun:
		_mount.add_child(gun)
	fit_to_gun(gun)


## Moves the left hand onto `gun`'s Support marker, or hides the left arm if it has none.
func fit_to_gun(gun: Node3D) -> void:
	var support := gun.get_node_or_null(^"Support") as Node3D if gun else null
	_arm_l.visible = support != null
	if support:
		_place(_arm_l, _mount.transform * (gun.transform * support.position), ELBOW_L)


func get_gun_mount() -> Node3D:
	return _mount


func _arm(arm_name: String, part: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = arm_name
	add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = Models.avatar_part_mesh(part)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	_meshes.append(mi)
	return pivot


## Puts the hand end of a forearm at `hand` with the elbow end towards `elbow`.
static func _place(arm: Node3D, hand: Vector3, elbow: Vector3) -> void:
	arm.position = hand
	arm.basis = Basis(Quaternion(Vector3.UP, (elbow - hand).normalized()))
