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
