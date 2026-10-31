class_name MapEditor
extends Node3D
## The Map Editor (main menu > PLAY > MAP EDITOR, scene scenes/map_editor.tscn): builds a
## CustomMaps map block by block. A FreeCam flies over the map; the aim ray (a voxel walk through
## the grid, `aim`) picks the block face under the crosshair. The `tool` decides what the place
## (fire: left mouse / RT) and remove (aim: right mouse / LT) presses do: BLOCK places the
## hotbar's block on the aimed face (brush 1 or 3 x 3 across the face) and removes the aimed
## block(s); SPAWN / HEALTH / AMMO / GRENADE put a marker on the aimed top face or remove the
## nearest one; JUMP PAD takes the pad, then the landing. A translucent ghost shows where the next
## press lands. Edits go through the VoxelMesher of an editable build (set_cells, then
## mesh_chunks / apply_chunk of the touched chunks on the spot) and onto the undo stack
## (UNDO_MAX steps; block edits store the cells' old and new ids, marker edits the marker lists).
## MapEditorHud is the screen: hotbar, info, validation, and the side panel (Tab / Esc / Start)
## with new / open / save, name, sky, tools, palette, undo / redo, test play and exit.

signal changed
signal message(text: String, error: bool)

const SCENE := "res://scenes/map_editor.tscn"
const TOOLS: Array[String] = ["block", "spawn", "health", "ammo", "grenade", "pad"]
const TOOL_NAMES := {"block": "BLOCKS", "spawn": "SPAWN", "health": "HEALTH", "ammo": "AMMO",
	"grenade": "GRENADES", "pad": "JUMP PAD"}
const TOOL_COLORS := {"block": Color("ffd166"), "spawn": Color("6ee7a0"), "health": Color("ff6b6b"),
	"ammo": Color("ffd166"), "grenade": Color("9fb3c8"), "pad": Color(0.25, 1.0, 0.85)}
## Every block the palette offers, in order, with its name.
const PALETTE := [
	[BlockAtlas.GRASS, "Grass"], [BlockAtlas.DIRT, "Dirt"], [BlockAtlas.STONE, "Stone"], [BlockAtlas.COBBLE, "Cobble"],
	[BlockAtlas.GRAVEL, "Gravel"], [BlockAtlas.SAND, "Sand"], [BlockAtlas.SANDSTONE, "Sandstone"], [BlockAtlas.CARVED, "Carved"],
	[BlockAtlas.PLANKS, "Planks"], [BlockAtlas.DARK_PLANKS, "Dark planks"], [BlockAtlas.LOG, "Log"], [BlockAtlas.LEAVES, "Leaves"],
	[BlockAtlas.PINE, "Pine"], [BlockAtlas.PINE_SNOW, "Snowy pine"], [BlockAtlas.BRICK, "Brick"], [BlockAtlas.STONE_BRICK, "Stone brick"],
	[BlockAtlas.MOSSY_BRICK, "Mossy brick"], [BlockAtlas.ROOF, "Roof"], [BlockAtlas.CONCRETE, "Concrete"], [BlockAtlas.METAL, "Metal"],
	[BlockAtlas.GRATE, "Grate"], [BlockAtlas.CONVEYOR, "Conveyor"], [BlockAtlas.HAZARD, "Hazard"], [BlockAtlas.CRATE, "Crate"],
	[BlockAtlas.CONTAINER_RED, "Red container"], [BlockAtlas.CONTAINER_BLUE, "Blue container"],
	[BlockAtlas.CONTAINER_GREEN, "Green container"], [BlockAtlas.CONTAINER_YELLOW, "Yellow container"],
	[BlockAtlas.SNOW, "Snow"], [BlockAtlas.SNOW_BLOCK, "Snow block"], [BlockAtlas.ICE, "Ice"], [BlockAtlas.GLASS, "Glass"],
	[BlockAtlas.LAMP, "Lamp"], [BlockAtlas.GOLD, "Gold"], [BlockAtlas.WATER, "Water"], [BlockAtlas.WHITE, "White"],
	[BlockAtlas.RED, "Red"], [BlockAtlas.ORANGE, "Orange"], [BlockAtlas.YELLOW, "Yellow"], [BlockAtlas.GREEN, "Green"],
	[BlockAtlas.TEAL, "Teal"], [BlockAtlas.BLUE, "Blue"],
]
const DEFAULT_HOTBAR: Array[int] = [BlockAtlas.GRASS, BlockAtlas.DIRT, BlockAtlas.STONE, BlockAtlas.COBBLE,
	BlockAtlas.PLANKS, BlockAtlas.BRICK, BlockAtlas.CONCRETE, BlockAtlas.GLASS, BlockAtlas.LAMP]
const DEFAULT_NAME := "My Map"
## How far the aim ray reaches (m).
const REACH := 90.0
const UNDO_MAX := 200
## A remove press with a marker tool takes the nearest marker this close to the aimed spot (m).
const MARKER_PICK := 1.6

var map := {}
var grid: VoxelGrid
## World position of grid cell (0,0,0) (the grid is centred on the origin, like MapBuilder's).
var origin := Vector3.ZERO
var tool := "block"
var hotbar: Array[int] = DEFAULT_HOTBAR.duplicate()
var slot := 0
## 1 or 3 (3 x 3 cells across the aimed face).
var brush := 1
## The aimed block: {cell: Vector3i, normal: Vector3i} or {} when the ray hits nothing.
var aim := {}
## Changes since the last save or load.
var unsaved := false
## The saved file (name) this map was opened from or last saved to; "" for a new, unsaved map.
## A save under a different name moves the map: the old file goes once the new one is written.
var file_name := ""
## JUMP PAD: the pad's feet position (grid space) once the first press placed it, else null.
var pad_start: Variant = null
var cam: FreeCam
var hud: MapEditorHud

var _mesher: VoxelMesher
var _map_root: Node3D
var _env_root: Node3D
var _markers: Node3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _undo: Array = []
var _redo: Array = []


func _ready() -> void:
	_env_root = Node3D.new()
	_env_root.name = "Environment"
	add_child(_env_root)
	_markers = Node3D.new()
	_markers.name = "Markers"
	add_child(_markers)
	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost.mesh = BoxMesh.new()
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.no_depth_test = false
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	cam = FreeCam.new()
	add_child(cam)
	cam.current = true
	hud = MapEditorHud.new()
	hud.editor = self
	add_child(hud)
	Sfx.play_music(&"menu")
	new_map(CustomMaps.PRESETS[1])
	hud.open_panel()


# ---------------------------------------------------------------- map lifecycle

## Starts a fresh map of `size` (a flat floor), named DEFAULT_NAME.
func new_map(size: Vector3i) -> void:
	_open(CustomMaps.new_map(size, DEFAULT_NAME))
	file_name = ""
	message.emit("New %d x %d map. Build away." % [size.x, size.z], false)


## Opens the saved map `map_name`; false (and a message) when it can't be read.
func load_saved(map_name: String) -> bool:
	var m := CustomMaps.load_map(map_name)
	if m.is_empty():
		message.emit("Couldn't open %s." % map_name, true)
		return false
	_open(m)
	file_name = map_name
	message.emit("Opened %s." % map_name, false)
	return true


## Saves to user://maps/<name>.json. Returns the validation problems (saved either way, so
## unfinished maps keep; only playable maps show up in match setup). After a rename the file
## under the old name is removed, but only once the new one was written.
func save() -> PackedStringArray:
	var problems := CustomMaps.validate(map)
	var err := CustomMaps.save(map)
	if err != OK:
		message.emit("Couldn't save: %s." % error_string(err), true)
		return problems
	if not file_name.is_empty() and file_name != map.name:
		CustomMaps.renamed(file_name, map.name)
	file_name = map.name
	unsaved = false
	if problems.is_empty():
		var notes := bot_warnings()
		message.emit("Saved %s. It's in match setup under CUSTOM.%s" % [map.name, "" if notes.is_empty() else " " + notes[0]], not notes.is_empty())
	else:
		message.emit("Saved %s, but it can't be played yet: %s" % [map.name, problems[0]], true)
	changed.emit()
	return problems


func set_map_name(raw: String) -> void:
	var n := CustomMaps.sanitize_name(raw)
	if n.is_empty() or n == map.name:
		return
	map.name = n
	unsaved = true
	changed.emit()


func set_time_of_day(tod: String) -> void:
	if not tod in Data.TIMES_OF_DAY:
		return
	map.time_of_day = tod
	unsaved = true
	_build_environment()
	changed.emit()


func problems() -> PackedStringArray:
	return CustomMaps.validate(map)


## Playable-map advice: the spots bots can't route to from spawn 1 (call when problems() is empty).
func bot_warnings() -> PackedStringArray:
	return CustomMaps.unreachable(map, true)


func _open(m: Dictionary) -> void:
	map = m
	grid = m.grid
	origin = Vector3(-grid.size.x / 2, 0, -grid.size.z / 2)
	if _map_root != null:
		_map_root.free()
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child(_map_root)
	_mesher = VoxelMesher.build(grid, _map_root, origin, NavigationMeshSourceGeometryData3D.new(), Transform3D.IDENTITY, Callable(), true)
	_mesher.grow_chunks = true
	_build_environment()
	_undo.clear()
	_redo.clear()
	pad_start = null
	aim = {}
	unsaved = false
	_rebuild_markers()
	# Above the south-west corner, looking across the map.
	var corner := origin + Vector3(-2.0, 12.0, grid.size.z + 2.0)
	cam.place(Transform3D(Basis.IDENTITY, corner).looking_at(origin + Vector3(grid.size.x * 0.5, 0.0, grid.size.z * 0.5)), float(Profile.get_setting("fov")))
	cam.set_bounds(AABB(origin, Vector3(grid.size)))
	changed.emit()


func _build_environment() -> void:
	for c in _env_root.get_children():
		c.free()
	MapBuilder.add_environment(_env_root, CustomMaps.ATMOSPHERE, int(Profile.get_setting("quality")))
	World._apply_time_of_day(_env_root, str(map.time_of_day))


# ---------------------------------------------------------------- tools and selection

func set_tool(t: String) -> void:
	if t in TOOLS and t != tool:
		tool = t
		pad_start = null
		_rebuild_markers()
		changed.emit()


func cycle_tool(step: int) -> void:
	set_tool(TOOLS[wrapi(TOOLS.find(tool) + step, 0, TOOLS.size())])


func block() -> int:
	return hotbar[slot]


func select_slot(i: int) -> void:
	slot = wrapi(i, 0, hotbar.size())
	set_tool("block")
	changed.emit()


## Puts palette block `b` into the current hotbar slot (or selects the slot already holding it).
func pick_block(b: int) -> void:
	var at := hotbar.find(b)
	if at >= 0:
		slot = at
	else:
		hotbar[slot] = b
	set_tool("block")
	changed.emit()


func set_brush(n: int) -> void:
	brush = 3 if n >= 3 else 1
	changed.emit()


static func block_name(b: int) -> String:
	for e: Array in PALETTE:
		if e[0] == b:
			return e[1]
	return "Block %d" % b


# ---------------------------------------------------------------- aiming

## Walks the grid from world point `from` along `dir`: {cell, normal} of the first solid cell
## (normal: the face it entered through, zero when `from` is inside it), or {}.
func raycast(from: Vector3, dir: Vector3, reach := REACH) -> Dictionary:
	if dir.is_zero_approx():
		return {}
	dir = dir.normalized()
	var p := from - origin
	var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for a in 3:
		if dir[a] != 0.0:
			t_delta[a] = absf(1.0 / dir[a])
			var edge := float(cell[a] + (1 if step[a] > 0 else 0))
			t_max[a] = (edge - p[a]) / dir[a]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= reach:
		if grid.in_bounds(cell.x, cell.y, cell.z) and not grid.is_air(cell.x, cell.y, cell.z):
			return {"cell": cell, "normal": normal}
		var a := 0
		if t_max.y < t_max[a]:
			a = 1
		if t_max.z < t_max[a]:
			a = 2
		t = t_max[a]
		cell[a] += step[a]
		t_max[a] += t_delta[a]
		normal = Vector3i.ZERO
		normal[a] = -step[a]
	return {}


## Aims along the camera (the crosshair).
func update_aim() -> void:
	aim = raycast(cam.global_position, -cam.global_basis.z)


## The cells a brush covers around `center` across a face with `normal`.
func brush_cells(center: Vector3i, normal: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = [center]
	if brush == 1:
		return out
	var axes := _face_axes(normal)
	out.clear()
	for i in range(-1, 2):
		for j in range(-1, 2):
			out.append(center + axes[0] * i + axes[1] * j)
	return out


static func _face_axes(normal: Vector3i) -> Array[Vector3i]:
	if normal.x != 0:
		return [Vector3i(0, 1, 0), Vector3i(0, 0, 1)]
	if normal.z != 0:
		return [Vector3i(1, 0, 0), Vector3i(0, 1, 0)]
	return [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]


## Feet position (grid space) a marker tool would use on the current aim: the cell above an
## aimed top face, else null.
func aimed_feet() -> Variant:
	if aim.is_empty() or aim.normal != Vector3i(0, 1, 0):
		return null
	var c: Vector3i = aim.cell + aim.normal
	return Vector3(c.x + 0.5, c.y, c.z + 0.5)


# ---------------------------------------------------------------- actions

## The place press (fire) with the current tool on the current aim.
func use_primary() -> void:
	if aim.is_empty():
		return
	if tool == "block":
		var cells := PackedInt32Array()
		for c in brush_cells(aim.cell + aim.normal, aim.normal):
			if grid.in_bounds(c.x, c.y, c.z) and grid.is_air(c.x, c.y, c.z):
				cells.append(grid.index(c.x, c.y, c.z))
		set_blocks(cells, block())
		return
	var feet: Variant = aimed_feet()
	if feet == null:
		message.emit("Aim at the top of a block.", true)
		return
	var why := CustomMaps.spot_problem(grid, feet)
	if not why.is_empty():
		message.emit("No room there: the spot %s." % why, true)
		return
	match tool:
		"spawn":
			if map.spawns.size() >= CustomMaps.MAX_SPAWNS:
				message.emit("At most %d spawns." % CustomMaps.MAX_SPAWNS, true)
				return
			add_marker("spawn", feet)
		"pad":
			if pad_start == null:
				if map.jump_pads.size() >= CustomMaps.MAX_PADS:
					message.emit("At most %d jump pads." % CustomMaps.MAX_PADS, true)
					return
				pad_start = feet
				_rebuild_markers()
				message.emit("Pad placed. Now aim at the landing spot and place again.", false)
			elif (feet as Vector3).distance_to(pad_start) < 3.0:
				message.emit("The landing must be at least 3 m from the pad.", true)
			else:
				add_jump_pad(pad_start, feet)
				pad_start = null
		_:
			if map.pickups.size() >= CustomMaps.MAX_PICKUPS:
				message.emit("At most %d pickups." % CustomMaps.MAX_PICKUPS, true)
				return
			add_marker(tool, feet)


## The remove press (aim) with the current tool on the current aim.
func use_secondary() -> void:
	if tool == "pad" and pad_start != null:
		pad_start = null
		_rebuild_markers()
		message.emit("Jump pad cancelled.", false)
		return
	if aim.is_empty():
		return
	if tool == "block":
		var cells := PackedInt32Array()
		for c in brush_cells(aim.cell, aim.normal):
			if grid.in_bounds(c.x, c.y, c.z) and not grid.is_air(c.x, c.y, c.z):
				cells.append(grid.index(c.x, c.y, c.z))
		set_blocks(cells, BlockAtlas.AIR)
		return
	var c: Vector3i = aim.cell + aim.normal
	if not remove_marker_near(Vector3(c.x + 0.5, c.y, c.z + 0.5)):
		message.emit("No marker there.", true)


## Sets the grid cells `cells` (VoxelGrid.index values) to block `value` as one undo step.
func set_blocks(cells: PackedInt32Array, value: int) -> void:
	var changed_cells := PackedInt32Array()
	var before := PackedByteArray()
	var after := PackedByteArray()
	for i in cells:
		if grid.blocks[i] != value:
			changed_cells.append(i)
			before.append(grid.blocks[i])
			after.append(value)
	if changed_cells.is_empty():
		return
	_apply_blocks(changed_cells, after)
	_push({"cells": changed_cells, "before": before, "after": after})


## Adds a spawn or a `kind` pickup at `feet` (grid space) as one undo step.
func add_marker(kind: String, feet: Vector3) -> void:
	var before := _marker_state()
	if kind == "spawn":
		map.spawns.append(feet)
	else:
		map.pickups.append({"kind": kind, "pos": feet})
	_marker_step(before)


func add_jump_pad(pos: Vector3, target: Vector3) -> void:
	var before := _marker_state()
	map.jump_pads.append({"pos": pos, "target": target, "rise": CustomMaps.PAD_RISE})
	_marker_step(before)
	message.emit("Jump pad added.", false)


## Removes the marker nearest `feet` (grid space) within MARKER_PICK (a jump pad by its pad or
## its landing) as one undo step; false when there is none.
func remove_marker_near(feet: Vector3) -> bool:
	var best := MARKER_PICK
	var hit := []
	for i in map.spawns.size():
		var d: float = (map.spawns[i] as Vector3).distance_to(feet)
		if d < best:
			best = d
			hit = ["spawns", i]
	for i in map.pickups.size():
		var d: float = (map.pickups[i].pos as Vector3).distance_to(feet)
		if d < best:
			best = d
			hit = ["pickups", i]
	for i in map.jump_pads.size():
		var d := minf((map.jump_pads[i].pos as Vector3).distance_to(feet), (map.jump_pads[i].target as Vector3).distance_to(feet))
		if d < best:
			best = d
			hit = ["jump_pads", i]
	if hit.is_empty():
		return false
	var before := _marker_state()
	(map[hit[0]] as Array).remove_at(hit[1])
	_marker_step(before)
	return true


func undo() -> void:
	if _undo.is_empty():
		message.emit("Nothing to undo.", false)
		return
	var step: Dictionary = _undo.pop_back()
	_redo.append(step)
	_apply_step(step, true)


func redo() -> void:
	if _redo.is_empty():
		message.emit("Nothing to redo.", false)
		return
	var step: Dictionary = _redo.pop_back()
	_undo.append(step)
	_apply_step(step, false)


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func _push(step: Dictionary) -> void:
	_undo.append(step)
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()
	unsaved = true
	changed.emit()


func _apply_step(step: Dictionary, backwards: bool) -> void:
	if step.has("cells"):
		_apply_blocks(step.cells, step.before if backwards else step.after)
	else:
		_set_marker_state(step.markers[0] if backwards else step.markers[1])
	unsaved = true
	changed.emit()


## Writes the cells into the grid through the mesher and rebuilds the touched chunks now.
func _apply_blocks(cells: PackedInt32Array, values: PackedByteArray) -> void:
	var dirty := {}
	_mesher.set_cells(cells, values, dirty)
	var out := _mesher.mesh_chunks(dirty.keys())
	for key: Vector2i in out:
		_mesher.apply_chunk(key, out[key])


func _marker_state() -> Dictionary:
	return {"spawns": map.spawns.duplicate(), "pickups": map.pickups.duplicate(true), "jump_pads": map.jump_pads.duplicate(true)}


func _set_marker_state(s: Dictionary) -> void:
	map.spawns = s.spawns.duplicate()
	map.pickups = s.pickups.duplicate(true)
	map.jump_pads = s.jump_pads.duplicate(true)
	_rebuild_markers()


func _marker_step(before: Dictionary) -> void:
	_push({"markers": [before, _marker_state()]})
	_rebuild_markers()


# ---------------------------------------------------------------- visuals

func _rebuild_markers() -> void:
	for c in _markers.get_children():
		c.free()
	for i in map.spawns.size():
		_markers.add_child(_spawn_marker(origin + map.spawns[i], i))
	for p: Dictionary in map.pickups:
		var node := PickupNode.new()
		node.setup(str(p.kind))
		node.position = origin + p.pos
		_markers.add_child(node)
	for j: Dictionary in map.jump_pads:
		var pad := JumpPad.new()
		pad.setup(origin + j.pos, origin + j.target, float(j.rise))
		_markers.add_child(pad)
	if pad_start != null:
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = JumpPad.RADIUS
		cyl.bottom_radius = JumpPad.RADIUS
		cyl.height = 0.08
		disc.mesh = cyl
		disc.material_override = _flat_material(TOOL_COLORS.pad, 0.8)
		disc.position = origin + (pad_start as Vector3) + Vector3(0, 0.04, 0)
		_markers.add_child(disc)


func _spawn_marker(pos: Vector3, i: int) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	body.mesh = capsule
	body.position.y = 0.9
	var ok := CustomMaps.spot_problem(grid, pos - origin).is_empty()
	body.material_override = _flat_material(TOOL_COLORS.spawn if ok else Color("ff4d4d"), 0.55)
	root.add_child(body)
	var tag := Label3D.new()
	tag.text = "S%d" % (i + 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 48
	tag.outline_size = 10
	tag.position.y = 2.3
	tag.no_depth_test = true
	root.add_child(tag)
	return root


static func _flat_material(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Places the ghost: the block(s) the place press would add (in the block's colour), or the
## marker tool's spot (red when there is no room). With the side panel open the aim holds still,
## so the ghost shows where the next press lands with the block or tool just picked.
func _update_ghost() -> void:
	if aim.is_empty():
		_ghost.visible = false
		return
	var box := _ghost.mesh as BoxMesh
	if tool == "block":
		var target: Vector3i = aim.cell + aim.normal
		var size := Vector3.ONE
		if brush == 3:
			var axes := _face_axes(aim.normal)
			size += Vector3(axes[0] + axes[1]) * 2.0
		box.size = size * 1.02
		_ghost.position = origin + Vector3(target) + Vector3(0.5, 0.5, 0.5)
		_ghost_mat.albedo_color = Color(BlockAtlas.top_color(block()).lightened(0.15), 0.5)
		_ghost.visible = true
		return
	var feet: Variant = aimed_feet()
	if feet == null:
		_ghost.visible = false
		return
	var ok := CustomMaps.spot_problem(grid, feet).is_empty()
	box.size = Vector3(0.9, 0.12, 0.9) if tool == "pad" else Vector3(0.7, 1.8, 0.7)
	_ghost.position = origin + (feet as Vector3) + Vector3(0, box.size.y * 0.5, 0)
	_ghost_mat.albedo_color = Color(TOOL_COLORS[tool] if ok else Color("ff4d4d"), 0.5)
	_ghost.visible = true


func _process(_delta: float) -> void:
	cam.active = not hud.panel_open()
	if cam.active:
		update_aim()
	_update_ghost()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or (event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_TAB) \
			or (event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK):
		hud.toggle_panel()
		get_viewport().set_input_as_handled()
		return
	if hud.panel_open():
		# B on a controller (ui_cancel) also goes back to building.
		if event.is_action_pressed(&"ui_cancel"):
			hud.close_panel()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam.look_mouse((event as InputEventMouseMotion).relative)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.ctrl_pressed or k.meta_pressed:
			match k.keycode:
				KEY_Z:
					if k.shift_pressed:
						redo()
					else:
						undo()
				KEY_Y:
					redo()
				KEY_S:
					save()
			get_viewport().set_input_as_handled()
			return
		if k.keycode >= KEY_1 and k.keycode <= KEY_9:
			select_slot(k.keycode - KEY_1)
			return
	if event is InputEventJoypadButton and event.pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				cycle_tool(-1)
			JOY_BUTTON_RIGHT_SHOULDER:
				cycle_tool(1)
			JOY_BUTTON_DPAD_LEFT:
				undo()
			JOY_BUTTON_DPAD_RIGHT:
				redo()
			JOY_BUTTON_Y:
				select_slot(slot + 1)
			JOY_BUTTON_X:
				set_brush(1 if brush == 3 else 3)
		return
	if event.is_action_pressed(&"fire"):
		use_primary()
	elif event.is_action_pressed(&"aim"):
		use_secondary()
	elif event.is_action_pressed(&"next_weapon"):
		select_slot(slot + 1)
	elif event.is_action_pressed(&"prev_weapon"):
		select_slot(slot - 1)
	elif event.is_action_pressed(&"lean_left"):
		cycle_tool(-1)
	elif event.is_action_pressed(&"lean_right"):
		cycle_tool(1)
	elif event.is_action_pressed(&"reload"):
		set_brush(1 if brush == 3 else 3)


## TEST PLAY: saves, then (when the map is playable) starts an offline Deathmatch on it.
func test_play() -> void:
	if not save().is_empty():
		return
	Net.play_offline({"mode": "ffa", "map": CustomMaps.id_for(map.name), "bots_fill": 6, "difficulty": 1,
		"kill_limit": 20, "time_limit": 480, "mutators": false})


func exit_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(Net.MENU_SCENE)
