class_name NetLinkLan
extends Node
## Same-Wi-Fi discovery without typing an IP. A host answers UDP queries on `discovery_port`;
## a browser broadcasts a query every second and lists whoever answers.
##
## Query:  "NETLINK?<game_id>"
## Answer: "NETLINK!" + JSON {game, name, port, players, max}

signal hosts_changed(hosts: Array[Dictionary])

const QUERY_PREFIX := "NETLINK?"
const ANSWER_PREFIX := "NETLINK!"
const QUERY_INTERVAL := 1.0
## A host that has not answered for this long drops off the list.
const HOST_TTL_MSEC := 3500

var game_id := ""
var discovery_port := 0

var _advert: PacketPeerUDP
## Returns {name, port, players, max} for the current session.
var _advert_info: Callable
var _browser: PacketPeerUDP
var _query_t := 0.0
## "ip:port" -> {name, address, port, players, max, seen}
var _hosts := {}


func _init(p_game_id: String, p_discovery_port: int) -> void:
	game_id = p_game_id
	discovery_port = p_discovery_port
	name = "NetLinkLan"


func _ready() -> void:
	set_process(false)


## Host: answer discovery queries until stop_advertising(). `info` is called per answer.
func advertise(info: Callable) -> Error:
	stop_advertising()
	var udp := PacketPeerUDP.new()
	var err := udp.bind(discovery_port)
	if err != OK:
		# Another host on this machine already owns the port; LAN friends can still use the IP.
		return err
	_advert = udp
	_advert_info = info
	set_process(true)
	return OK


func stop_advertising() -> void:
	if _advert:
		_advert.close()
	_advert = null
	_update_processing()


func is_advertising() -> bool:
	return _advert != null


## Client: start listing hosts (hosts_changed fires whenever the list changes).
func browse() -> void:
	stop_browsing()
	_browser = PacketPeerUDP.new()
	_browser.set_broadcast_enabled(true)
	if _browser.bind(0) != OK:
		_browser = null
		return
	_query_t = QUERY_INTERVAL
	set_process(true)


func stop_browsing() -> void:
	if _browser:
		_browser.close()
	_browser = null
	if not _hosts.is_empty():
		_hosts.clear()
		hosts_changed.emit(hosts())
	_update_processing()


func hosts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h: Dictionary in _hosts.values():
		out.append(h)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return out


func _update_processing() -> void:
	set_process(_advert != null or _browser != null)


func _exit_tree() -> void:
	stop_advertising()
	stop_browsing()


func _process(delta: float) -> void:
	if _advert:
		_answer_queries()
	if _browser:
		_query_t += delta
		if _query_t >= QUERY_INTERVAL:
			_query_t = 0.0
			_send_queries()
		_read_answers()


func _answer_queries() -> void:
	while _advert.get_available_packet_count() > 0:
		var text := _advert.get_packet().get_string_from_utf8()
		var ip := _advert.get_packet_ip()
		var port := _advert.get_packet_port()
		if text != QUERY_PREFIX + game_id or ip.is_empty():
			continue
		var info: Dictionary = _advert_info.call()
		info.game = game_id
		_advert.set_dest_address(ip, port)
		_advert.put_packet((ANSWER_PREFIX + JSON.stringify(info)).to_utf8_buffer())


func _send_queries() -> void:
	var query := (QUERY_PREFIX + game_id).to_utf8_buffer()
	var targets: Array[String] = ["255.255.255.255", "127.0.0.1"]
	# Subnet broadcasts reach hosts on networks where the limited broadcast is filtered.
	for entry in NetLinkAddresses.local_addresses():
		var parts: PackedStringArray = str(entry.address).split(".")
		targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	for t in targets:
		_browser.set_dest_address(t, discovery_port)
		_browser.put_packet(query)
	_prune()


func _read_answers() -> void:
	var changed := false
	while _browser.get_available_packet_count() > 0:
		var text := _browser.get_packet().get_string_from_utf8()
		var ip := _browser.get_packet_ip()
		if not text.begins_with(ANSWER_PREFIX):
			continue
		var info: Variant = JSON.parse_string(text.trim_prefix(ANSWER_PREFIX))
		if not info is Dictionary or str(info.get("game", "")) != game_id:
			continue
		var port := int(info.get("port", 0))
		if port < 1 or port > 65535:
			continue
		# The same host answers on loopback and on its LAN address; keep one row per machine.
		var address := ip
		if ip == "127.0.0.1":
			address = _first_local_or(ip)
		var key := "%s:%d" % [address, port]
		var row := {
			name = str(info.get("name", "Host")).left(32),
			address = address,
			port = port,
			players = int(info.get("players", 0)),
			max = int(info.get("max", 0)),
			seen = Time.get_ticks_msec(),
		}
		if not _hosts.has(key) or _hosts[key].players != row.players or _hosts[key].name != row.name:
			changed = true
		_hosts[key] = row
	if changed:
		hosts_changed.emit(hosts())


func _prune() -> void:
	var now := Time.get_ticks_msec()
	var changed := false
	for key: String in _hosts.keys():
		if now - int(_hosts[key].seen) > HOST_TTL_MSEC:
			_hosts.erase(key)
			changed = true
	if changed:
		hosts_changed.emit(hosts())


static func _first_local_or(fallback: String) -> String:
	for entry in NetLinkAddresses.local_addresses():
		if entry.kind == "LAN":
			return entry.address
	return fallback
