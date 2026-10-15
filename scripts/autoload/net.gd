extends Node
## Placeholder; real implementation in progress.
signal status(text: String)
const DEFAULT_PORT := 7777
var players := {}
func play_offline(_config: Dictionary) -> void: pass
func host(_port: int, _config: Dictionary) -> Error: return OK
func join(_ip: String, _port: int) -> Error: return OK
func leave() -> void: pass
