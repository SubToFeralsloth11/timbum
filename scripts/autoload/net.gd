extends Node
## Session layer: hosting, joining, the peer registry, and moving everyone between the menu and matches.
## Match gameplay RPCs live on the World node (scripts/game/world.gd).
##
## Ways to connect (addons/netlink), so players never have to know an IP:
## - DIRECT: one ENet server reachable four ways at once: same-Wi-Fi discovery (NetLinkLan), an
##   internet room code through noray with NAT punch-through and relay fallback (NetLinkNoray),
##   a virtual-LAN address (Tailscale/ZeroTier), or a plain IP / hostname.
## - STEAM: a Steam lobby + SteamMultiplayerPeer; the lobby id is the code, friends can join from Steam.
## - WEBRTC: a "W-XXXXXX" code through PeerJS signalling and STUN.

signal status(text: String)
signal players_changed
## room_code / how friends can join changed (host side).
signal invite_changed

enum Link { DIRECT, STEAM, WEBRTC }

const DEFAULT_PORT := 7777
## UDP port hosts answer same-Wi-Fi discovery on.
const DISCOVERY_PORT := 47777
const GAME_ID := "timbum"
## 5: tacticals, grapple relay, _s_explode carries the kind, lean/slide state flags, new weapons.
## 6: prone state flag.
## 7: charms, win emotes, draw animations and attachment levels in peer_info; win emote at match end.
## 8: Tactical mode (config `mode`, team/weapon-pickup/marker RPCs).
## 9: Team Deathmatch and Infected (mode controllers' RPCs, role fields in entity info).
## 10: Gun Game and King of the Block (their controllers' RPCs, `ladder` / `no_grenades` in info).
## 11: killstreak rewards (config `streaks`, Streaks RPCs, the shield in World._s_damaged).
## 12: quick pings (Pings RPCs).
const PROTOCOL_VERSION := 12
const CONNECT_TIMEOUT := 8.0
## A room-code join first tries a direct (NAT punch-through) link this long, then the relay.
const NAT_CONNECT_TIMEOUT := 6.0
## Steam and WebRTC connections negotiate through a third party first, so they get longer.
const RELAYED_CONNECT_TIMEOUT := 20.0
const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

const DEFAULT_CONFIG := {
	## A Data.MODES id: "ffa" (deathmatch), "tdm", "gungame", "koth", "infected" or "tactical"
	## (see MatchMode).
	"mode": "ffa",
	"map": "rotation",
	"bots_fill": 8,
	"difficulty": 1,
	"kill_limit": 20,
	"time_limit": 480,
	## Roll a random mutator each match.
	"mutators": true,
	## Killstreak rewards (Streaks). Missing from a config: the mode's default (Streaks.default_for).
	"streaks": true,
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
## How the current session was hosted or joined.
var link := Link.DIRECT
## Host: the code friends type into Join (noray id, "W-..." or Steam lobby id); "" until ready.
var room_code := ""
## Host: the ENet port of a DIRECT session (LAN discovery advertises it).
var host_port := 0

var lan: NetLinkLan
var noray: NetLinkNoray
var steam: NetLinkSteam
var webrtc: NetLinkWebRtc

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
## Joining by room code over a direct link: retry through the relay if it fails.
var _relay_retry_code := ""
## Bumped whenever the session is closed, so async host/join steps from before give up.
var _attempt := 0
## Host: why there is no room code (service unreachable), shown instead of the code.
var room_code_error := ""
## Joining by typed address (so a failure hints at address/port/firewall).
var _joined_by_address := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	lan = NetLinkLan.new(GAME_ID, DISCOVERY_PORT)
	noray = NetLinkNoray.new()
	steam = NetLinkSteam.new(GAME_ID)
	webrtc = NetLinkWebRtc.new(GAME_ID)
	for n: Node in [lan, noray, steam, webrtc]:
		add_child(n)
	noray.code_ready.connect(func(code: String) -> void:
		room_code = code
		room_code_error = ""
		invite_changed.emit()
		status.emit("Room code ready: %s" % code))
	noray.failed.connect(_on_link_failed)
	webrtc.failed.connect(_on_link_failed)
	steam.invite_accepted.connect(func(lobby_id: int) -> void: join_steam_lobby(lobby_id))
	var lobby := steam.lobby_from_command_line()
	if lobby != 0:
		join_steam_lobby.call_deferred(lobby)


# ---------------------------------------------------------------- entry points

func play_offline(cfg: Dictionary) -> void:
	_close_peer()
	offline = true
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_server(cfg)


## Starts a match others can join. DIRECT hosts an ENet server on `port`; STEAM and WEBRTC
## first register with their service (await it). Returns OK or the failure (also sent to `status`).
func host(port: int, cfg: Dictionary, p_link := Link.DIRECT) -> Error:
	_close_peer()
	var attempt := _attempt
	var peer: MultiplayerPeer
	var code := ""
	match p_link:
		Link.DIRECT:
			var enet := ENetMultiplayerPeer.new()
			# One spare slot past the 11 clients that fit, so a 12th joiner connects and is told
			# "Server is full." by _rpc_register instead of timing out.
			var err := enet.create_server(port, Data.MAX_PLAYERS)
			if err != OK:
				status.emit("Could not host on port %d (%s). Is it already in use?" % [port, error_string(err)])
				return err
			peer = enet
			host_port = port
		Link.STEAM:
			status.emit("Creating a Steam lobby...")
			var r: Dictionary = await steam.host(Data.MAX_PLAYERS, Profile.peer_info().name)
			if attempt != _attempt:
				return ERR_SKIP
			if r.peer == null:
				status.emit(r.error)
				return FAILED
			peer = r.peer
			code = str(steam.lobby_id)
		Link.WEBRTC:
			status.emit("Getting a WebRTC room code...")
			var r: Dictionary = await webrtc.host()
			if attempt != _attempt:
				return ERR_SKIP
			if r.peer == null:
				status.emit(r.error)
				return FAILED
			peer = r.peer
			code = r.code
	offline = false
	link = p_link
	room_code = code
	multiplayer.multiplayer_peer = peer
	if p_link == Link.DIRECT:
		lan.advertise(_lan_info)
		noray.start_host(peer as ENetMultiplayerPeer)
	_start_server(cfg)
	invite_changed.emit()
	return OK


## Joins by IP, hostname, virtual-LAN address (Tailscale/ZeroTier) or tunnel address (playit.gg).
func join(address: String, port: int) -> Error:
	_close_peer()
	address = address.strip_edges()
	if address.is_empty():
		status.emit("Enter the host's address.")
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status.emit("Could not connect to %s:%d (%s)." % [address, port, error_string(err)])
		return err
	status.emit("Connecting to %s:%d..." % [address, port])
	_begin_client(peer, Link.DIRECT, CONNECT_TIMEOUT)
	_joined_by_address = true
	return OK


## Joins by any room code: noray id, "W-XXXXXX" (WebRTC) or a Steam lobby id.
func join_code(code: String) -> Error:
	_close_peer()
	code = code.strip_edges()
	match NetLinkAddresses.code_kind(code):
		NetLinkAddresses.CodeKind.STEAM:
			return await join_steam_lobby(int(code))
		NetLinkAddresses.CodeKind.WEBRTC:
			var attempt := _attempt
			status.emit("Connecting through WebRTC...")
			var r: Dictionary = await webrtc.join(code)
			if attempt != _attempt:
				return ERR_SKIP
			if r.peer == null:
				status.emit(r.error)
				return FAILED
			_begin_client(r.peer, Link.WEBRTC, RELAYED_CONNECT_TIMEOUT)
			return OK
		NetLinkAddresses.CodeKind.NORAY:
			return await _join_noray(code, false)
	status.emit("That doesn't look like a room code.")
	return ERR_INVALID_PARAMETER


func join_steam_lobby(lobby_id: int) -> Error:
	_close_peer()
	var attempt := _attempt
	status.emit("Joining the Steam lobby...")
	var r: Dictionary = await steam.join(lobby_id)
	if attempt != _attempt:
		return ERR_SKIP
	if r.peer == null:
		status.emit(r.error)
		return FAILED
	_begin_client(r.peer, Link.STEAM, RELAYED_CONNECT_TIMEOUT)
	return OK


## Host: opens the Steam friend picker for the lobby (false when not hosting on Steam).
func invite_steam_friends() -> bool:
	return link == Link.STEAM and steam.invite_friends()


func _join_noray(code: String, relay: bool) -> Error:
	var attempt := _attempt
	status.emit("Trying the relay..." if relay else "Finding the host...")
	var r: Dictionary = await noray.join(code, relay)
	if attempt != _attempt:
		return ERR_SKIP
	if r.error == "nat":
		return await _join_noray(code, true)
	if r.peer == null:
		status.emit(r.error)
		return FAILED
	status.emit("Connecting through the relay..." if relay else "Connecting directly...")
	_begin_client(r.peer, Link.DIRECT, CONNECT_TIMEOUT if relay else NAT_CONNECT_TIMEOUT)
	_relay_retry_code = "" if relay else code
	return OK


func _begin_client(peer: MultiplayerPeer, p_link: Link, timeout: float) -> void:
	offline = false
	link = p_link
	multiplayer.multiplayer_peer = peer
	_connect_timer = get_tree().create_timer(timeout)
	_connect_timer.timeout.connect(_on_connect_timeout.bind(peer))


## Same-Wi-Fi discovery answer.
func _lan_info() -> Dictionary:
	var host_name: String = players[1].name if players.has(1) else Profile.peer_info().name
	return {name = host_name, port = host_port, players = players.size(), max = Data.MAX_PLAYERS}


## Host: the room code service dropped (or never answered). LAN, IP and already-connected
## players are unaffected.
func _on_link_failed(reason: String) -> void:
	room_code = ""
	room_code_error = reason
	invite_changed.emit()
	status.emit(reason)


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
	_attempt += 1
	_connect_timer = null
	_relay_retry_code = ""
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	offline = false
	lan.stop_advertising()
	noray.stop()
	webrtc.stop()
	steam.leave_lobby()
	link = Link.DIRECT
	host_port = 0
	room_code_error = ""
	_joined_by_address = false
	if not room_code.is_empty():
		room_code = ""
		invite_changed.emit()


func _start_server(cfg: Dictionary) -> void:
	config = sanitize_config(cfg)
	players = {1: Profile.peer_info()}
	players_changed.emit()
	_rotation.clear()
	_next_match = {}
	load_map(_pick_next_map())


static func sanitize_config(cfg: Dictionary) -> Dictionary:
	var out := DEFAULT_CONFIG.duplicate()
	var mode := str(cfg.get("mode", out.mode))
	out.mode = mode if Data.MODES.has(mode) else "ffa"
	var map_id := str(cfg.get("map", out.map))
	out.map = map_id if (map_id == "rotation" or Data.MAP_ROTATION.has(map_id)) else "rotation"
	out.bots_fill = clampi(int(cfg.get("bots_fill", out.bots_fill)), 1, Data.MAX_PLAYERS)
	out.difficulty = clampi(int(cfg.get("difficulty", out.difficulty)), 0, 2)
	# `kill_limit` is each mode's limit: kills (Deathmatch), the team score (Team Deathmatch), the
	# ladder length (Gun Game) or the points to win (King of the Block).
	var default_limit: int = {"tdm": TeamDeathmatch.DEFAULT_KILL_LIMIT, "gungame": GunGame.max_length(),
		"koth": KingOfTheBlock.DEFAULT_SCORE_LIMIT}.get(out.mode, out.kill_limit)
	out.kill_limit = clampi(int(cfg.get("kill_limit", default_limit)), 1, 200)
	if out.mode == "gungame":
		out.kill_limit = clampi(out.kill_limit, 2, GunGame.max_length())
	out.time_limit = clampi(int(cfg.get("time_limit", out.time_limit)), 60, 3600)
	out.mutators = bool(cfg.get("mutators", out.mutators))
	out.streaks = bool(cfg.get("streaks", Streaks.default_for(out.mode)))
	var mut := str(cfg.get("mutator", out.mutator))
	out.mutator = mut if Data.MUTATORS.has(mut) else "none"
	var tod := str(cfg.get("time_of_day", out.time_of_day))
	out.time_of_day = tod if tod in Data.TIMES_OF_DAY else "day"
	if out.mode == "tactical":
		# Tactical is always 25 v 25 in the building, with no mutators.
		out.map = Data.TACTICAL_MAP
		out.bots_fill = Tactical.PLAYERS
		out.mutators = false
		out.mutator = "none"
	elif (out.mode == "infected" or out.mode == "gungame") and World.LOADOUT_MUTATORS.has(out.mutator):
		# Infected keeps everyone's own loadout, Gun Game hands out the ladder's guns: no
		# loadout mutators.
		out.mutator = "none"
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
		if config.mode == "infected" or config.mode == "gungame":
			for m: String in World.LOADOUT_MUTATORS:
				options.erase(m)
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
	# A repeat would rename the peer and reload its match.
	if players.has(id):
		return
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
		"tactical": str(info.get("tactical", "flash")),
		"charm": str(info.get("charm", "none")),
		"emote": str(info.get("emote", "wave")),
		"draw": str(info.get("draw", "standard")),
		"mods": {},
		"level": clampi(int(info.get("level", 1)), 1, 9999),
	}
	var mods: Variant = info.get("mods", {})
	if typeof(mods) == TYPE_DICTIONARY:
		for id: String in Data.ATTACHMENTS:
			var lvl := clampi(int(mods.get(id, 0)) if typeof(mods.get(id, 0)) in [TYPE_INT, TYPE_FLOAT] else 0, 0, int(Data.ATTACHMENTS[id].max))
			if lvl > 0:
				clean.mods[id] = lvl
	if clean.name.is_empty():
		clean.name = "Player"
	if not Data.OUTFITS.has(clean.outfit): clean.outfit = "classic"
	if not Data.HATS.has(clean.hat): clean.hat = "none"
	if not Data.SKINS.has(clean.skin): clean.skin = "default"
	if not Data.WEAPONS.has(clean.primary) or Data.WEAPONS[clean.primary].slot != "primary": clean.primary = "smg"
	if not Data.WEAPONS.has(clean.secondary) or Data.WEAPONS[clean.secondary].slot != "secondary": clean.secondary = "pistol"
	if not Data.TACTICALS.has(clean.tactical): clean.tactical = "flash"
	if not Data.CHARMS.has(clean.charm): clean.charm = "none"
	if not Data.EMOTES.has(clean.emote): clean.emote = "wave"
	if not Data.DRAWS.has(clean.draw): clean.draw = "standard"
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
		if peer != null and not (peer is OfflineMultiplayerPeer) and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
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
	_connection_attempt_failed("Could not reach the host.")


func _on_connect_timeout(peer: MultiplayerPeer) -> void:
	if _connect_timer == null or multiplayer.multiplayer_peer != peer:
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		_connection_attempt_failed("Connection timed out.")


func _connection_attempt_failed(what: String) -> void:
	if not _relay_retry_code.is_empty():
		var code := _relay_retry_code
		_close_peer()
		status.emit("No direct route to the host. Trying the relay...")
		_join_noray(code, true)
		return
	var hint := ""
	match link:
		Link.DIRECT:
			hint = " Check the address, port and the host's firewall." if _joined_by_address else ""
		Link.WEBRTC:
			hint = " " + webrtc.last_error if not webrtc.last_error.is_empty() else " The routers may block WebRTC; try a room code instead."
		Link.STEAM:
			hint = " Both players need Steam open and signed in."
	last_error = what + hint
	status.emit(last_error)
	_close_peer()


func _on_server_disconnected() -> void:
	if _leaving:
		return
	last_error = "Lost connection to the host."
	status.emit(last_error)
	leave()
