class_name NetLinkWait
extends RefCounted
## Await a signal with a timeout (plain `await sig` would hang forever if it never fires).


## The signal's arguments, or null on timeout or when `cancelled` (a Dictionary) gets `stop = true`.
static func for_signal(tree: SceneTree, sig: Signal, timeout: float, cancelled := {}) -> Variant:
	var box := {done = false, args = []}
	var on_fire := func(...args: Array) -> void:
		if not box.done:
			box.done = true
			box.args = args
	sig.connect(on_fire)
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not box.done and Time.get_ticks_msec() < deadline and not cancelled.get("stop", false):
		await tree.process_frame
	if sig.is_connected(on_fire):
		sig.disconnect(on_fire)
	return box.args if box.done else null
