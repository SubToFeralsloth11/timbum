class_name NetLinkSteam
extends Node
## Steam lobbies + SteamMultiplayerPeer (GodotSteam GDExtension in addons/godotsteam).
## Steam relays the traffic, so nobody needs an IP or port forwarding; both players need the
## Steam client running and signed in. The lobby id doubles as a room code, and friends can join
## from the Steam overlay or the friends list ("Join Game").
##
## Everything goes through Engine.get_singleton("Steam") and ClassDB, so this script still
## loads on a platform where the GodotSteam library is missing; available() is then false.

## A friend accepted an invite or clicked "Join Game" in Steam while we are running.
signal invite_accepted(lobby_id: int)

## Spacewar, Valve's free test app every Steam account can use. A shipped game uses its own id.
const DEFAULT_APP_ID := 480
const LOBBY_TYPE_PUBLIC := 2
const LOBBY_COMPARISON_EQUAL := 0
const LOBBY_DISTANCE_WORLDWIDE := 3
const ENTER_SUCCESS := 1
const TIMEOUT := 12.0

var app_id := DEFAULT_APP_ID
var game_id := ""
var lobby_id := 0

var _steam: Object
var _init_error := ""


func _init(p_game_id: String, p_app_id := DEFAULT_APP_ID) -> void:
	game_id = p_game_id
	app_id = p_app_id
	name = "NetLinkSteam"


## True when the GodotSteam library loaded on this platform (Steam itself may still be closed).
static func library_loaded() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


## Starts the Steam API on first use. Returns "" or why Steam can't be used.
func ensure_started() -> String:
	if _steam:
		return ""
	if not library_loaded():
		return "Steam support isn't included for this platform."
	var steam := Engine.get_singleton("Steam")
	var result: Dictionary = steam.steamInitEx(app_id, true)
	if int(result.get("status", -1)) != 0:
		var why := str(result.get("verbal", "unknown error")).strip_edges().trim_suffix(".")
		_init_error = "Steam isn't available (%s). Open Steam, sign in, then try again." % why
		return _init_error
	_steam = steam
	_steam.join_requested.connect(func(lobby: int, _friend: int) -> void: invite_accepted.emit(lobby))
	return ""


func persona_name() -> String:
	return _steam.getPersonaName() if _steam else ""


## Steam launches the game with "+connect_lobby <id>" when a friend joins from Steam before it runs.
func lobby_from_command_line() -> int:
	var args := OS.get_cmdline_args()
	for i in args.size() - 1:
		if args[i] == "+connect_lobby" and args[i + 1].is_valid_int():
			return int(args[i + 1])
	return 0


## Host: creates a lobby and a listening peer. Returns {peer, error}.
func host(max_members: int, host_name: String) -> Dictionary:
	var err := ensure_started()
	if err != "":
		return {peer = null, error = err}
	leave_lobby()
	_steam.createLobby(LOBBY_TYPE_PUBLIC, max_members)
	var got: Variant = await NetLinkWait.for_signal(get_tree(), _steam.lobby_created, TIMEOUT)
	if got == null or int(got[0]) != 1:
		return {peer = null, error = "Steam could not create a lobby. Check your connection to Steam."}
	lobby_id = int(got[1])
	_steam.setLobbyData(lobby_id, "netlink_game", game_id)
	_steam.setLobbyData(lobby_id, "name", host_name)
	_steam.setLobbyJoinable(lobby_id, true)
	_steam.setRichPresence("connect", "+connect_lobby %d" % lobby_id)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var e: int = peer.create_host(0)
	if e != OK:
		leave_lobby()
		return {peer = null, error = "Steam could not start hosting (%s)." % error_string(e)}
	peer.set("server_relay", true)
	return {peer = peer, error = ""}


## Client: joins the lobby and connects to its owner. Returns {peer, error}.
func join(p_lobby_id: int) -> Dictionary:
	var err := ensure_started()
	if err != "":
		return {peer = null, error = err}
	leave_lobby()
	_steam.joinLobby(p_lobby_id)
	var got: Variant = await NetLinkWait.for_signal(get_tree(), _steam.lobby_joined, TIMEOUT)
	if got == null:
		return {peer = null, error = "Steam did not answer. Is the lobby code right?"}
	if int(got[3]) != ENTER_SUCCESS:
		return {peer = null, error = "Could not join that Steam lobby (it may be full or closed)."}
	lobby_id = int(got[0])
	var owner: int = _steam.getLobbyOwner(lobby_id)
	if owner == 0 or owner == _steam.getSteamID():
		leave_lobby()
		return {peer = null, error = "That Steam lobby has no host."}
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var e: int = peer.create_client(owner, 0)
	if e != OK:
		leave_lobby()
		return {peer = null, error = "Steam could not connect to the host (%s)." % error_string(e)}
	peer.set("server_relay", true)
	return {peer = peer, error = ""}


## Open lobbies of this game: [{lobby_id, name, players, max}].
func find_lobbies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ensure_started() != "":
		return out
	_steam.addRequestLobbyListStringFilter("netlink_game", game_id, LOBBY_COMPARISON_EQUAL)
	_steam.addRequestLobbyListDistanceFilter(LOBBY_DISTANCE_WORLDWIDE)
	_steam.requestLobbyList()
	var got: Variant = await NetLinkWait.for_signal(get_tree(), _steam.lobby_match_list, TIMEOUT)
	if got == null:
		return out
	for id: int in got[0]:
		out.append({
			lobby_id = id,
			name = _steam.getLobbyData(id, "name"),
			players = _steam.getNumLobbyMembers(id),
			max = _steam.getLobbyMemberLimit(id),
		})
	return out


## Opens the Steam overlay's friend picker for the current lobby.
func invite_friends() -> bool:
	if not _steam or lobby_id == 0:
		return false
	_steam.activateGameOverlayInviteDialog(lobby_id)
	return true


func leave_lobby() -> void:
	if _steam and lobby_id != 0:
		_steam.leaveLobby(lobby_id)
		_steam.clearRichPresence()
	lobby_id = 0
