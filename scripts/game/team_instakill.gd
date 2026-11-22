class_name TeamInstakill
extends TeamDeathmatch
## Team Instakill (`Net.config.mode == "instakill"`): Team Deathmatch where any hit from any weapon
## kills outright. First team to `Net.config.kill_limit` (default DEFAULT_LIMIT) wins.

const DEFAULT_LIMIT := 30


func _init() -> void:
	name = "TeamInstakill"


func hit_damage(_shooter: Player, _target: Player, _wid: String, dmg: float) -> float:
	return 10000.0 if dmg > 0.0 else dmg
