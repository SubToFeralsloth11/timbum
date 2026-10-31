class_name MapInfo
extends RefCounted
## Gameplay facts about a built map, returned by MapBuilder.build().

var id := ""
var display_name := ""
## Feet positions, world space.
var spawns: Array[Vector3] = []
## `{kind: "health"|"ammo"|"grenade", pos: Vector3}`, world space.
var pickups: Array[Dictionary] = []
## Anything below this height dies.
var kill_y := -20.0
var bounds := AABB()
## Navigation map of the baked NavigationRegion3D.
var nav_map := RID()
## Named spots a map's own controller reads (the Firing Range's line, dummy posts, signs, console
## and grapple ledge), world space: a Vector3, an AABB, or an Array of Dictionaries with a `pos`.
var marks := {}
## The map's jump pads (MapBuilder adds them from the generator's `jump_pads` mark; deathmatch
## maps only).
var jump_pads: Array[JumpPad] = []
## Editable builds only (MapBuilder.build `editable`, the Demolition mutator), else null: the
## block grid (cell (0,0,0) at `bounds.position`), the mesher that rebuilds its chunks, and the
## NavigationRegion3D whose navmesh is rebaked.
var grid: VoxelGrid
var mesher: VoxelMesher
var nav_region: NavigationRegion3D
