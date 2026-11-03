class_name OneInTheChamber
extends MatchMode
## One in the Chamber (`Net.config.mode == "oitc"`), free-for-all on the deathmatch maps.
## Everyone carries the Cuber .44 (GUN) with one round and no reserve, plus their own melee
## weapon; no grenades or tacticals, and the map has no ammo or grenade crates (health packs stay:
## melee fights still wear players down). Any Cuber .44 hit kills (`hit_damage`, after the server's
## usual hit validation). Every kill, with any weapon, gives the killer one round (`_s_round`: into
## the empty chamber, else onto the reserve, so rounds stack); a new life starts with one round.
## The server also counts the rounds it handed out (`_rounds`) and drops a Cuber .44 shot from
## anyone who has none left (`server_take_shot`).
## Each player has `Net.config.kill_limit` lives (setup: 1, 3 or 5; LIVES). A player out of lives
## stays dead and follows the others (Spectator dead mode) for the rest of the match. The last
## player with lives left wins at once; at the time limit the most lives left wins, then the most
## kills (eliminated players rank by how long they lasted). Lives live in `Player.info.lives`
## (set by `prepare_info`, sent with the entity, so late joiners see them) and change with
## `_s_lives`, which also carries `info.out_at`, the elimination order.
## Joining after the first life was lost: with the fewest lives anyone still in has (at least 1);
## a human who ran out (or switched to spectating after that) and comes back stays out. After the
## first life is lost no bot joins (a fresh one would bring lives), and one only leaves when a
## joining human would go over Data.MAX_PLAYERS. Killstreaks and mutators are off
## (Net.sanitize_config).

const GUN := "revolver"
## Lives offered in match setup.
const LIVES: Array[int] = [1, 3, 5]
const DEFAULT_LIVES := 3
## Seconds the eliminated player watches their own death before the follow camera starts.
const SPECTATE_DELAY := 3.0
## Farthest a bot fires the Cuber .44 from, per difficulty; past that it runs in with its melee
## weapon.
const BOT_SHOT_RANGE: Array[float] = [12.0, 18.0, 26.0]
## A bot only fires when its crosshair is within this many metres of the target's body centre.
const BOT_SURE_RADIUS := 0.3
## Range a bot holding the Cuber .44 closes to.
const BOT_CLOSE_IN := Vector2(0.0, 8.0)

# Server only.
## Whether anyone has lost a life yet (late joiners and bot balance change after that).
var started := false
## Entity id -> rounds the server handed out and hasn't seen fired.
var _rounds := {}
## Entity id -> Cuber .44 kills.
var _gun_kills := {}
## Peer ids of humans who ran out of lives (or quit playing after the start): they stay out.
var _out_peers := {}
var _out_count := 0
var _final_two := false

# Every peer.
## World.now() the local player was first seen out of lives (-1: not out).
var _out_since := -1.0


func _init() -> void:
	name = "OneInTheChamber"


func _ready() -> void:
	var card := ChamberCard.new()
	card.name = "ChamberCard"
	card.setup(self)
	add_child(card)


static func lives_of(p: Player) -> int:
	return int(p.info.get("lives", 0)) if p != null else 0


## Rounds `p` carries (chamber plus reserve) on this peer.
static func rounds_of(p: Player) -> int:
	if p == null or not p.ammo.has(GUN):
		return 0
	var a: Vector2i = p.ammo[GUN]
	return a.x + a.y


func start_lives() -> int:
	return clampi(int(Net.config.kill_limit), 1, LIVES[-1])


## Players still in: lives left, alive or waiting to respawn.
func players_in() -> Array[Player]:
	var out: Array[Player] = []
	for eid: int in world.entities:
		var p: Player = world.entities[eid]
		if lives_of(p) > 0:
			out.append(p)
	return out


func respawns(eid: int) -> bool:
	return lives_of(world.entities.get(eid)) > 0


func no_respawn_note() -> String:
	return "Out of lives  ·  spectating the rest of the match"


## Only health packs: rounds come from kills, and nobody carries grenades.
func has_pickup(kind: String) -> bool:
	return kind == "health"


func no_ammo_hint() -> String:
	return "NO ROUNDS - A KILL GIVES YOU ONE"


func uses_loadout(_p: Player) -> bool:
	return false


# ================================================================ server

## The Cuber .44 as the only gun, one round, the player's own melee weapon, no grenades, and the
## lives this player starts with.
func prepare_info(info: Dictionary, _team: int) -> Dictionary:
	var out := info.duplicate()
	out.primary = ""
	out.secondary = GUN
	out.no_grenades = true
	out.one_round = true
	out.lives = _join_lives()
	out.out_at = 0
	return out


## Full lives before anyone lost one; after that the fewest lives a player still in has.
func _join_lives() -> int:
	if not started:
		return start_lives()
	var fewest := start_lives()
	for p: Player in players_in():
		fewest = mini(fewest, lives_of(p))
	return maxi(1, fewest)


func server_human_joined(pid: int) -> void:
	if not _out_peers.has(pid):
		super(pid)
		return
	# Back after running out: present (scoreboard, follow camera) but out, ranked below everyone.
	world.server_add_human(pid, -1, false)
	_broadcast(&"_s_lives", [pid, 0, 0])


func server_human_left(pid: int) -> void:
	if started and respawns(pid):
		_out_peers[pid] = true
	super(pid)
	_server_check_end()


## Standard balance until the first life is lost; then no bot joins, and one leaves only when a
## joining human would go over Data.MAX_PLAYERS: an eliminated bot first, else the bot with the
## fewest lives.
func server_balance() -> void:
	if not started:
		world.server_balance_bots()
		return
	var bots: Array[Player] = []
	for eid: int in world.entities:
		if eid < 0:
			bots.append(world.entities[eid])
	var over := Net.playing_count() + bots.size() - Data.MAX_PLAYERS
	if over <= 0:
		return
	bots.sort_custom(func(a: Player, b: Player) -> bool: return lives_of(a) < lives_of(b))
	for i in mini(over, bots.size()):
		world.server_remove_bot(bots[i].id)
	_server_check_end()


func server_on_death(victim_id: int, _killer_id: int, _wid: String) -> void:
	var victim: Player = world.entities.get(victim_id)
	if victim == null or world.match_over:
		return
	started = true
	var left := maxi(0, lives_of(victim) - 1)
	var out_at := 0
	if left == 0:
		_out_count += 1
		out_at = _out_count
		if victim_id > 0:
			_out_peers[victim_id] = true
	# The next life starts with one round again.
	_rounds[victim_id] = 1
	_broadcast(&"_s_lives", [victim_id, left, out_at])


## Server: a Cuber .44 shot needs a round the server handed out.
func server_take_shot(shooter: Player, wid: String) -> bool:
	if wid != GUN:
		return true
	var have := int(_rounds.get(shooter.id, 1))
	if have <= 0:
		return false
	_rounds[shooter.id] = have - 1
	return true


## Any accepted Cuber .44 hit is a kill.
func hit_damage(_shooter: Player, target: Player, wid: String, dmg: float) -> float:
	if wid == GUN and dmg > 0.0:
		return target.max_health() + target.shield + 1.0
	return dmg


## A kill gives the killer a round; one player left with lives ends the match.
func server_on_kill(victim_id: int, killer_id: int, wid: String) -> void:
	if world.match_over:
		return
	var killer: Player = world.entities.get(killer_id)
	if killer_id != victim_id and killer != null and killer.alive:
		_rounds[killer_id] = int(_rounds.get(killer_id, 1)) + 1
		if wid == GUN:
			_gun_kills[killer_id] = int(_gun_kills.get(killer_id, 0)) + 1
		_broadcast(&"_s_round", [killer_id])
	_server_check_end()


func _server_check_end() -> void:
	if not started or world.match_over:
		return
	var left := players_in()
	if left.size() <= 1:
		world.server_end_match()
	elif left.size() == 2 and not _final_two:
		_final_two = true
		_broadcast(&"_s_final_two", [left[0].id, left[1].id])


func server_finish(rows: Array) -> Dictionary:
	annotate_rows(rows)
	sort_rows(rows)
	var in_count := 0
	for r: Dictionary in rows:
		if int(r.lives) > 0:
			in_count += 1
	for i in rows.size():
		var r: Dictionary = rows[i]
		r.won = i == 0
		r.gun_kills = int(_gun_kills.get(int(r.id), 0))
		r.last_standing = i == 0 and in_count == 1 and rows.size() > 1
		r.flawless = i == 0 and int(r.deaths) == 0 and rows.size() > 1
	return {}


# ================================================================ every peer

## `eid` has `left` lives; `out_at` > 0: the elimination order of a player who just ran out.
@rpc("authority", "call_remote", "reliable")
func _s_lives(eid: int, left: int, out_at: int) -> void:
	var p: Player = world.entities.get(eid)
	if p == null:
		return
	var before := lives_of(p)
	p.info.lives = left
	if out_at > 0:
		p.info.out_at = out_at
	world.hud.refresh_scores()
	if world.match_over:
		return
	if p == world.local_player:
		if left == 0:
			world.hud.announce("OUT OF LIVES")
		elif left == 1 and before > 1:
			world.hud.announce("LAST LIFE")
	elif left == 0 and before > 0:
		world.hud.callout("%s IS OUT" % world.display_name(eid).to_upper(), "kill")


## `eid` earned a round with a kill.
@rpc("authority", "call_remote", "reliable")
func _s_round(eid: int) -> void:
	var p: Player = world.entities.get(eid)
	if p == null:
		return
	p.add_round(GUN)
	if p == world.local_player:
		world.hud.callout("+1 ROUND", "streak")


## Two players are left with lives.
@rpc("authority", "call_remote", "reliable")
func _s_final_two(a: int, b: int) -> void:
	world.hud.announce("LAST TWO STANDING")
	world.hud.callout("%s  VS  %s" % [world.display_name(a).to_upper(), world.display_name(b).to_upper()], "kill")


## Out of lives: after SPECTATE_DELAY the camera follows whoever is still in.
func _process(_delta: float) -> void:
	var me := world.local_player
	if me == null or me.alive or lives_of(me) > 0 or world.match_over:
		_out_since = -1.0
		return
	if _out_since < 0.0:
		_out_since = World.now()
	elif World.now() - _out_since >= SPECTATE_DELAY and not world.spectator.is_active():
		world.spectator.begin_dead()


# ================================================================ HUD and results

func annotate_rows(rows: Array) -> void:
	for r: Dictionary in rows:
		var p: Player = world.entities.get(int(r.id))
		if not r.has("lives"):
			r.lives = lives_of(p)
		if not r.has("out_at"):
			r.out_at = int(p.info.get("out_at", 0)) if p != null else 0


## Most lives first; of those out, whoever lasted longer; then kills, then fewest deaths.
func sort_rows(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.lives) != int(b.lives):
			return int(a.lives) > int(b.lives)
		if int(a.out_at) != int(b.out_at):
			return int(a.out_at) > int(b.out_at)
		return a.kills > b.kills if a.kills != b.kills else a.deaths < b.deaths)


func score_columns() -> Array:
	return ["LIVES", "KILLS", "DEATHS"]


func row_cells(r: Dictionary) -> Array:
	var n := int(r.get("lives", 0))
	return ["♥".repeat(n) if n > 0 else "OUT", r.kills, r.deaths]


func row_dimmed(r: Dictionary) -> bool:
	return int(r.get("lives", 0)) <= 0


## The top panel's race is on lives.
func race_value(r: Dictionary) -> int:
	return int(r.get("lives", 0))


func race_limit() -> int:
	return start_lives()


func race_text(value: int) -> String:
	return "%d li%s" % [value, "fe" if value == 1 else "ves"]


## Last one standing, the most Cuber .44 kills, and a win without losing a life.
func extra_highlights(rows: Array) -> Array:
	var out: Array = []
	var me := world.my_id()
	if not rows.is_empty() and bool(rows[0].get("last_standing", false)):
		var n := int(rows[0].lives)
		out.append(["Last one standing:  %s  (%d li%s left)" % [rows[0].name, n, "fe" if n == 1 else "ves"], int(rows[0].id) == me, "last_standing"])
	var best: Dictionary = {}
	for r: Dictionary in rows:
		if int(r.get("gun_kills", 0)) > 0 and (best.is_empty() or int(r.gun_kills) > int(best.gun_kills)):
			best = r
	if not best.is_empty():
		var k := int(best.gun_kills)
		out.append(["Dead Eye:  %s  (%d Cuber .44 kill%s)" % [best.name, k, "" if k == 1 else "s"], int(best.id) == me, "dead_eye"])
	if not rows.is_empty() and bool(rows[0].get("flawless", false)):
		out.append(["Flawless:  %s  (won without losing a life)" % rows[0].name, int(rows[0].id) == me, "flawless"])
	return out


# ================================================================ bots

## Without rounds the melee weapon; with one, the Cuber .44 once the target is within shooting
## range (a little more while already holding it), else run in with the melee weapon.
func bot_weapon_slot(p: Player, target: Player, dist: float) -> int:
	if rounds_of(p) <= 0:
		return 2
	if target == null:
		return 1
	var reach := BOT_SHOT_RANGE[clampi(int(Net.config.difficulty), 0, 2)] + (6.0 if p.current_slot == 1 else 0.0)
	return 1 if dist <= reach else 2


## With the Cuber .44 a bot closes in for a sure shot.
func bot_preferred_range(_p: Player, wid: String) -> Vector2:
	return BOT_CLOSE_IN if wid == GUN else Vector2.ZERO


## The one round only goes when the crosshair (not just the bot's wandering aim point) is on the
## target's body and the target is in range.
func bot_fire_ok(p: Player, target: Player, dist: float, aim_dir: Vector3) -> bool:
	if p.weapon_id() != GUN:
		return true
	if dist > BOT_SHOT_RANGE[clampi(int(Net.config.difficulty), 0, 2)] + 6.0:
		return false
	# The view's error plus the gun's spread cone (hip or sights) must stay on the body.
	var w: Dictionary = Data.WEAPONS[GUN]
	var spread := deg_to_rad(lerpf(float(w.spread_hip), float(w.spread_ads), p.aim_blend))
	var to := target.global_position + Vector3.UP * target.body_center_height() - p.head.global_position
	return aim_dir.angle_to(to.normalized()) + spread <= atan2(BOT_SURE_RADIUS, maxf(dist, 0.5))


## With nobody in sight a bot hunts the nearest player still in, so the match closes.
func bot_roam_goal(p: Player) -> Variant:
	var best: Player = null
	var best_d := INF
	for o: Player in players_in():
		if o == p or not o.alive:
			continue
		var d := p.global_position.distance_squared_to(o.global_position)
		if d < best_d:
			best_d = d
			best = o
	return best.global_position if best != null else null
