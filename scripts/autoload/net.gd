extends Node
## Session layer: hosting, joining, the peer registry, and moving everyone between the menu and matches.
## Match gameplay RPCs live on the World node (scripts/game/world.gd).

signal status(text: String)
signal players_changed

const DEFAULT_PORT := 7777
const PROTOCOL_VERSION := 2
const CONNECT_TIMEOUT := 8.0
const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

const DEFAULT_CONFIG := {
	"map": "rotation",
	"bots_fill": 8,
	"difficulty": 1,
	"kill_limit": 20,
	"time_limit": 480,
	## Roll a random mutator each match.
	"mutators": true,
	## Rolled per match by the server and sent to clients with the config.
	"mutator": "none",
	"time_of_day": "day",
}

## peer id -> peer_info dictionary (see Profile.peer_info()). Kept in sync on every peer.
var players := {}
## Active match configuration (server's copy is authoritative; clients receive it).
var config := DEFAULT_CONFIG.duplicate()
## Map the world scene should build when it loads.
var current_map := "village"
var offline := false

## Maps left in the current shuffled rotation.
var _rotation: Array[String] = []
## Server: the next match ({map, mutator, time_of_day}), decided when a match ends so the results
## screen can announce it; empty while a match is in progress.
var _next_match := {}
var _connect_timer: SceneTreeTimer
## Set when we leave on purpose so the disconnect handler stays quiet.
var _leaving := false
## Shown by the menu after returning from a dropped session.
var last_error := ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------- entry points

func play_offline(cfg: Dictionary) -> void:
	_close_peer()
	offline = true
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_server(cfg)


func host(port: int, cfg: Dictionary) -> Error:
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Data.MAX_PLAYERS - 1)
	if err != OK:
		status.emit("Could not host on port %d (%s). Is it already in use?" % [port, error_string(err)])
		return err
	offline = false
	multiplayer.multiplayer_peer = peer
	_start_server(cfg)
	return OK


func join(ip: String, port: int) -> Error:
	_close_peer()
	ip = ip.strip_edges()
	if ip.is_empty():
		status.emit("Enter the host's IP address.")
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		status.emit("Could not connect to %s:%d (%s)." % [ip, port, error_string(err)])
		return err
	offline = false
	multiplayer.multiplayer_peer = peer
	status.emit("Connecting to %s:%d..." % [ip, port])
	_connect_timer = get_tree().create_timer(CONNECT_TIMEOUT)
	_connect_timer.timeout.connect(_on_connect_timeout.bind(peer))
	return OK


## Ends the session (any role) and returns to the main menu.
func leave() -> void:
	_leaving = true
	_close_peer()
	_leaving = false
	players.clear()
	players_changed.emit()
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _close_peer() -> void:
	_connect_timer = null
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	offline = false


func _start_server(cfg: Dictionary) -> void:
	config = sanitize_config(cfg)
	players = {1: Profile.peer_info()}
	players_changed.emit()
	_rotation.clear()
	_next_match = {}
	load_map(_pick_next_map())


static func sanitize_config(cfg: Dictionary) -> Dictionary:
	var out := DEFAULT_CONFIG.duplicate()
	var map_id := str(cfg.get("map", out.map))
	out.map = map_id if (map_id == "rotation" or Data.MAPS.has(map_id)) else "rotation"
	out.bots_fill = clampi(int(cfg.get("bots_fill", out.bots_fill)), 1, Data.MAX_PLAYERS)
	out.difficulty = clampi(int(cfg.get("difficulty", out.difficulty)), 0, 2)
	out.kill_limit = clampi(int(cfg.get("kill_limit", out.kill_limit)), 1, 200)
	out.time_limit = clampi(int(cfg.get("time_limit", out.time_limit)), 60, 3600)
	out.mutators = bool(cfg.get("mutators", out.mutators))
	var mut := str(cfg.get("mutator", out.mutator))
	out.mutator = mut if Data.MUTATORS.has(mut) else "none"
	var tod := str(cfg.get("time_of_day", out.time_of_day))
	out.time_of_day = tod if tod in Data.TIMES_OF_DAY else "day"
	return out


## Rotation plays every map once in a shuffled order, then reshuffles (never the same map twice in a row).
func _pick_next_map() -> String:
	if config.map != "rotation":
		return config.map
	if _rotation.is_empty():
		_rotation = Data.MAP_ROTATION.duplicate()
		_rotation.shuffle()
		if _rotation.size() > 1 and _rotation[0] == current_map:
			_rotation.reverse()
	return _rotation.pop_front()


## Picks a match's mutator (roughly half the matches are classic; never the same mutator twice
## in a row) and lighting: {mutator, time_of_day}.
func _roll_match_variety(previous: String) -> Dictionary:
	var mutator := "none"
	if config.mutators and (previous != "none" or randf() < 0.6):
		var options: Array = Data.MUTATORS.keys()
		options.erase("none")
		options.erase(previous)
		if previous == "none" or randf() < 0.5:
			mutator = options.pick_random()
	return {"mutator": mutator, "time_of_day": Data.TIMES_OF_DAY.pick_random()}


# ---------------------------------------------------------------- server: map flow

## Server only: send every peer (including us) into a fresh match on map_id. `variety` is the
## {mutator, time_of_day} already announced for it; empty rolls a fresh one.
func load_map(map_id: String, variety := {}) -> void:
	assert(multiplayer.is_server())
	current_map = map_id
	if variety.is_empty():
		variety = _roll_match_variety(config.mutator)
	config.mutator = variety.mutator
	config.time_of_day = variety.time_of_day
	_next_match = {}
	for id: int in players:
		if id != 1:
			_rpc_load_match.rpc_id(id, map_id, config)
	get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)


## Server only: decides (once per match) which map, mutator and lighting come next, so the
## results screen can show it. next_match() then plays exactly this.
func plan_next_match() -> Dictionary:
	if _next_match.is_empty():
		var variety := _roll_match_variety(config.mutator)
		_next_match = {"map": _pick_next_map(), "mutator": variety.mutator, "time_of_day": variety.time_of_day}
	return _next_match


## Server only: called by the World when a match has ended and the results delay is over (or
## the players voted to skip it).
func next_match() -> void:
	if multiplayer.is_server():
		var plan := plan_next_match()
		load_map(plan.map, plan)


## Sends this player's current Profile.peer_info() (loadout and cosmetics changed between
## matches) to the server; it takes effect from their next spawn in the next match.
func update_my_info() -> void:
	if players.is_empty():
		return
	if multiplayer.is_server():
		_apply_info(1, Profile.peer_info())
	else:
		_rpc_update_info.rpc_id(1, Profile.peer_info())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_update_info(info: Dictionary) -> void:
	if multiplayer.is_server():
		_apply_info(multiplayer.get_remote_sender_id(), info)


## Server: replaces a registered peer's info, keeping the (already unique) name it joined with.
func _apply_info(id: int, info: Dictionary) -> void:
	if not players.has(id):
		return
	var clean := sanitize_info(info)
	clean.name = players[id].name
	players[id] = clean
	_rpc_sync_players.rpc(players)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_load_match(map_id: String, cfg: Dictionary) -> void:
	if not Data.MAPS.has(map_id):
		return
	current_map = map_id
	config = sanitize_config(cfg)
	status.emit("Loading %s..." % Data.MAPS[map_id].name)
	get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)


# ---------------------------------------------------------------- registration

func _on_connected_to_server() -> void:
	_connect_timer = null
	status.emit("Connected. Joining match...")
	_rpc_register.rpc_id(1, Profile.peer_info(), PROTOCOL_VERSION)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(info: Dictionary, version: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		_kick(id, "Version mismatch: host runs protocol %d, you run %d." % [PROTOCOL_VERSION, version])
		return
	if players.size() >= Data.MAX_PLAYERS:
		_kick(id, "Server is full.")
		return
	var clean := sanitize_info(info)
	clean.name = _unique_name(clean.name)
	players[id] = clean
	_rpc_sync_players.rpc(players)
	players_changed.emit()
	_rpc_load_match.rpc_id(id, current_map, config)


## Accepts only known ids and a clean name from untrusted peers.
static func sanitize_info(info: Dictionary) -> Dictionary:
	var clean := {
		"name": Profile.sanitize_name(str(info.get("name", ""))),
		"outfit": str(info.get("outfit", "classic")),
		"hat": str(info.get("hat", "none")),
		"skin": str(info.get("skin", "default")),
		"primary": str(info.get("primary", "smg")),
		"secondary": str(info.get("secondary", "pistol")),
		"level": clampi(int(info.get("level", 1)), 1, 9999),
	}
	if clean.name.is_empty():
		clean.name = "Player"
	if not Data.OUTFITS.has(clean.outfit): clean.outfit = "classic"
	if not Data.HATS.has(clean.hat): clean.hat = "none"
	if not Data.SKINS.has(clean.skin): clean.skin = "default"
	if not Data.WEAPONS.has(clean.primary) or Data.WEAPONS[clean.primary].slot != "primary": clean.primary = "smg"
	if not Data.WEAPONS.has(clean.secondary) or Data.WEAPONS[clean.secondary].slot != "secondary": clean.secondary = "pistol"
	return clean


func _unique_name(wanted: String) -> String:
	var taken := {}
	for id: int in players:
		taken[players[id].name] = true
	if not taken.has(wanted):
		return wanted
	var n := 2
	while taken.has("%s (%d)" % [wanted.substr(0, 12), n]):
		n += 1
	return "%s (%d)" % [wanted.substr(0, 12), n]


func _kick(id: int, reason: String) -> void:
	_rpc_kicked.rpc_id(id, reason)
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		var peer := multiplayer.multiplayer_peer
		if peer is ENetMultiplayerPeer and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			peer.disconnect_peer(id))


@rpc("authority", "call_remote", "reliable")
func _rpc_kicked(reason: String) -> void:
	last_error = reason
	status.emit(reason)
	leave()


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_players(all: Dictionary) -> void:
	players = all
	players_changed.emit()


# ---------------------------------------------------------------- connection events

func _on_peer_connected(_id: int) -> void:
	pass  # Peers register themselves via _rpc_register once their connection is up.


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.erase(id):
		_rpc_sync_players.rpc(players)
		players_changed.emit()


func _on_connection_failed() -> void:
	last_error = "Could not reach the host. Check the IP, port and firewall."
	status.emit(last_error)
	_close_peer()


func _on_connect_timeout(peer: ENetMultiplayerPeer) -> void:
	if _connect_timer == null or multiplayer.multiplayer_peer != peer:
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		last_error = "Connection timed out. Check the IP, port and firewall."
		status.emit(last_error)
		_close_peer()


func _on_server_disconnected() -> void:
	if _leaving:
		return
	last_error = "Lost connection to the host."
	status.emit(last_error)
	leave()
