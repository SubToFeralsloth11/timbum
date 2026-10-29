class_name NetLinkNoray
extends Node
## Internet room codes through a noray server (https://github.com/foxssake/noray), with no port
## forwarding: noray tells host and client each other's public address so they can punch
## through their routers (NAT), and relays the traffic when that fails.
##
## Protocol (TCP, one command per line):
##   -> register-host            <- set-oid <open id>, set-pid <private id>
##   -> connect <oid>            <- connect <ip:port>       (both sides; punch through NAT)
##   -> connect-relay <oid>      <- connect-relay <port>    (both sides; relay on the noray host)
## Registration: the private id sent over UDP to REGISTRAR_PORT records which public address
## and port noray forwards to; the registrar answers "OK".
## The open id is the room code.

signal code_ready(code: String)
## Hosting only: lost the noray server, so new players can no longer join by code.
signal failed(reason: String)

const DEFAULT_SERVER := "tomfol.io"
const TCP_PORT := 8890
const REGISTRAR_PORT := 8809
const TIMEOUT := 8.0
const HANDSHAKE_TIMEOUT := 5.0
## How often a host re-sends its registration (also keeps its router's port mapping open).
const KEEPALIVE_SEC := 10.0
const HANDSHAKE_SEC := 6.0

signal _command(cmd: String, data: String)

var server := DEFAULT_SERVER
var code := ""

var _tcp := StreamPeerTCP.new()
var _buf := ""
var _server_ip := ""
var _pid := ""
var _oid := ""
var _host_enet: ENetMultiplayerPeer
var _keepalive_t := 0.0
## Bumped by stop() so coroutines from an older session give up.
var _session := 0


func _init(p_server := DEFAULT_SERVER) -> void:
	server = p_server
	name = "NetLinkNoray"


func _ready() -> void:
	_command.connect(_on_command)


## Host: give the ENet server (already listening) a room code. Emits code_ready or failed.
func start_host(enet: ENetMultiplayerPeer) -> void:
	stop()
	var session := _session
	var err := await _register()
	if session != _session:
		return
	if err != "":
		failed.emit(err)
		return
	_host_enet = enet
	_keepalive_t = 0.0
	_register_enet()
	code = _oid
	code_ready.emit(code)


## Client: returns {peer: ENetMultiplayerPeer (connecting, not yet connected) or null, error: String}.
## `relay` skips NAT punch-through and goes through the noray server.
func join(room_code: String, relay: bool) -> Dictionary:
	stop()
	var session := _session
	var err := await _register()
	if err != "":
		return {peer = null, error = err}
	var udp := PacketPeerUDP.new()
	udp.bind(0)
	udp.set_dest_address(_server_ip, REGISTRAR_PORT)
	var registered := false
	var deadline := Time.get_ticks_msec() + int(TIMEOUT * 1000.0)
	while not registered and Time.get_ticks_msec() < deadline and session == _session:
		udp.put_packet(_pid.to_utf8_buffer())
		await get_tree().create_timer(0.1).timeout
		while udp.get_available_packet_count() > 0:
			registered = udp.get_packet().get_string_from_utf8() == "OK"
	if session != _session:
		udp.close()
		return {peer = null, error = "Cancelled."}
	if not registered:
		udp.close()
		stop()
		return {peer = null, error = "The room code server did not answer over UDP. Is UDP blocked on this network?"}
	var local_port := udp.get_local_port()
	var cmd := "connect-relay" if relay else "connect"
	_put("%s %s" % [cmd, room_code.strip_edges()])
	var target: Variant = null
	deadline = Time.get_ticks_msec() + int(TIMEOUT * 1000.0)
	while target == null and Time.get_ticks_msec() < deadline and session == _session:
		var got: Variant = await NetLinkWait.for_signal(get_tree(), _command, maxf(0.05, (deadline - Time.get_ticks_msec()) / 1000.0))
		if got is Array and got[0] == cmd:
			target = got[1]
	# noray answers an unknown open id with the bare command and no address.
	if target == null or str(target).strip_edges().is_empty():
		udp.close()
		stop()
		return {peer = null, error = "No game found for that room code. Check it (codes are case-sensitive) and that the host is still running."}
	var address := _server_ip
	var port := 0
	if relay:
		port = int(target)
	else:
		address = str(target).get_slice(":", 0)
		port = int(str(target).get_slice(":", 1))
	udp.set_dest_address(address, port)
	var shook := await _handshake(udp, session)
	udp.close()
	# The client no longer needs noray once it knows where to send.
	stop()
	if not shook:
		return {peer = null, error = "nat" if not relay else "Could not reach the host through the relay."}
	var peer := ENetMultiplayerPeer.new()
	var e := peer.create_client(address, port, 0, 0, 0, local_port)
	if e != OK:
		return {peer = null, error = "Could not start the connection (%s)." % error_string(e)}
	return {peer = peer, error = ""}


func stop() -> void:
	_session += 1
	_tcp.disconnect_from_host()
	_buf = ""
	_pid = ""
	_oid = ""
	code = ""
	_host_enet = null


func is_hosting() -> bool:
	return _host_enet != null


## Connects to noray and fetches ids. Returns "" or a reason.
func _register() -> String:
	var session := _session
	var ips := IP.resolve_hostname_addresses(server, IP.TYPE_IPV4)
	if ips.is_empty():
		return "Room codes need the internet: can't find the code server %s." % server
	_server_ip = ips[0]
	_tcp = StreamPeerTCP.new()
	if _tcp.connect_to_host(_server_ip, TCP_PORT) != OK:
		return "Can't reach the room code server %s." % server
	var deadline := Time.get_ticks_msec() + int(TIMEOUT * 1000.0)
	while _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		_tcp.poll()
		await get_tree().process_frame
		if session != _session:
			return "Cancelled."
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_tcp.disconnect_from_host()
		return "Can't reach the room code server %s." % server
	_tcp.set_no_delay(true)
	_put("register-host")
	while (_pid.is_empty() or _oid.is_empty()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if session != _session:
			return "Cancelled."
	if _pid.is_empty() or _oid.is_empty():
		_tcp.disconnect_from_host()
		return "The room code server did not answer."
	return ""


## Host: registration goes out of the ENet socket itself, so noray learns the address and port
## that the game server is reachable on. The registrar's "OK" lands in ENet, which drops it.
func _register_enet() -> void:
	if _host_enet == null or _host_enet.host == null:
		return
	for i in 3:
		_host_enet.host.socket_send(_server_ip, REGISTRAR_PORT, _pid.to_utf8_buffer())


func _put(line: String) -> void:
	if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_tcp.put_data((line + "\n").to_utf8_buffer())


func _process(delta: float) -> void:
	if _tcp.get_status() == StreamPeerTCP.STATUS_NONE:
		return
	_tcp.poll()
	var status := _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		var n := _tcp.get_available_bytes()
		if n > 0:
			_ingest(_tcp.get_utf8_string(n))
	elif status == StreamPeerTCP.STATUS_ERROR or (status == StreamPeerTCP.STATUS_NONE and is_hosting()):
		if is_hosting():
			stop()
			failed.emit("Lost the room code server; new players can't join by code.")
		return
	if is_hosting():
		if _host_enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			stop()
			return
		_keepalive_t += delta
		if _keepalive_t >= KEEPALIVE_SEC:
			_keepalive_t = 0.0
			_register_enet()


func _ingest(text: String) -> void:
	_buf += text
	while "\n" in _buf:
		var i := _buf.find("\n")
		var line := _buf.left(i).strip_edges()
		_buf = _buf.substr(i + 1)
		if line.is_empty():
			continue
		var cmd := line.get_slice(" ", 0)
		var data := line.substr(cmd.length() + 1) if " " in line else ""
		_command.emit(cmd, data)


func _on_command(cmd: String, data: String) -> void:
	match cmd:
		"set-oid":
			_oid = data
		"set-pid":
			_pid = data
		"connect":
			if is_hosting() and ":" in data:
				_punch(data.get_slice(":", 0), int(data.get_slice(":", 1)))
		"connect-relay":
			if is_hosting():
				_punch(_server_ip, int(data))


## Host: the ENet socket can't read raw packets, so it just sends the "done" handshake state to
## the joining player for a while; that opens the router mapping for their ENet connect.
func _punch(address: String, port: int) -> void:
	var session := _session
	var packet := "$rwx".to_ascii_buffer()
	var until := Time.get_ticks_msec() + int(HANDSHAKE_SEC * 1000.0)
	while Time.get_ticks_msec() < until and session == _session and _host_enet and _host_enet.host:
		_host_enet.host.socket_send(address, port, packet)
		await get_tree().create_timer(0.1).timeout


## Client side of netfox's packet handshake: each side sends "$" + r(read) w(wrote) x(handshake).
## True once both sides heard each other (or we heard them, which is usually enough).
func _handshake(udp: PacketPeerUDP, session: int) -> bool:
	var did_read := false
	var did_handshake := false
	var until := Time.get_ticks_msec() + int(HANDSHAKE_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < until and session == _session:
		while udp.get_available_packet_count() > 0:
			var state := udp.get_packet().get_string_from_ascii()
			if not state.begins_with("$"):
				continue
			did_read = true
			if "r" in state:
				did_handshake = true
			if "x" in state and did_handshake:
				return true
		udp.put_packet(("$%sw%s" % ["r" if did_read else "-", "x" if did_handshake else "-"]).to_ascii_buffer())
		await get_tree().create_timer(0.1).timeout
	return did_read
