class_name NetLinkWebRtc
extends Node
## WebRTC room codes ("W-K7Q2XP"): peers find each other through the free PeerJS signalling
## server, then talk directly (STUN punches through most routers). Needs the webrtc-native
## GDExtension (addons/webrtc) on desktop.
##
## Signalling goes over the PeerJS WebSocket (relayed to "dst" with "src" added). The public
## server drops connections that send anything but PeerJS-shaped messages, so every message is
## a PeerJS CANDIDATE envelope carrying ours in extra payload fields:
##   nl = "offer"   client -> host   {sdp, pid}   pid: the client's multiplayer peer id
##   nl = "answer"  host -> client   {sdp}
##   nl = "ice"     both ways        {mid, index, sdp}
## PeerJS answers EXPIRE when "dst" is not connected (wrong code / host gone).
## The host's PeerJS id is "<game id>-<code>", so the code is all a client needs.

## Hosting only: the signalling server dropped, so new players can no longer join by code.
signal failed(reason: String)

const CODE_PREFIX := "W-"
const CODE_LETTERS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6
const SIGNAL_URL := "wss://0.peerjs.com/peerjs?key=peerjs&id=%s&token=%s"
const HEARTBEAT_SEC := 5.0
const TIMEOUT := 12.0
const ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}]}

var game_id := ""
var code := ""
## Client: why the last attempt ended, when the link knows better than "connection failed".
var last_error := ""

var _ws: WebSocketPeer
var _ws_open := false
var _heartbeat_t := 0.0
var _rtc: WebRTCMultiplayerPeer
var _hosting := false
## Host: PeerJS id of each joining client -> WebRTCPeerConnection. Client: "host" -> connection.
var _conns := {}
var _remote_id := ""
var _session := 0
## Client: when to give up waiting for the host's answer (0 = not waiting).
var _answer_deadline := 0


func _init(p_game_id: String) -> void:
	game_id = p_game_id.to_lower()
	name = "NetLinkWebRtc"


static func library_loaded() -> bool:
	return ClassDB.class_exists("WebRTCLibPeerConnection")


## Host: returns {peer, code, error}.
func host() -> Dictionary:
	stop()
	if not library_loaded():
		return {peer = null, code = "", error = "WebRTC support isn't included for this platform."}
	var session := _session
	for attempt in 3:
		var c := ""
		for i in CODE_LENGTH:
			c += CODE_LETTERS[randi() % CODE_LETTERS.length()]
		var err := await _open_signalling("%s-%s" % [game_id, c.to_lower()], session)
		if err == "taken":
			continue
		if err != "":
			return {peer = null, code = "", error = err}
		code = CODE_PREFIX + c
		_rtc = WebRTCMultiplayerPeer.new()
		_rtc.create_server()
		_hosting = true
		return {peer = _rtc, code = code, error = ""}
	return {peer = null, code = "", error = "Could not reserve a WebRTC room code."}


## Client: returns {peer (connecting), error}. The connection finishes in the background.
func join(room_code: String) -> Dictionary:
	stop()
	if not library_loaded():
		return {peer = null, error = "WebRTC support isn't included for this platform."}
	var session := _session
	var c := room_code.strip_edges().to_upper().trim_prefix(CODE_PREFIX)
	if c.length() != CODE_LENGTH:
		return {peer = null, error = "WebRTC codes look like W-K7Q2XP."}
	var err := await _open_signalling("%s-c%d" % [game_id, randi()], session)
	if err != "":
		return {peer = null, error = err}
	_remote_id = "%s-%s" % [game_id, c.to_lower()]
	var pid := randi_range(2, 2147483647)
	_rtc = WebRTCMultiplayerPeer.new()
	_rtc.create_client(pid)
	var conn := _new_connection(_remote_id)
	_rtc.add_peer(conn, 1)
	_conns["host"] = conn
	conn.session_description_created.connect(func(type: String, sdp: String) -> void:
		conn.set_local_description(type, sdp)
		_send("offer", _remote_id, {sdp = sdp, pid = pid}))
	conn.create_offer()
	_answer_deadline = Time.get_ticks_msec() + int(TIMEOUT * 1000.0)
	return {peer = _rtc, error = ""}


func stop() -> void:
	_session += 1
	if _ws:
		_ws.close()
	_ws = null
	_ws_open = false
	_conns.clear()
	_rtc = null
	_hosting = false
	_remote_id = ""
	code = ""
	last_error = ""
	_answer_deadline = 0


func is_hosting() -> bool:
	return _hosting


## Connects to PeerJS as `id`. Returns "", "taken", or a reason.
func _open_signalling(id: String, session: int) -> String:
	_ws = WebSocketPeer.new()
	var token := "%x" % randi()
	if _ws.connect_to_url(SIGNAL_URL % [id, token]) != OK:
		return "Can't reach the WebRTC signalling server."
	var deadline := Time.get_ticks_msec() + int(TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if session != _session or _ws == null:
			return "Cancelled."
		_ws.poll()
		if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		while _ws.get_available_packet_count() > 0:
			var msg: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
			if not msg is Dictionary:
				continue
			match str(msg.get("type", "")):
				"OPEN":
					_ws_open = true
					_heartbeat_t = 0.0
					return ""
				"ID-TAKEN":
					_ws.close()
					return "taken"
				"ERROR":
					_ws.close()
					return "WebRTC signalling error: %s" % str(msg.get("payload", {}).get("msg", "unknown"))
	if _ws:
		_ws.close()
	return "Can't reach the WebRTC signalling server (0.peerjs.com)."


func _new_connection(remote: String) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize(ICE)
	conn.ice_candidate_created.connect(func(mid: String, index: int, sdp: String) -> void:
		_send("ice", remote, {mid = mid, index = index, sdp = sdp}))
	return conn


func _send(kind: String, dst: String, body: Dictionary) -> void:
	if _ws == null or not _ws_open or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := {type = "data", connectionId = "netlink", candidate = {candidate = "netlink", sdpMid = "0", sdpMLineIndex = 0}, nl = kind}
	payload.merge(body)
	_ws.send_text(JSON.stringify({type = "CANDIDATE", dst = dst, payload = payload}))


func _process(delta: float) -> void:
	if _ws == null or not _ws_open:
		return
	_ws.poll()
	if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_ws_open = false
		if _hosting:
			failed.emit("Lost the WebRTC signalling server; new players can't join by code.")
		return
	_heartbeat_t += delta
	if _heartbeat_t >= HEARTBEAT_SEC and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_heartbeat_t = 0.0
		_ws.send_text(JSON.stringify({type = "HEARTBEAT"}))
	while _ws.get_available_packet_count() > 0:
		var msg: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if msg is Dictionary:
			_on_signal(msg)
	if not _hosting and _rtc and _rtc.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		# A connected client no longer needs signalling.
		_ws.close()
		_ws_open = false
	elif not _hosting and _answer_deadline > 0 and Time.get_ticks_msec() > _answer_deadline:
		_fail_join("No answer for that WebRTC code. Check it and that the host is still running.")


func _on_signal(msg: Dictionary) -> void:
	var type := str(msg.get("type", ""))
	var src := str(msg.get("src", ""))
	var payload: Variant = msg.get("payload", {})
	if not payload is Dictionary:
		return
	if type == "EXPIRE" and not _hosting:
		# The host's id is not connected to PeerJS: wrong code or the host left.
		_fail_join("No game found for that WebRTC code. Check it and that the host is still running.")
		return
	if type != "CANDIDATE":
		return
	var kind := str(payload.get("nl", ""))
	if _hosting:
		match kind:
			"offer":
				_accept_offer(src, payload)
			"ice":
				if _conns.has(src):
					_conns[src].add_ice_candidate(str(payload.get("mid", "")), int(payload.get("index", 0)), str(payload.get("sdp", "")))
	elif src == _remote_id and _conns.has("host"):
		var conn: WebRTCPeerConnection = _conns["host"]
		match kind:
			"answer":
				_answer_deadline = 0
				conn.set_remote_description("answer", str(payload.get("sdp", "")))
			"ice":
				conn.add_ice_candidate(str(payload.get("mid", "")), int(payload.get("index", 0)), str(payload.get("sdp", "")))


## Client: ends a connecting attempt; the multiplayer API then reports connection_failed.
func _fail_join(reason: String) -> void:
	_answer_deadline = 0
	if _rtc and _rtc.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		last_error = reason
		_rtc.close()


func _accept_offer(src: String, payload: Dictionary) -> void:
	var pid := int(payload.get("pid", 0))
	if src.is_empty() or _conns.has(src) or pid < 2 or _rtc.has_peer(pid):
		return
	var conn := _new_connection(src)
	conn.session_description_created.connect(func(type: String, sdp: String) -> void:
		conn.set_local_description(type, sdp)
		_send("answer", src, {sdp = sdp}))
	_rtc.add_peer(conn, pid)
	_conns[src] = conn
	conn.set_remote_description("offer", str(payload.get("sdp", "")))
