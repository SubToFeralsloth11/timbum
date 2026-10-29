class_name NetLinkAddresses
extends RefCounted
## This machine's IPv4 addresses that friends can join on, tagged by network:
## "LAN" (home Wi-Fi / Ethernet) or a virtual LAN ("Tailscale", "ZeroTier", "Hamachi", "Radmin VPN").
## Virtual-LAN apps give both players a shared private network, so joining by that address
## works across the internet with no port forwarding.

## What a room code means, from its shape (see NetLinkNoray / NetLinkWebRtc / NetLinkSteam).
enum CodeKind { INVALID, NORAY, WEBRTC, STEAM }


## [{address, kind}], LAN first, each address once.
static func local_addresses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for iface: Dictionary in IP.get_local_interfaces():
		var iface_name := (str(iface.get("name", "")) + " " + str(iface.get("friendly", ""))).to_lower()
		for addr: String in iface.get("addresses", []):
			if seen.has(addr) or not addr.is_valid_ip_address() or ":" in addr:
				continue
			var kind := address_kind(addr, iface_name)
			if kind.is_empty():
				continue
			seen[addr] = true
			out.append({address = addr, kind = kind})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a.kind == "LAN") != (b.kind == "LAN"):
			return a.kind == "LAN"
		return a.address < b.address)
	return out


## "" for addresses nobody else can reach (loopback, link-local, public).
static func address_kind(addr: String, iface_name := "") -> String:
	var p := addr.split(".")
	if p.size() != 4:
		return ""
	var a := int(p[0])
	var b := int(p[1])
	if "zerotier" in iface_name or iface_name.begins_with("zt") or iface_name.begins_with("feth"):
		return "ZeroTier"
	if "tailscale" in iface_name or (a == 100 and b >= 64 and b <= 127):
		return "Tailscale"
	if a == 25:
		return "Hamachi"
	if a == 26:
		return "Radmin VPN"
	if a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31):
		return "LAN"
	return ""


static func code_kind(code: String) -> CodeKind:
	code = code.strip_edges()
	if code.is_empty():
		return CodeKind.INVALID
	if code.to_upper().begins_with(NetLinkWebRtc.CODE_PREFIX):
		return CodeKind.WEBRTC
	if code.is_valid_int() and code.length() >= 10:
		return CodeKind.STEAM
	for c in code:
		if not (c == "-" or c == "_" or (c >= "0" and c <= "9") or (c.to_lower() >= "a" and c.to_lower() <= "z")):
			return CodeKind.INVALID
	return CodeKind.NORAY
