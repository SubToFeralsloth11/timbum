class_name CustomMaps
extends RefCounted
## Player-made maps from the Map Editor (MapEditor): the file format, saving and loading, the
## checks a map must pass to be played, and the map a match plays.
##
## A map in memory is a Dictionary: `name`, `time_of_day` (Data.TIMES_OF_DAY), `grid` (VoxelGrid,
## full cubes only), `spawns` (Array of Vector3 feet positions), `pickups` (Array of
## `{kind, pos}`), `jump_pads` (Array of `{pos, target, rise}`), all in grid space (cell (0,0,0)
## at the grid's corner, y = 0 its floor), like a map generator's output.
## On disk (`user://maps/<name>.json`) it is JSON: `version`, `name`, `time_of_day`, `size`
## [x, y, z], `blocks` (the grid's block ids, deflated and base64-encoded), and the markers as
## number arrays. Match ids of custom maps are PREFIX + name ("custom:Arena").
## A match on a custom map plays `active`: the host reads the file (activate_file), clients get
## its deflated bytes over the network (Net, chunked) and keep them in CACHE_DIR by hash
## (activate_payload / activate_cached), so every peer builds the same map.

const VERSION := 1
const PREFIX := "custom:"
const DIR := "user://maps/"
const CACHE_DIR := "user://maps/cache/"
const MIN_SIZE := Vector3i(16, 12, 16)
const MAX_SIZE := Vector3i(96, 48, 96)
## The editor's NEW sizes (x, height, z).
const PRESETS: Array[Vector3i] = [Vector3i(32, 24, 32), Vector3i(48, 24, 48), Vector3i(64, 24, 64)]
const MIN_SPAWNS := 4
const MAX_SPAWNS := 32
const MAX_PICKUPS := 48
const MAX_PADS := 16
const PICKUP_KINDS: Array[String] = ["health", "ammo", "grenade"]
const NAME_MAX := 24
## Metres below the grid floor at which players die.
const KILL_DEPTH := 8.0
## A jump pad's arc apex above the higher of pad and landing (JumpPad.setup).
const PAD_RISE := 3.0
## Largest deflated map (network payload) and inflated JSON text accepted.
const MAX_PAYLOAD := 1 << 20
const MAX_TEXT := 8 << 20
## Sky, sun and fog of every custom map before its time of day (World._apply_time_of_day).
const ATMOSPHERE := {
	"sky_top": Color("3f7fd6"), "sky_horizon": Color("a9cbe8"), "ground_bottom": Color("4d5a3a"),
	"sun_pitch": -50.0, "sun_yaw": -35.0, "sun_color": Color("fff1d6"), "sun_energy": 1.35,
	"fog_color": Color("b9d2e6"), "fog_density": 0.0025, "ambient": 0.75, "exposure": 1.0, "fog_sky": 0.15,
}

## The custom map the current match plays: {id, hash, payload (deflated JSON), map}; empty
## when none.
static var active := {}


static func is_custom(map_id: String) -> bool:
	if not map_id.begins_with(PREFIX):
		return false
	var n := name_of(map_id)
	return not n.is_empty() and sanitize_name(n) == n


static func name_of(map_id: String) -> String:
	return map_id.substr(PREFIX.length())


static func id_for(map_name: String) -> String:
	return PREFIX + map_name


## Letters, digits, spaces, `-` and `_`, trimmed, at most NAME_MAX characters ("" if nothing is left).
static func sanitize_name(raw: String) -> String:
	var out := ""
	for ch in raw:
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in [" ", "-", "_"]:
			out += ch
	return out.strip_edges().left(NAME_MAX).strip_edges()


static func path_for(map_name: String) -> String:
	return DIR + map_name + ".json"


## A new map: a flat GRASS floor one block thick over the whole grid, no markers.
static func new_map(size: Vector3i, map_name: String) -> Dictionary:
	var g := VoxelGrid.new(size)
	g.fill(Vector3i(0, 0, 0), Vector3i(size.x - 1, 0, size.z - 1), BlockAtlas.GRASS)
	return {"name": map_name, "time_of_day": "day", "grid": g, "spawns": [], "pickups": [], "jump_pads": []}


static func grid_hash(g: VoxelGrid) -> String:
	return md5(g.blocks)


static func md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


# ---------------------------------------------------------------- format

static func to_json(map: Dictionary) -> String:
	var g: VoxelGrid = map.grid
	var spawns := []
	for s: Vector3 in map.spawns:
		spawns.append(_arr(s))
	var pickups := []
	for p: Dictionary in map.pickups:
		pickups.append({"kind": p.kind, "pos": _arr(p.pos)})
	var pads := []
	for j: Dictionary in map.jump_pads:
		pads.append({"pos": _arr(j.pos), "target": _arr(j.target), "rise": float(j.rise)})
	return JSON.stringify({
		"version": VERSION, "name": map.name, "time_of_day": map.time_of_day,
		"size": [g.size.x, g.size.y, g.size.z],
		"blocks": Marshalls.raw_to_base64(g.blocks.compress(FileAccess.COMPRESSION_DEFLATE)),
		"spawns": spawns, "pickups": pickups, "jump_pads": pads,
	})


## The map in `text`, or {} when it is not a valid map file. Untrusted input (files, the
## network): sizes, ids, kinds and positions are checked, unknown block ids become STONE and
## marker lists are cut to their maximum.
static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	if not _is_num(d.get("version")) or int(d.version) < 1 or int(d.version) > VERSION:
		return {}
	var map_name := sanitize_name(str(d.get("name", "")))
	var sz: Variant = d.get("size")
	if map_name.is_empty() or typeof(sz) != TYPE_ARRAY or (sz as Array).size() != 3:
		return {}
	for v: Variant in sz:
		if not _is_num(v):
			return {}
	var size := Vector3i(int(sz[0]), int(sz[1]), int(sz[2]))
	if size.x < MIN_SIZE.x or size.y < MIN_SIZE.y or size.z < MIN_SIZE.z or size.x > MAX_SIZE.x or size.y > MAX_SIZE.y or size.z > MAX_SIZE.z:
		return {}
	var g := VoxelGrid.new(size)
	var packed := Marshalls.base64_to_raw(str(d.get("blocks", "")))
	if packed.is_empty():
		return {}
	var blocks := packed.decompress(g.blocks.size(), FileAccess.COMPRESSION_DEFLATE)
	if blocks.size() != g.blocks.size():
		return {}
	for i in blocks.size():
		if blocks[i] >= BlockAtlas.BLOCK_COUNT:
			blocks[i] = BlockAtlas.STONE
	g.blocks = blocks
	var tod := str(d.get("time_of_day", "day"))
	var map := {"name": map_name, "time_of_day": tod if tod in Data.TIMES_OF_DAY else "day", "grid": g,
		"spawns": [], "pickups": [], "jump_pads": []}
	for s: Variant in _list(d.get("spawns"), MAX_SPAWNS):
		var p: Variant = _vec(s, size)
		if p != null:
			map.spawns.append(p)
	for e: Variant in _list(d.get("pickups"), MAX_PICKUPS):
		if typeof(e) != TYPE_DICTIONARY or not str(e.get("kind", "")) in PICKUP_KINDS:
			continue
		var p: Variant = _vec(e.get("pos"), size)
		if p != null:
			map.pickups.append({"kind": str(e.kind), "pos": p})
	for e: Variant in _list(d.get("jump_pads"), MAX_PADS):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var a: Variant = _vec(e.get("pos"), size)
		var b: Variant = _vec(e.get("target"), size)
		if a != null and b != null:
			var rise := clampf(float(e.get("rise", PAD_RISE)) if _is_num(e.get("rise")) else PAD_RISE, 1.0, 12.0)
			map.jump_pads.append({"pos": a, "target": b, "rise": rise})
	return map


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _list(v: Variant, cap: int) -> Array:
	return (v as Array).slice(0, cap) if typeof(v) == TYPE_ARRAY else []


## A position inside the grid box from a 3-number array, else null.
static func _vec(v: Variant, size: Vector3i) -> Variant:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 3:
		return null
	for n: Variant in v:
		if not _is_num(n):
			return null
	var p := Vector3(float(v[0]), float(v[1]), float(v[2]))
	if p.x < 0.0 or p.y < 0.0 or p.z < 0.0 or p.x > size.x or p.y > size.y or p.z > size.z:
		return null
	return p


# ---------------------------------------------------------------- validation

## Why `map` can't be played (empty when it can): at least MIN_SPAWNS spawns, the grid size within
## MIN_SIZE..MAX_SIZE, every spawn, pickup, jump pad and landing on a solid floor with two
## free cells (feet and head) above, and (once those spots are fine) every spawn, pickup and pad
## reachable on foot from spawn 1 (`unreachable`, player rules).
static func validate(map: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var g: VoxelGrid = map.grid
	var s := g.size
	if s.x < MIN_SIZE.x or s.y < MIN_SIZE.y or s.z < MIN_SIZE.z or s.x > MAX_SIZE.x or s.y > MAX_SIZE.y or s.z > MAX_SIZE.z:
		out.append("Size %dx%dx%d is outside %dx%dx%d to %dx%dx%d." % [s.x, s.y, s.z, MIN_SIZE.x, MIN_SIZE.y, MIN_SIZE.z, MAX_SIZE.x, MAX_SIZE.y, MAX_SIZE.z])
	var spots_ok := out.is_empty()
	if map.spawns.size() < MIN_SPAWNS:
		out.append("Place at least %d spawns (%d placed)." % [MIN_SPAWNS, map.spawns.size()])
	for i in map.spawns.size():
		var why := spot_problem(g, map.spawns[i])
		if not why.is_empty():
			out.append("Spawn %d %s." % [i + 1, why])
			spots_ok = false
	for i in map.pickups.size():
		var why := spot_problem(g, map.pickups[i].pos)
		if not why.is_empty():
			out.append("%s pickup %d %s." % [str(map.pickups[i].kind).capitalize(), i + 1, why])
			spots_ok = false
	for i in map.jump_pads.size():
		for key: String in ["pos", "target"]:
			var why := spot_problem(g, map.jump_pads[i][key])
			if not why.is_empty():
				out.append("Jump pad %d %s %s." % [i + 1, "pad" if key == "pos" else "landing", why])
				spots_ok = false
	if spots_ok and not map.spawns.is_empty():
		out.append_array(unreachable(map, false))
	return out


## The spawns, pickups and jump pads that can't be reached from spawn 1, as messages. Expects
## validate()'s spot checks to pass. Player rules make a map unplayable (validate); bot rules are
## advice the Map Editor shows on a playable map. A flood fill over the cells feet can stand in
## (a full block below, two air cells for feet and head), with jump pads as one-way links from
## the pad cell to the landing cell. Player rules (`bots` false): step to a neighbour on the
## same level, jump up one block (with head room over the take-off cell), or drop down any
## height onto a floor.
## Bot rules (`bots` true) are the navmesh's (MapBuilder.navigation_mesh): it climbs at most
## 0.25 m and links no drops, so bots only walk on the level; its 0.5 m agent radius erodes a
## one-block-wide strip (walls, ledges or low ceilings on both sides) away. A bot counts as
## reaching a spot when it gets to the spot's cell or a level neighbour of it.
static func unreachable(map: Dictionary, bots: bool) -> PackedStringArray:
	var f := _Flood.new(map, bots)
	var out := PackedStringArray()
	var why := " (bots only walk on the level, through gaps two blocks wide, and take jump pads)." if bots \
		else " (walking, jumping up one block, dropping down or taking a jump pad)."
	var lead := "Bots can't get from spawn 1 to %s" if bots else "%s can't be reached from spawn 1"
	for i in range(1, map.spawns.size()):
		if not f.reached(map.spawns[i]):
			out.append(lead % ("spawn %d" % (i + 1) if bots else "Spawn %d" % (i + 1)) + why)
	for i in map.pickups.size():
		if not f.reached(map.pickups[i].pos):
			out.append(lead % ("%s pickup %d" % [str(map.pickups[i].kind), i + 1] if bots \
				else "%s pickup %d" % [str(map.pickups[i].kind).capitalize(), i + 1]) + why)
	for i in map.jump_pads.size():
		if not f.reached(map.jump_pads[i].pos):
			out.append(lead % ("jump pad %d" % (i + 1) if bots else "Jump pad %d" % (i + 1)) + why)
	return out


## The flood fill behind unreachable(): `seen` marks the cells reached from spawn 1 (by
## VoxelGrid.index). Standable cells are worked out once each (`_memo`), reading the grid's
## arrays directly, so a 96 x 96 map stays cheap enough to recheck after every edit.
class _Flood:
	const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var seen := PackedByteArray()
	var bots := false
	var _blocks: PackedByteArray
	var _shapes: PackedByteArray
	## Per cell: 0 not worked out yet, 1 standable, 2 not.
	var _memo := PackedByteArray()
	var _sx := 0
	var _sy := 0
	var _sz := 0
	var _layer := 0

	func _init(map: Dictionary, p_bots: bool) -> void:
		var g: VoxelGrid = map.grid
		bots = p_bots
		_blocks = g.blocks
		_shapes = g.shapes
		_sx = g.size.x
		_sy = g.size.y
		_sz = g.size.z
		_layer = _sx * _sz
		seen.resize(_blocks.size())
		_memo.resize(_blocks.size())
		_fill(map)

	## Index of cell (x, y, z), or -1 outside the grid.
	func idx(x: int, y: int, z: int) -> int:
		if x < 0 or y < 0 or z < 0 or x >= _sx or y >= _sy or z >= _sz:
			return -1
		return (y * _sz + z) * _sx + x

	func cell(feet: Vector3) -> int:
		return idx(floori(feet.x), floori(feet.y + 0.01), floori(feet.z))

	## Air (outside the grid counts as air, like VoxelGrid.is_air).
	func air(x: int, y: int, z: int) -> bool:
		var i := idx(x, y, z)
		return i < 0 or _blocks[i] == BlockAtlas.AIR

	## Feet fit in cell (x, y, z): a full block under it, air for feet and head.
	func stand(x: int, y: int, z: int) -> bool:
		var i := idx(x, y, z)
		if i < 0 or y == 0:
			return false
		var m := _memo[i]
		if m == 0:
			var below := i - _layer
			var ok := _blocks[i] == BlockAtlas.AIR and _blocks[below] != BlockAtlas.AIR \
				and _shapes[below] == VoxelGrid.CUBE and (y + 1 >= _sy or _blocks[i + _layer] == BlockAtlas.AIR)
			m = 1 if ok else 2
			_memo[i] = m
		return m == 1

	## A cell the bots' navmesh keeps: standable and not a one-wide strip along x or z.
	func bot_cell(x: int, y: int, z: int) -> bool:
		if not stand(x, y, z):
			return false
		if not stand(x - 1, y, z) and not stand(x + 1, y, z):
			return false
		return stand(x, y, z - 1) or stand(x, y, z + 1)

	## Whether the spot with feet at `feet` was reached (bots: or a level neighbour of its cell).
	func reached(feet: Vector3) -> bool:
		var x := floori(feet.x)
		var y := floori(feet.y + 0.01)
		var z := floori(feet.z)
		var i := idx(x, y, z)
		if i >= 0 and seen[i] != 0:
			return true
		if bots:
			for d in DIRS:
				var j := idx(x + d.x, y, z + d.y)
				if j >= 0 and seen[j] != 0:
					return true
		return false

	func _fill(map: Dictionary) -> void:
		# Pad cell index -> landing cells. A bot's route reaches a pad from a level neighbour too.
		var pads := {}
		for j: Dictionary in map.jump_pads:
			var to := cell(j.target)
			var p: Vector3 = j.pos
			var from: Array[int] = [cell(p)]
			if bots:
				for d in DIRS:
					from.append(cell(p + Vector3(d.x, 0, d.y)))
			for k in from:
				if k >= 0 and to >= 0:
					if not pads.has(k):
						pads[k] = []
					pads[k].append(to)
		var queue := PackedInt32Array()
		var first := cell(map.spawns[0])
		if first < 0:
			return
		seen[first] = 1
		queue.append(first)
		var head := 0
		while head < queue.size():
			var i := queue[head]
			head += 1
			var y := i / _layer
			var z := (i % _layer) / _sx
			var x := i % _sx
			for d in DIRS:
				var nx := x + d.x
				var nz := z + d.y
				if nx < 0 or nz < 0 or nx >= _sx or nz >= _sz:
					continue
				var to := -1
				if bots:
					if bot_cell(nx, y, nz):
						to = idx(nx, y, nz)
				elif stand(nx, y, nz):
					to = idx(nx, y, nz)
				elif stand(nx, y + 1, nz) and air(x, y + 2, z):
					to = idx(nx, y + 1, nz)
				elif air(nx, y, nz) and air(nx, y + 1, nz):
					var fy := y
					while fy > 0 and air(nx, fy - 1, nz):
						fy -= 1
					if stand(nx, fy, nz):
						to = idx(nx, fy, nz)
				if to >= 0 and seen[to] == 0:
					seen[to] = 1
					queue.append(to)
			if pads.has(i):
				for to: int in pads[i]:
					if seen[to] == 0:
						seen[to] = 1
						queue.append(to)


## "" when feet at `feet` (grid space) stand on a full block with two air cells above, else why not.
static func spot_problem(g: VoxelGrid, feet: Vector3) -> String:
	var x := floori(feet.x)
	var y := floori(feet.y + 0.01)
	var z := floori(feet.z)
	if not g.is_air(x, y, z) or not g.is_air(x, y + 1, z):
		return "is inside blocks"
	if not g.is_cube(x, y - 1, z):
		return "has no floor under it"
	return ""


# ---------------------------------------------------------------- files

## Writes user://maps/<map.name>.json. `old_name` is the file the map was opened from or last
## saved to ("" for a new map). ERR_ALREADY_EXISTS (nothing written) when that would overwrite a
## different saved map: see name_taken().
static func save(map: Dictionary, old_name := "") -> Error:
	if name_taken(map.name, old_name):
		return ERR_ALREADY_EXISTS
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path_for(map.name), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var written := f.store_string(to_json(map))
	f.close()
	if not written:
		return ERR_FILE_CANT_WRITE
	MapBuilder.forget_preview(id_for(map.name))
	return OK


## True when saving the map from file `old_name` ("" = never saved) as `new_name` would overwrite
## another saved map. A case-only rename of the same map is not a clash: on a case-insensitive
## disk the file under the new spelling is the map's own file (the listing still shows the old one).
static func name_taken(new_name: String, old_name: String) -> bool:
	if new_name == old_name or not FileAccess.file_exists(path_for(new_name)):
		return false
	if old_name.is_empty() or new_name.to_lower() != old_name.to_lower():
		return true
	return DirAccess.get_files_at(DIR).has(new_name + ".json")


## After the map saved as `old_name` was saved again as `new_name`: removes the old file. When
## only the letter case changed on a case-insensitive disk the save rewrote the old file, so it
## is renamed instead (its name then matches the map's).
static func renamed(old_name: String, new_name: String) -> void:
	if not FileAccess.file_exists(path_for(old_name)):
		return
	if DirAccess.get_files_at(DIR).has(new_name + ".json"):
		DirAccess.remove_absolute(path_for(old_name))
	else:
		DirAccess.rename_absolute(path_for(old_name), path_for(new_name))
	MapBuilder.forget_preview(id_for(old_name))


## The saved map `map_name`, or {} when it is missing or broken.
static func load_map(map_name: String) -> Dictionary:
	var text := _read_text(path_for(map_name))
	return {} if text.is_empty() else from_json(text)


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_TEXT:
		return ""
	return f.get_as_text()


## Names of the saved maps, sorted (playable or not).
static func list() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "json":
			var n := f.get_basename()
			if sanitize_name(n) == n and not n.is_empty():
				out.append(n)
	out.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return out


## Names of the saved maps that pass validate() (match setup lists these).
static func playable() -> Array[String]:
	var out: Array[String] = []
	for n in list():
		var m := load_map(n)
		if not m.is_empty() and validate(m).is_empty():
			out.append(n)
	return out


## The map `map_id` plays: the active one, else the saved file (offline previews); {} if neither.
static func map_for(map_id: String) -> Dictionary:
	if not active.is_empty() and active.id == map_id:
		return active.map
	return load_map(name_of(map_id)) if is_custom(map_id) else {}


# ---------------------------------------------------------------- the match's map

## Host / offline: makes the saved map `map_id` the active one. False when it is missing or
## doesn't pass validate().
static func activate_file(map_id: String) -> bool:
	var text := _read_text(path_for(name_of(map_id)))
	var map := from_json(text)
	if map.is_empty() or not validate(map).is_empty():
		return false
	var payload := text.to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	if payload.size() > MAX_PAYLOAD:
		return false
	active = {"id": map_id, "hash": md5(payload), "payload": payload, "map": map}
	return true


## Client: makes the host's map active from its deflated bytes, if they match `hash` and hold a
## playable map, and keeps them in CACHE_DIR. Returns whether it worked.
static func activate_payload(map_id: String, payload: PackedByteArray, hash: String) -> bool:
	if payload.size() > MAX_PAYLOAD or md5(payload) != hash:
		return false
	var text := payload.decompress_dynamic(MAX_TEXT, FileAccess.COMPRESSION_DEFLATE).get_string_from_utf8()
	var map := from_json(text)
	if map.is_empty() or not validate(map).is_empty():
		return false
	active = {"id": map_id, "hash": hash, "payload": payload, "map": map}
	var path := _cache_path(hash)
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(payload)
	return true


## Client: activates a map received before (CACHE_DIR), if there is one with `hash`.
static func activate_cached(map_id: String, hash: String) -> bool:
	if not active.is_empty() and active.hash == hash:
		active.id = map_id
		return true
	var path := _cache_path(hash)
	if not hash.is_valid_hex_number() or not FileAccess.file_exists(path):
		return false
	return activate_payload(map_id, FileAccess.get_file_as_bytes(path), hash)


static func _cache_path(hash: String) -> String:
	return CACHE_DIR + hash + ".map"


## MapBuilder.generate for a custom map: fills `info` like a generator does (grid space) and
## returns a fresh copy of the grid (an editable build changes it), or null when `map_id` has no map.
static func generate(map_id: String, info: MapInfo) -> VoxelGrid:
	var map := map_for(map_id)
	if map.is_empty():
		return null
	var src: VoxelGrid = map.grid
	var g := VoxelGrid.new(src.size)
	g.blocks = src.blocks.duplicate()
	info.id = map_id
	info.display_name = str(map.name)
	info.kill_y = -KILL_DEPTH
	for s: Vector3 in map.spawns:
		info.spawns.append(s)
	for p: Dictionary in map.pickups:
		info.pickups.append({"kind": p.kind, "pos": p.pos})
	var pads := []
	for j: Dictionary in map.jump_pads:
		pads.append({"pos": j.pos, "target": j.target, "rise": j.rise})
	if not pads.is_empty():
		info.marks["jump_pads"] = pads
	return g
