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
## The pre-match lobby's state (`lobby`) changed: who is ready, map votes, the countdown.
signal lobby_changed
## A lobby chat line ("" sender: a system message).
signal lobby_chat(sender: String, text: String)
## Server, in a match: peer `pid` asked to spectate (`on`) or to play (World does the switch).
signal spectate_requested(pid: int, on: bool)

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
## 13: prestige rank and mastery camos in peer_info, the weapon id in World._s_hit_confirm, the
##     dropper's gun skin on Tactical weapon spots.
## 14: the pre-match lobby (Net lobby RPCs) and the results screen's next-map vote.
## 15: spectators (`spectator` in peer_info, Net spectate RPCs).
## 16: loadout presets (World._s_loadout: a loadout picked while dead applies at the respawn).
## 17: weapon inspect (Player.FLAG_INSPECT, bit 20 of the state flags).
## 18: sprays (`spray` in peer_info, Sprays RPCs).
## 19: jump pads on the deathmatch maps (map geometry and navigation links).
## 20: melee weapons and five new guns (`melee` in peer_info, a melee argument on
##     World._s_loadout, new weapon ids in shots and weapon indices).
## 21: snapshots in chunks of World.SNAPSHOT_CHUNK entities (several _s_snapshot RPCs per tick).
## 22: the Demolition mutator ("demolition" in config.mutator, Demolition._s_remove).
## 23: custom maps (config.map "custom:<name>", the map hash on _rpc_load_match, the
##     _rpc_request_map / _rpc_map_chunk download).
const PROTOCOL_VERSION := 23
const CONNECT_TIMEOUT := 8.0
## A room-code join first tries a direct (NAT punch-through) link this long, then the relay.
const NAT_CONNECT_TIMEOUT := 6.0
## Steam and WebRTC connections negotiate through a third party first, so they get longer.
const RELAYED_CONNECT_TIMEOUT := 20.0
const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
## Once a majority of the lobby is ready (not everyone), the match starts this many seconds later.
const LOBBY_COUNTDOWN := 10.0
## Maps offered in a map vote (the lobby adds RANDOM_MAP).
const MAP_VOTE_CHOICES := 3
const RANDOM_MAP := "random"
## Spectators allowed on top of Data.MAX_PLAYERS players.
const MAX_SPECTATORS := 4
## Bytes per _rpc_map_chunk, so each packet of a custom map download stays under the MTU.
const MAP_CHUNK := 1000

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
	## A Data.SESSIONS id: "match", or an offline practice session ("range": FiringRange,
	## "tutorial": Tutorial) on Data.RANGE_MAP.
	"session": "match",
}

## peer id -> peer_info dictionary (see Profile.peer_info()). Kept in sync on every peer.
var players := {}
## Join as a spectator (the Join screen's option); sent with the registration.
var join_as_spectator := false
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
## True on every peer while the session waits in the pre-match lobby (hosting online opens it
## before the first match; a peer joining later goes straight into the running match).
var in_lobby := false
## The lobby as every peer sees it: {options: map ids offered for the first match then
## RANDOM_MAP (empty in Tactical: no vote), ready: {peer id: true}, votes: {peer id: option index},
## countdown: seconds left until the countdown starts the match, -1 when none is running}.
var lobby := {}
## Server: Time.get_ticks_msec() when the lobby countdown starts the match (-1: none).
var _lobby_start_ms := -1
## Client: the custom map being downloaded before its match loads: {id, cfg, hash, parts (one
## PackedByteArray or null per chunk), got}; empty when none.
var _map_download := {}
## Server: peer id -> the custom map hash already sent to it (one download per map and peer).
var _map_sent := {}
## Client: size in bytes of the last custom map downloaded (shown by checks).
var map_bytes_received := 0


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
	var steam_lobby := steam.lobby_from_command_line()
	if steam_lobby != 0:
		join_steam_lobby.call_deferred(steam_lobby)
	set_process(false)


# ---------------------------------------------------------------- entry points

func play_offline(cfg: Dictionary) -> void:
	_close_peer()
	offline = true
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_server(cfg)


## Opens the Firing Range (or, with `tutorial`, the tutorial in it): an offline practice session.
func play_range(tutorial := false) -> void:
	play_offline({"session": "tutorial" if tutorial else "range"})


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
			# Remote slots = the 11 other players + MAX_SPECTATORS, so the spectator places stay open
			# in a full match. A player past Data.MAX_PLAYERS still connects (while spectator places
			# are free) and is told "Server is full." by _rpc_register instead of timing out.
			var err := enet.create_server(port, (Data.MAX_PLAYERS - 1) + MAX_SPECTATORS)
			if err != OK:
				status.emit("Could not host on port %d (%s). Is it already in use?" % [port, error_string(err)])
				return err
			peer = enet
			host_port = port
		Link.STEAM:
			status.emit("Creating a Steam lobby...")
			# Lobby members include the host: every player plus the spectator places.
			var r: Dictionary = await steam.host(Data.MAX_PLAYERS + MAX_SPECTATORS, Profile.peer_info().name)
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
	# Everyone gathers in the lobby before the first match (offline play starts straight away).
	_start_server(cfg, true)
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
	return {name = host_name, port = host_port, players = playing_count(), max = Data.MAX_PLAYERS}


## Host: the room code service dropped (or never answered). LAN, IP and already-connected
## players are unaffected.
func _on_link_failed(reason: String) -> void:
	room_code = ""
	room_code_error = reason
	print("Net: no room code: ", reason)
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
	_leave_lobby()
	_map_download = {}
	_map_sent.clear()
	if not room_code.is_empty():
		room_code = ""
		invite_changed.emit()


func _start_server(cfg: Dictionary, with_lobby := false) -> void:
	config = sanitize_config(cfg)
	# Practice sessions are offline only; a hosted game is always a match.
	if with_lobby:
		config.session = "match"
	players = {1: Profile.peer_info()}
	players_changed.emit()
	_rotation.clear()
	_next_match = {}
	if with_lobby:
		open_lobby()
	else:
		load_map(_pick_next_map())


# ---------------------------------------------------------------- pre-match lobby

## Server only: everyone waits in the lobby (scenes/lobby.tscn) until the first match starts:
## when every human is ready, when the host presses Start, or LOBBY_COUNTDOWN seconds after a
## majority got ready. Peers registering meanwhile join the lobby.
func open_lobby() -> void:
	assert(multiplayer.is_server())
	in_lobby = true
	_lobby_start_ms = -1
	lobby = {"options": _map_vote_options("", true), "ready": {}, "votes": {}, "countdown": -1.0}
	set_process(true)
	lobby_changed.emit()
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)


## The maps of a vote: MAP_VOTE_CHOICES maps of the mode's pool, with `first` (if any) as the
## first option and without `exclude`; plus RANDOM_MAP when `with_random`. Empty in Tactical (one map).
func _map_vote_options(first: String, with_random: bool, exclude := "") -> Array:
	if config.mode == "tactical":
		return []
	var pool: Array = Data.MAP_ROTATION.duplicate()
	pool.shuffle()
	if exclude != first:
		pool.erase(exclude)
	if first.is_empty() and config.map != "rotation":
		# The host's own map pick is always one of the choices (and wins a tie).
		first = config.map
	if not first.is_empty():
		pool.erase(first)
		pool.push_front(first)
	var out := pool.slice(0, MAP_VOTE_CHOICES)
	if with_random:
		out.append(RANDOM_MAP)
	return out


## The option a vote picked: the one with the most votes, or -1 on no votes or a tie at the top.
static func vote_winner(counts: Array) -> int:
	var best := -1
	var top := 0
	for i in counts.size():
		if int(counts[i]) > top:
			top = int(counts[i])
			best = i
		elif int(counts[i]) == top and top > 0:
			best = -1
	return best


## Votes per option from {peer id: option index}, counting only peers still in the session.
func vote_counts(votes: Dictionary, options: int) -> Array:
	var counts: Array = []
	counts.resize(options)
	counts.fill(0)
	for pid: int in votes:
		if players.has(pid) and int(votes[pid]) >= 0 and int(votes[pid]) < options:
			counts[int(votes[pid])] += 1
	return counts


## Humans in the lobby who are ready.
func lobby_ready_count() -> int:
	var n := 0
	for pid: int in (lobby.get("ready", {}) as Dictionary):
		if players.has(pid):
			n += 1
	return n


## Ready check majority: more than half the humans (the results screen's skip vote uses the same).
static func majority(humans: int) -> int:
	return humans / 2 + 1


## This player is (not) ready.
func lobby_set_ready(on: bool) -> void:
	if multiplayer.is_server():
		_server_lobby_ready(1, on)
	else:
		_rpc_lobby_ready.rpc_id(1, on)


## This player votes for lobby.options[index].
func lobby_vote(index: int) -> void:
	if multiplayer.is_server():
		_server_lobby_vote(1, index)
	else:
		_rpc_lobby_vote.rpc_id(1, index)


func lobby_say(text: String) -> void:
	if multiplayer.is_server():
		_server_lobby_chat(1, text)
	else:
		_rpc_lobby_chat.rpc_id(1, text)


## Host: starts the first match now, ready or not.
func lobby_start() -> void:
	if multiplayer.is_server() and in_lobby:
		_lobby_begin()


# ---------------------------------------------------------------- spectators

## Whether peer `pid` watches without playing (`players[pid].spectator`, set by the server).
func is_spectator(pid: int) -> bool:
	return bool((players.get(pid, {}) as Dictionary).get("spectator", false))


## Peers taking a player slot (everyone but the spectators); bots fill up to `bots_fill`.
func playing_count() -> int:
	var n := 0
	for pid: int in players:
		if not is_spectator(pid):
			n += 1
	return n


func spectator_ids() -> Array:
	var out: Array = []
	for pid: int in players:
		if is_spectator(pid):
			out.append(pid)
	out.sort()
	return out


## This player asks to spectate (`on`) or to play: in the lobby (applies from the first match)
## or in a match (World removes or spawns the player). Offline it spectates the bots.
func set_spectating(on: bool) -> void:
	if multiplayer.is_server():
		_server_request_spectating(1, on)
	else:
		_rpc_set_spectating.rpc_id(1, on)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_spectating(on: bool) -> void:
	if multiplayer.is_server():
		_server_request_spectating(multiplayer.get_remote_sender_id(), on)


func _server_request_spectating(pid: int, on: bool) -> void:
	if not players.has(pid) or is_spectator(pid) == on:
		return
	if in_lobby:
		var err := server_set_spectating(pid, on)
		_server_lobby_said("", err if not err.is_empty() else "%s %s" % [players[pid].name, "will spectate" if on else "will play"])
		_server_lobby_update()
	else:
		spectate_requested.emit(pid, on)


## Server: sets peer `pid`'s spectator flag and tells everyone. Returns "" or why it was refused
## (no player slot or spectator place left).
func server_set_spectating(pid: int, on: bool) -> String:
	if not players.has(pid):
		return "Unknown player."
	if is_spectator(pid) == on:
		return ""
	if on and spectator_ids().size() >= MAX_SPECTATORS:
		return "%s can't spectate: all %d spectator places are taken." % [players[pid].name, MAX_SPECTATORS]
	if not on and playing_count() >= Data.MAX_PLAYERS:
		return "%s can't play: the match is full (%d players)." % [players[pid].name, Data.MAX_PLAYERS]
	players[pid].spectator = on
	_rpc_sync_players.rpc(players)
	players_changed.emit()
	return ""


func _server_lobby_ready(pid: int, on: bool) -> void:
	if not in_lobby or not players.has(pid):
		return
	if on:
		lobby.ready[pid] = true
	else:
		lobby.ready.erase(pid)
	_server_lobby_update()


func _server_lobby_vote(pid: int, index: int) -> void:
	if not in_lobby or not players.has(pid) or index < 0 or index >= (lobby.options as Array).size():
		return
	lobby.votes[pid] = index
	_server_lobby_update()


func _server_lobby_chat(pid: int, text: String) -> void:
	text = text.strip_edges().replace("[", "(").replace("]", ")").substr(0, World.MAX_CHAT_LENGTH)
	if not in_lobby or text.is_empty() or not players.has(pid):
		return
	_server_lobby_said(str(players[pid].name), text)


func _server_lobby_said(sender: String, text: String) -> void:
	for id: int in players:
		if id != 1:
			_rpc_lobby_said.rpc_id(id, sender, text)
	lobby_chat.emit(sender, text)


## Server: starts the match once everyone is ready, runs the countdown while a majority (but
## not everyone) is, and sends every peer the lobby.
func _server_lobby_update() -> void:
	if not in_lobby:
		return
	for pid: int in (lobby.ready as Dictionary).keys():
		if not players.has(pid):
			lobby.ready.erase(pid)
	for pid: int in (lobby.votes as Dictionary).keys():
		if not players.has(pid):
			lobby.votes.erase(pid)
	var n_ready := lobby_ready_count()
	if n_ready >= players.size():
		_lobby_begin()
		return
	if n_ready >= majority(players.size()):
		if _lobby_start_ms < 0:
			_lobby_start_ms = Time.get_ticks_msec() + int(LOBBY_COUNTDOWN * 1000.0)
	else:
		_lobby_start_ms = -1
	lobby.countdown = maxf(0.0, (_lobby_start_ms - Time.get_ticks_msec()) / 1000.0) if _lobby_start_ms >= 0 else -1.0
	for id: int in players:
		if id != 1:
			_rpc_lobby_state.rpc_id(id, lobby)
	lobby_changed.emit()


func _process(_delta: float) -> void:
	if in_lobby and multiplayer.is_server() and _lobby_start_ms >= 0 and Time.get_ticks_msec() >= _lobby_start_ms:
		_lobby_begin()


## Server: leaves the lobby for the first match on the voted map (RANDOM_MAP: any of the mode's
## pool; no votes or a tie: the host's pick, or the rotation's first map).
func _lobby_begin() -> void:
	var options: Array = lobby.options
	var pick := vote_winner(vote_counts(lobby.votes, options.size()))
	var map_id := ""
	if pick >= 0:
		map_id = str(options[pick])
		if map_id == RANDOM_MAP:
			map_id = Data.MAP_ROTATION.pick_random()
	_leave_lobby()
	if map_id.is_empty():
		map_id = _pick_next_map()
	elif config.map == "rotation":
		# The voted map counts as this round of the rotation's pick.
		if _rotation.is_empty():
			_rotation = Data.MAP_ROTATION.duplicate()
			_rotation.shuffle()
		_rotation.erase(map_id)
	load_map(map_id)


func _leave_lobby() -> void:
	in_lobby = false
	lobby = {}
	_lobby_start_ms = -1
	set_process(false)


@rpc("authority", "call_remote", "reliable")
func _rpc_enter_lobby(cfg: Dictionary, state: Dictionary) -> void:
	config = sanitize_config(cfg)
	in_lobby = true
	lobby = state
	status.emit("Joined the lobby.")
	lobby_changed.emit()
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_state(state: Dictionary) -> void:
	if in_lobby:
		lobby = state
		lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_said(sender: String, text: String) -> void:
	lobby_chat.emit(sender, text)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_lobby_ready(on: bool) -> void:
	if multiplayer.is_server():
		_server_lobby_ready(multiplayer.get_remote_sender_id(), on)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_lobby_vote(index: int) -> void:
	if multiplayer.is_server():
		_server_lobby_vote(multiplayer.get_remote_sender_id(), index)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_lobby_chat(text: String) -> void:
	if multiplayer.is_server():
		_server_lobby_chat(multiplayer.get_remote_sender_id(), text)


static func sanitize_config(cfg: Dictionary) -> Dictionary:
	var out := DEFAULT_CONFIG.duplicate()
	var mode := str(cfg.get("mode", out.mode))
	out.mode = mode if Data.MODES.has(mode) else "ffa"
	var map_id := str(cfg.get("map", out.map))
	out.map = map_id if (map_id == "rotation" or Data.MAP_ROTATION.has(map_id) or map_id == Data.RANGE_MAP or CustomMaps.is_custom(map_id)) else "rotation"
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
	var session := str(cfg.get("session", out.session))
	out.session = session if session in Data.SESSIONS else "match"
	if out.session != "match":
		# The Firing Range and the tutorial: the range map in daylight, no mutators or rewards.
		out.mode = "ffa"
		out.map = Data.RANGE_MAP
		out.bots_fill = 1
		out.mutators = false
		out.mutator = "none"
		out.streaks = false
		out.time_of_day = "day"
		return out
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
	if config.session != "match":
		return {"mutator": "none", "time_of_day": "day"}
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
## {mutator, time_of_day} already announced for it; empty rolls a fresh one. A custom map
## (CustomMaps) is read from its file and always plays its own time of day; clients missing it
## download it first (_rpc_load_match).
func load_map(map_id: String, variety := {}) -> void:
	assert(multiplayer.is_server())
	if CustomMaps.is_custom(map_id) and not CustomMaps.activate_file(map_id):
		last_error = "The custom map %s is missing or can't be played; playing Village." % CustomMaps.name_of(map_id)
		status.emit(last_error)
		map_id = "village"
	current_map = map_id
	if variety.is_empty():
		variety = _roll_match_variety(config.mutator)
	config.mutator = variety.mutator
	config.time_of_day = _time_of_day_for(map_id, variety.time_of_day)
	_next_match = {}
	var map_hash := _map_hash(map_id)
	for id: int in players:
		if id != 1:
			_rpc_load_match.rpc_id(id, map_id, config, map_hash)
	get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)


## The time of day a match on `map_id` plays: a custom map's own, else `rolled`.
func _time_of_day_for(map_id: String, rolled: String) -> String:
	if not CustomMaps.is_custom(map_id):
		return rolled
	var map := CustomMaps.map_for(map_id)
	return str(map.time_of_day) if not map.is_empty() else rolled


## The hash clients check their copy of a custom map against ("" for a built-in map).
func _map_hash(map_id: String) -> String:
	if CustomMaps.is_custom(map_id) and not CustomMaps.active.is_empty() and CustomMaps.active.id == map_id:
		return CustomMaps.active.hash
	return ""


## Server only: decides (once per match) which map, mutator and lighting come next, so the
## results screen can show it. next_match() then plays exactly this.
func plan_next_match() -> Dictionary:
	if _next_match.is_empty():
		var variety := _roll_match_variety(config.mutator)
		_next_match = {"map": _pick_next_map(), "mutator": variety.mutator, "time_of_day": variety.time_of_day}
		_next_match.time_of_day = _time_of_day_for(_next_match.map, variety.time_of_day)
	return _next_match


## Server only: the results screen's map choices: the planned next map first (it also wins a tie
## or no votes), then other maps of the mode's pool, never the map just played. Empty in Tactical.
func next_map_options() -> Array:
	return _map_vote_options(str(plan_next_match().map), false, current_map)


## Server only: the results screen's map vote picked `map_id` over the planned map. In a rotation
## the picked map leaves the rotation and the planned one goes to its end, so neither is lost.
func vote_next_map(map_id: String) -> void:
	var plan := plan_next_match()
	if not Data.MAP_ROTATION.has(map_id) or map_id == plan.map:
		return
	if config.map == "rotation":
		_rotation.erase(map_id)
		_rotation.append(plan.map)
	plan.map = map_id


## Server only: called by the World when a match has ended and the results delay is over (or
## the players voted to skip it).
func next_match() -> void:
	if multiplayer.is_server():
		var plan := plan_next_match()
		load_map(plan.map, plan)


## Sends this player's current Profile.peer_info() (loadout and cosmetics changed between
## matches, or a loadout preset picked while dead) to the server; the loadout takes effect from
## their next spawn (World._server_next_loadout), never mid-life.
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


## Server: replaces a registered peer's info, keeping the (already unique) name it joined with
## and its spectator flag (only set_spectating changes that).
func _apply_info(id: int, info: Dictionary) -> void:
	if not players.has(id):
		return
	var clean := sanitize_info(info)
	clean.name = players[id].name
	clean.spectator = is_spectator(id)
	players[id] = clean
	_rpc_sync_players.rpc(players)
	players_changed.emit()


## `map_hash`: a custom map's CustomMaps.active hash. A client that has it (in memory or in
## CustomMaps.CACHE_DIR) loads at once; otherwise it asks the server for the bytes first.
@rpc("authority", "call_remote", "reliable")
func _rpc_load_match(map_id: String, cfg: Dictionary, map_hash: String) -> void:
	if CustomMaps.is_custom(map_id):
		if not CustomMaps.activate_cached(map_id, map_hash):
			_map_download = {"id": map_id, "cfg": cfg, "hash": map_hash, "parts": [], "got": 0}
			status.emit("Downloading the map %s..." % CustomMaps.name_of(map_id))
			_rpc_request_map.rpc_id(1, map_hash)
			return
	elif not Data.MAPS.has(map_id):
		return
	_enter_match(map_id, cfg)


func _enter_match(map_id: String, cfg: Dictionary) -> void:
	_map_download = {}
	_leave_lobby()
	current_map = map_id
	config = sanitize_config(cfg)
	status.emit("Loading %s..." % MapBuilder.map_name(map_id))
	get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)


## Server: a client asks for the custom map it is about to play: its deflated file
## (CustomMaps.active.payload) goes out in MAP_CHUNK pieces, once per peer and map.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_map(map_hash: String) -> void:
	if not multiplayer.is_server() or CustomMaps.active.is_empty() or CustomMaps.active.hash != map_hash:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or _map_sent.get(id, "") == map_hash:
		return
	_map_sent[id] = map_hash
	var payload: PackedByteArray = CustomMaps.active.payload
	var count := ceili(payload.size() / float(MAP_CHUNK))
	for i in count:
		_rpc_map_chunk.rpc_id(id, map_hash, i, count, payload.slice(i * MAP_CHUNK, (i + 1) * MAP_CHUNK))


## Client: one piece of the custom map being downloaded. With the last one in, the map is
## checked against its hash, cached and played.
@rpc("authority", "call_remote", "reliable")
func _rpc_map_chunk(map_hash: String, index: int, count: int, bytes: PackedByteArray) -> void:
	var d := _map_download
	if d.is_empty() or d.hash != map_hash or count <= 0 or count > CustomMaps.MAX_PAYLOAD / MAP_CHUNK + 1 \
			or index < 0 or index >= count or bytes.size() > MAP_CHUNK:
		return
	var parts: Array = d.parts
	if parts.size() != count:
		parts.resize(count)
		d.got = 0
	if parts[index] == null:
		parts[index] = bytes
		d.got += 1
	if d.got < count:
		return
	var payload := PackedByteArray()
	for p: PackedByteArray in parts:
		payload.append_array(p)
	_map_download = {}
	map_bytes_received = payload.size()
	if not CustomMaps.activate_payload(d.id, payload, map_hash):
		_rpc_kicked("The host's map %s didn't arrive intact." % CustomMaps.name_of(d.id))
		return
	_enter_match(d.id, d.cfg)


# ---------------------------------------------------------------- registration

func _on_connected_to_server() -> void:
	_connect_timer = null
	status.emit("Connected. Joining match...")
	var info := Profile.peer_info()
	info.spectator = join_as_spectator
	_rpc_register.rpc_id(1, info, PROTOCOL_VERSION)


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
	var clean := sanitize_info(info)
	# Spectators take no player slot, but only MAX_SPECTATORS of them fit.
	if clean.spectator and spectator_ids().size() >= MAX_SPECTATORS:
		_kick(id, "No spectator places left (%d)." % MAX_SPECTATORS)
		return
	if not clean.spectator and playing_count() >= Data.MAX_PLAYERS:
		_kick(id, "Server is full.")
		return
	clean.name = _unique_name(clean.name)
	players[id] = clean
	_rpc_sync_players.rpc(players)
	players_changed.emit()
	if in_lobby:
		_rpc_enter_lobby.rpc_id(id, config, lobby)
		_server_lobby_said("", "%s joined the lobby" % clean.name)
		_server_lobby_update()
		return
	_rpc_load_match.rpc_id(id, current_map, config, _map_hash(current_map))


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
		"melee": str(info.get("melee", "knife")),
		"charm": str(info.get("charm", "none")),
		"emote": str(info.get("emote", "wave")),
		"draw": str(info.get("draw", "standard")),
		"spray": str(info.get("spray", "gg")),
		"mods": {},
		"level": clampi(int(info.get("level", 1)), 1, 9999),
		"prestige": clampi(int(info.get("prestige", 0)) if typeof(info.get("prestige", 0)) in [TYPE_INT, TYPE_FLOAT] else 0, 0, Data.PRESTIGE_MAX),
		"camos": [],
		# Watches without a player entity (see Spectator); only a real bool counts.
		"spectator": info.get("spectator", false) is bool and bool(info.get("spectator", false)),
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
	if not Data.is_melee(clean.melee): clean.melee = "knife"
	if not Data.CHARMS.has(clean.charm): clean.charm = "none"
	if not Data.EMOTES.has(clean.emote): clean.emote = "wave"
	if not Data.DRAWS.has(clean.draw): clean.draw = "standard"
	if not Data.SPRAYS.has(clean.spray): clean.spray = "gg"
	# Mastery camos: known weapon ids, each once (the Gold unlock is the player's own profile's).
	var camos: Variant = info.get("camos", [])
	if typeof(camos) == TYPE_ARRAY:
		for id: Variant in (camos as Array).slice(0, Data.WEAPONS.size()):
			if typeof(id) in [TYPE_STRING, TYPE_STRING_NAME] and Data.WEAPONS.has(str(id)) and not clean.camos.has(str(id)):
				clean.camos.append(str(id))
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
	var who: String = str(players[id].name) if players.has(id) else ""
	if players.erase(id):
		_map_sent.erase(id)
		_rpc_sync_players.rpc(players)
		players_changed.emit()
		if in_lobby:
			_server_lobby_said("", "%s left the lobby" % who)
			_server_lobby_update()


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
