class_name Demolition
extends Node
## Destructible blocks, the "demolition" mutator: World's child "Demolition" on every peer
## (`World.demolition`; idle under any other mutator). World.server_blast hands every rocket, frag
## and Block Bomber blast to `server_blast`, which picks the grid cells whose centres lie within
## RADIUS[kind] of the blast, skips the locked ones (see _lock_cells) and sends the cell indices to
## every peer (`_s_remove`). Each peer turns them into air in its own copy of the grid (MapInfo.grid,
## built `editable`) at once, then remeshes only the chunks they touch on a worker thread
## (VoxelMesher.snapshot().mesh_chunks) and swaps in their meshes and trimesh collision on the main
## thread when it is done (VoxelMesher.apply_chunk), usually the next frame. Removals arriving
## meanwhile wait for the next job. It also throws debris in the blocks' colours and drops pickups
## whose floor went down to the next block beneath. Players and bots on removed blocks simply fall:
## their collision is gone. Late joiners get the whole `removed` list (server_sync). The server
## rebakes the navmesh on a worker thread at most every NAV_REBAKE_EVERY seconds after a change and
## swaps it in when done (the navigation map runs async iterations in this mutator), so bots keep
## pathing on the old one meanwhile. Everything belongs to the match: the next match builds a fresh
## World and map.

## Every peer, after a remesh job is swapped in: cells it covered, chunks remeshed, collision parts
## rebuilt, main-thread milliseconds (clearing the cells + swapping in meshes and collision) and
## worker milliseconds.
signal cells_removed(count: int, chunk_count: int, part_count: int, main_ms: float, worker_ms: float)
## Server, when a rebaked navmesh is in use: worker-thread milliseconds (gathering the triangles
## and baking) and main-thread milliseconds (starting it and swapping it in).
signal nav_rebaked(bake_ms: float, main_ms: float)

const MUTATOR := "demolition"
## Removal radius (m, blocks are 1 m) per explosion kind (World.server_blast's `wid`).
const RADIUS := {"rocket": 2.2, "grenade": 2.6, Streaks.WEAPON: 2.8}
## Columns this close to the grid's side are the map edge / outer walls: never removed.
const EDGE := 2
## Floor cells within this many cells (Chebyshev) of a spawn or a jump pad's take-off / landing
## spot stay, so spawns and pads keep working.
const SPAWN_GUARD := 1
const PAD_GUARD := 2
const NAV_REBAKE_EVERY := 2.0
## Late joiners: cell indices per _s_remove.
const SYNC_CHUNK := 4096
## At most this many different block colours in one debris burst.
const DEBRIS_COLORS := 4

var world: World
## True when the match runs the mutator on a map built editable.
var active := false
## Every peer: grid indices of every removed cell, in removal order.
var removed := PackedInt32Array()
## Server: navmesh rebakes swapped in this match.
var rebakes := 0

var _grid: VoxelGrid
var _mesher: VoxelMesher
var _origin := Vector3.ZERO
## 1 for every cell no explosion may remove.
var _locked := PackedByteArray()
## Chunk keys waiting for the next remesh job, with the cells and main-thread time behind them.
var _dirty := {}
var _dirty_cells := 0
var _dirty_usec := 0
## The running remesh job (WorkerThreadPool task id, -1 = none), what it fills and what it covers.
var _mesh_task := -1
var _mesh_out := {}
var _mesh_cells := 0
var _mesh_usec := 0
var _mesh_worker := [0]
var _nav_dirty := false
var _nav_task := -1
var _nav_out: NavigationMesh
var _nav_main_usec := 0
var _nav_worker := [0]
var _nav_started := -100.0


func _init() -> void:
	name = "Demolition"


## Whether this match's config runs the mutator (World builds the map editable for it).
static func enabled() -> bool:
	return str(Net.config.get("mutator", "")) == MUTATOR


func _ready() -> void:
	active = enabled() and world.map_info.grid != null
	set_process(active)
	if not active:
		return
	_grid = world.map_info.grid
	_mesher = world.map_info.mesher
	_origin = world.map_info.bounds.position
	_lock_cells()
	if multiplayer.is_server() and world.map_info.nav_region != null:
		# A rebaked navmesh is then merged into the map off the main thread.
		NavigationServer3D.region_set_use_async_iterations(world.map_info.nav_region.get_rid(), true)
		NavigationServer3D.map_set_use_async_iterations(world.map_info.nav_map, true)


func _exit_tree() -> void:
	if _mesh_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_mesh_task)
		_mesh_task = -1
	if _nav_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_nav_task)
		_nav_task = -1


## Whether grid cell `i` (VoxelGrid.index) can never be removed.
func is_locked(i: int) -> bool:
	return _locked[i] != 0


## Order-independent fingerprint of the removed cells (for comparing peers).
func removed_hash() -> int:
	var sorted := removed.duplicate()
	sorted.sort()
	return hash(sorted)


## True while removed cells still wait for their chunks to be swapped in.
func busy() -> bool:
	return _mesh_task >= 0 or not _dirty.is_empty()


# ================================================================ locked cells

## Locks what keeps the map playable: the outer EDGE columns, water, and in every column the
## lowest block whose top is above the kill height plus everything under it (the bedrock / ground
## layer, and the last floor over a kill plane: a hole there would drop players to their death);
## everything above it always has that floor beneath. Also the floor around every spawn and both
## ends of every jump pad.
func _lock_cells() -> void:
	var s := _grid.size
	_locked.resize(_grid.blocks.size())
	var kill := world.map_info.kill_y - _origin.y
	for z in s.z:
		for x in s.x:
			var edge := x < EDGE or z < EDGE or x >= s.x - EDGE or z >= s.z - EDGE
			var floor_found := false
			for y in s.y:
				var i := _grid.index(x, y, z)
				var b := _grid.blocks[i]
				if edge or not floor_found or b == BlockAtlas.WATER:
					_locked[i] = 1
				if b != BlockAtlas.AIR and float(y + 1) > kill:
					floor_found = true
	for sp: Vector3 in world.map_info.spawns:
		_lock_floor(sp, SPAWN_GUARD)
	for m: Dictionary in world.map_info.marks.get("jump_pads", []):
		_lock_floor(m.pos, PAD_GUARD)
		_lock_floor(m.target, PAD_GUARD)


## Locks the two cells under the feet position `feet` (world space) and those around them.
func _lock_floor(feet: Vector3, guard: int) -> void:
	var c := feet - _origin
	var cx := floori(c.x)
	var cz := floori(c.z)
	var fy := floori(c.y - 0.5)
	for y in range(fy - 1, fy + 1):
		for z in range(cz - guard, cz + guard + 1):
			for x in range(cx - guard, cx + guard + 1):
				if _grid.in_bounds(x, y, z):
					_locked[_grid.index(x, y, z)] = 1


# ================================================================ server

## Server (World.server_blast): removes the unlocked blocks within the radius of a `kind`
## explosion at `pos` (world space) on every peer. Returns how many it removed.
func server_blast(pos: Vector3, kind: String) -> int:
	if not active or not RADIUS.has(kind) or not pos.is_finite():
		return 0
	var r: float = RADIUS[kind]
	var c := pos - _origin
	var s := _grid.size
	var cells := PackedInt32Array()
	for y in range(maxi(floori(c.y - r), 0), mini(floori(c.y + r), s.y - 1) + 1):
		for z in range(maxi(floori(c.z - r), 0), mini(floori(c.z + r), s.z - 1) + 1):
			for x in range(maxi(floori(c.x - r), 0), mini(floori(c.x + r), s.x - 1) + 1):
				if Vector3(x + 0.5, y + 0.5, z + 0.5).distance_squared_to(c) > r * r:
					continue
				var i := _grid.index(x, y, z)
				if _grid.blocks[i] != BlockAtlas.AIR and _locked[i] == 0:
					cells.append(i)
	if cells.is_empty():
		return 0
	for pid: int in world.ready_peer_ids():
		_s_remove.rpc_id(pid, cells, true)
	_s_remove(cells, true)
	return cells.size()


## A peer that just loaded the match gets every removed cell (no debris).
func server_sync(pid: int) -> void:
	if not active:
		return
	for from in range(0, removed.size(), SYNC_CHUNK):
		_s_remove.rpc_id(pid, removed.slice(from, from + SYNC_CHUNK), false)


func _process(_delta: float) -> void:
	if _mesh_task >= 0 and WorkerThreadPool.is_task_completed(_mesh_task):
		_finish_mesh_job()
	if _mesh_task < 0 and not _dirty.is_empty():
		_start_mesh_job()
	if _nav_task >= 0 and WorkerThreadPool.is_task_completed(_nav_task):
		_finish_rebake()
	if _nav_dirty and _nav_task < 0 and not busy() and World.now() - _nav_started >= NAV_REBAKE_EVERY:
		_start_rebake()


# ================================================================ remeshing

func _start_mesh_job() -> void:
	var t0 := Time.get_ticks_usec()
	var keys := _dirty.keys().filter(func(k: Vector2i) -> bool: return _mesher.chunks.has(k))
	_mesh_cells = _dirty_cells
	_mesh_usec = _dirty_usec
	_dirty = {}
	_dirty_cells = 0
	_dirty_usec = 0
	var snap := _mesher.snapshot()
	var out := {}
	var worker := [0]
	_mesh_out = out
	_mesh_worker = worker
	_mesh_task = WorkerThreadPool.add_task(func() -> void:
		var w0 := Time.get_ticks_usec()
		out.merge(snap.mesh_chunks(keys))
		worker[0] = Time.get_ticks_usec() - w0, false, "Demolition remesh")
	_mesh_usec += Time.get_ticks_usec() - t0


func _finish_mesh_job() -> void:
	WorkerThreadPool.wait_for_task_completion(_mesh_task)
	_mesh_task = -1
	var t0 := Time.get_ticks_usec()
	var parts := 0
	for key: Vector2i in _mesh_out:
		parts += _mesher.apply_chunk(key, _mesh_out[key])
	_mesh_usec += Time.get_ticks_usec() - t0
	if multiplayer.is_server():
		_nav_dirty = true
	cells_removed.emit(_mesh_cells, _mesh_out.size(), parts, _mesh_usec / 1000.0, int(_mesh_worker[0]) / 1000.0)
	_mesh_out = {}


# ================================================================ navigation (server)

## Gathers the chunks' current collision triangles and bakes a new navmesh from them on a worker
## thread; the old one stays in use until _finish_rebake swaps it in.
func _start_rebake() -> void:
	var region := world.map_info.nav_region
	_nav_dirty = false
	if region == null:
		return
	var t0 := Time.get_ticks_usec()
	_nav_started = World.now()
	var tris: Array[PackedVector3Array] = []
	var xforms: Array[Transform3D] = []
	for key: Vector2i in _mesher.chunks:
		tris.append(_mesher.faces[key])
		xforms.append((_mesher.chunks[key] as MeshInstance3D).global_transform)
	var nm := MapBuilder.navigation_mesh(world.map_info.bounds)
	var worker := [0]
	_nav_out = nm
	_nav_worker = worker
	_nav_task = WorkerThreadPool.add_task(func() -> void:
		var w0 := Time.get_ticks_usec()
		var source := NavigationMeshSourceGeometryData3D.new()
		for i in tris.size():
			source.add_faces(tris[i], xforms[i])
		NavigationServer3D.bake_from_source_geometry_data(nm, source)
		worker[0] = Time.get_ticks_usec() - w0, false, "Demolition navmesh")
	_nav_main_usec = Time.get_ticks_usec() - t0


func _finish_rebake() -> void:
	WorkerThreadPool.wait_for_task_completion(_nav_task)
	_nav_task = -1
	var t0 := Time.get_ticks_usec()
	world.map_info.nav_region.navigation_mesh = _nav_out
	_nav_out = null
	rebakes += 1
	nav_rebaked.emit(int(_nav_worker[0]) / 1000.0, (_nav_main_usec + Time.get_ticks_usec() - t0) / 1000.0)


# ================================================================ every peer

## Blocks went: turn `cells` (grid indices) into air now, queue their chunks for remeshing, drop
## pickups that lost their floor, and (`debris`, a blast rather than a late-join sync) burst debris.
@rpc("authority", "call_remote", "reliable")
func _s_remove(cells: PackedInt32Array, debris: bool) -> void:
	if not active:
		return
	var t0 := Time.get_ticks_usec()
	var fresh := PackedInt32Array()
	var colors := {}
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var sx := _grid.size.x
	var sz := _grid.size.z
	for i in cells:
		if i < 0 or i >= _grid.blocks.size():
			continue
		var b := _grid.blocks[i]
		if b == BlockAtlas.AIR:
			continue
		fresh.append(i)
		if debris:
			if colors.size() < DEBRIS_COLORS:
				colors[b] = true
			var cell := Vector3(i % sx, i / (sx * sz), (i / sx) % sz)
			lo = lo.min(cell)
			hi = hi.max(cell)
	if fresh.is_empty():
		return
	_mesher.clear_cells(fresh, _dirty)
	removed.append_array(fresh)
	_dirty_cells += fresh.size()
	_dirty_usec += Time.get_ticks_usec() - t0
	_drop_pickups()
	if debris:
		var tints := PackedColorArray()
		for b: int in colors:
			tints.append(BlockAtlas.top_color(b))
		world.fx.block_debris(_origin + (lo + hi) * 0.5 + Vector3.ONE * 0.5, (hi - lo) * 0.5 + Vector3.ONE * 0.4, tints)


## Moves every pickup whose floor block is gone down onto the next block beneath it.
func _drop_pickups() -> void:
	for node in world.pickup_nodes:
		var c := node.position - _origin
		var x := floori(c.x)
		var z := floori(c.z)
		var y := floori(c.y - 0.5)
		if not _grid.in_bounds(x, 0, z) or not _grid.is_air(x, y, z):
			continue
		while y >= 0 and _grid.is_air(x, y, z):
			y -= 1
		if y >= 0:
			node.position.y = _origin.y + y + 1
