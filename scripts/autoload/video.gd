class_name Video
extends RefCounted
## The Video settings (Settings > Video): their option names, the quality presets, and applying
## them live to the window, the main viewport, the shadow and AO globals and every built map's
## sun and environment (MapBuilder.apply_graphics). Profile owns the values and calls `apply`
## whenever a setting changes, `tick` every frame (dynamic resolution) and `apply_fps` when the
## window gains or loses focus.

const WINDOW_MODE_NAMES: Array[String] = ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"]
const VSYNC_NAMES: Array[String] = ["Off", "On", "Adaptive", "Mailbox"]
## Frame rate limits (setting "fps_limit" is an index; 0 is unlimited).
const FPS_LIMITS: Array[int] = [0, 30, 60, 75, 90, 120, 144, 165, 240]
## Frame rate while the window is unfocused or minimised with "background_fps" on.
const BACKGROUND_FPS := 30
## 3D render resolution caps ("render_resolution" index): the 3D view renders at most this many
## lines (16:9 pixel count) at render scale 100 %; bigger windows upscale it. 0 is native.
const RENDER_HEIGHTS: Array[int] = [720, 900, 1080, 1440, 0]
const UPSCALER_NAMES: Array[String] = ["Auto", "Bilinear", "FSR 1", "FSR 2.2", "MetalFX Spatial", "MetalFX Temporal"]
## Dynamic resolution targets ("dynamic_resolution" index; 0 is off).
const DYNAMIC_TARGETS: Array[int] = [0, 60, 90, 120, 144]
const LEVEL_NAMES: Array[String] = ["Off", "Low", "Medium", "High", "Ultra"]
const ANISO_NAMES: Array[String] = ["Off", "2x", "4x", "8x", "16x"]
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]
## Settings each quality preset (QUALITY_NAMES) switches to when picked. Low also turns HiDPI
## off (from the next start): on a Retina or scaled display that quarters the pixels the GPU fills
## and upscales, which is what holds 60 fps there (A18 Pro, 2560 x 1440 display at 2x: Low with
## HiDPI 44 fps with MetalFX, 55-60 bilinear; without HiDPI 60, the display's refresh rate).
const PRESETS: Array[Dictionary] = [
	{"shadow_quality": 1, "ssao_quality": 0, "ssil": false, "bloom": false, "reflections": false, "anti_aliasing": 1, "anisotropic": 1, "render_resolution": 1, "hidpi": false},
	{"shadow_quality": 2, "ssao_quality": 2, "ssil": false, "bloom": true, "reflections": false, "anti_aliasing": 2, "anisotropic": 2, "render_resolution": 1, "hidpi": true},
	{"shadow_quality": 3, "ssao_quality": 3, "ssil": true, "bloom": true, "reflections": true, "anti_aliasing": 3, "anisotropic": 3, "render_resolution": 2, "hidpi": true},
	{"shadow_quality": 4, "ssao_quality": 4, "ssil": true, "bloom": true, "reflections": true, "anti_aliasing": 3, "anisotropic": 4, "render_resolution": 3, "hidpi": true},
]
## Windows with more pixels than this (2560 x 1600) get bilinear from the Auto upscaler: FSR 1 and
## MetalFX cost a full pass at the window's size, 7-10 ms at 5120 x 2880 on an A18 Pro.
const AUTO_BILINEAR_PIXELS := 2560 * 1600
## Sun shadows per "shadow_quality" level 1-4: [splits (2 or 4), max distance m, atlas size,
## soft filter quality, blend splits].
const SHADOW_LEVELS: Array = [
	[],
	[2, 45.0, 2048, RenderingServer.SHADOW_QUALITY_HARD, false],
	[2, 80.0, 4096, RenderingServer.SHADOW_QUALITY_SOFT_LOW, false],
	[4, 130.0, 8192, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, true],
	[4, 180.0, 8192, RenderingServer.SHADOW_QUALITY_SOFT_HIGH, true],
]
## Ambient occlusion per "ssao_quality" level 1-4: [RenderingServer SSAO quality, half size].
const SSAO_LEVELS: Array = [
	[],
	[RenderingServer.ENV_SSAO_QUALITY_LOW, true],
	[RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true],
	[RenderingServer.ENV_SSAO_QUALITY_HIGH, false],
	[RenderingServer.ENV_SSAO_QUALITY_ULTRA, false],
]
## The HiDPI choice lives in this file, which project.godot names as its
## `application/config/project_settings_override`, because Godot reads it before the window
## exists (so it takes a restart).
const DISPLAY_OVERRIDE := "user://display_override.cfg"

## Dynamic resolution: the share of the render scale in use (0.6-1) and its frame time average.
static var dynamic_factor := 1.0
static var _frame_ms := 0.0
static var _dyn_wait := 0.0
static var _applied := {}


## Applies every Video setting of `p` (Profile) to the window, `vp` and the built maps.
static func apply(p: Node, vp: Viewport) -> void:
	_apply_window(p)
	apply_fps(p)
	var aa := int(p.get_setting("anti_aliasing"))
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_DISABLED][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.anisotropic_filtering_level = int(p.get_setting("anisotropic")) as Viewport.AnisotropicFiltering
	vp.use_debanding = bool(p.get_setting("debanding"))
	apply_render_scale(p, vp)
	var shadow := int(p.get_setting("shadow_quality"))
	if shadow > 0:
		var level: Array = SHADOW_LEVELS[shadow]
		_once(&"shadow_atlas", level[2], func() -> void: RenderingServer.directional_shadow_atlas_set_size(level[2], true))
		_once(&"shadow_filter", level[3], func() -> void: RenderingServer.directional_soft_shadow_filter_set_quality(level[3]))
	var ssao := int(p.get_setting("ssao_quality"))
	if ssao > 0:
		var q: Array = SSAO_LEVELS[ssao]
		_once(&"ssao", ssao, func() -> void: RenderingServer.environment_set_ssao_quality(q[0], q[1], 0.5, 2, 50.0, 300.0))
	BlockAtlas.set_detail(bool(p.get_setting("block_detail")))
	MapBuilder.apply_graphics(p.get_tree())


## Runs `fn` only when `value` differs from the last one applied under `key`, so a slider drag
## elsewhere in Settings (every change re-applies everything) never reallocates the shadow atlas.
static func _once(key: StringName, value: Variant, fn: Callable) -> void:
	if _applied.get(key) == value:
		return
	_applied[key] = value
	fn.call()


static func _apply_window(p: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var screen := int(p.get_setting("screen")) - 1
	if screen >= 0 and screen < DisplayServer.get_screen_count() and DisplayServer.window_get_current_screen() != screen:
		DisplayServer.window_set_current_screen(screen)
	var want: DisplayServer.WindowMode = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][int(p.get_setting("window_mode"))]
	var mode := DisplayServer.window_get_mode()
	# Minimised or maximised windows count as windowed: only a real change switches the mode.
	var is_windowed := mode in [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_MINIMIZED, DisplayServer.WINDOW_MODE_MAXIMIZED]
	if want != mode and not (want == DisplayServer.WINDOW_MODE_WINDOWED and is_windowed):
		DisplayServer.window_set_mode(want)
	var vsync: DisplayServer.VSyncMode = [DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
		DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_MAILBOX][int(p.get_setting("vsync_mode"))]
	if DisplayServer.window_get_vsync_mode() != vsync:
		DisplayServer.window_set_vsync_mode(vsync)


## The frame rate limit, or BACKGROUND_FPS while the window is unfocused (setting
## "background_fps"), whichever is lower.
static func apply_fps(p: Node) -> void:
	var limit: int = FPS_LIMITS[int(p.get_setting("fps_limit"))]
	if not p.window_focused and bool(p.get_setting("background_fps")):
		limit = BACKGROUND_FPS if limit == 0 else mini(limit, BACKGROUND_FPS)
	Engine.max_fps = limit


## The share of the window the 3D view renders at: the render scale setting times the render
## resolution cap's share of the window (RENDER_HEIGHTS, as a 16:9 pixel count) times the dynamic
## resolution factor; below native it is upscaled by the chosen upscaler.
static func render_scale(p: Node) -> float:
	var win := Vector2(DisplayServer.window_get_size())
	var cap: int = RENDER_HEIGHTS[int(p.get_setting("render_resolution"))]
	var budget := 1.0
	if cap > 0 and win.x * win.y > 0.0:
		budget = minf(1.0, sqrt(cap * cap * 16.0 / 9.0 / (win.x * win.y)))
	return float(p.get_setting("render_scale")) * budget * dynamic_factor


static func apply_render_scale(p: Node, vp: Viewport) -> void:
	var s := render_scale(p)
	var sharp := float(p.get_setting("sharpness"))
	var mode := upscaler_mode(int(p.get_setting("upscaler")), s, sharp)
	# FSR 1 at 99 % is how Godot sharpens a native image (its RCAS pass needs the upscale pass).
	if s >= 0.99 and mode == Viewport.SCALING_3D_MODE_FSR:
		s = 0.99
	vp.scaling_3d_mode = mode
	vp.scaling_3d_scale = minf(s, 1.0)
	# 0 is FSR's sharpest, 2 its softest.
	vp.fsr_sharpness = 2.0 * (1.0 - sharp)
	var temporal := mode in [Viewport.SCALING_3D_MODE_FSR2, Viewport.SCALING_3D_MODE_METALFX_TEMPORAL]
	# The temporal upscalers anti-alias by themselves; TAA on top of them only blurs.
	vp.use_taa = int(p.get_setting("anti_aliasing")) == 4 and not temporal


## The Viewport scaling mode for "upscaler" index `choice` at 3D scale `s`. Auto: at native,
## FSR 1 (as a sharpener) when sharpening is on, else nothing; below native, bilinear in windows
## over AUTO_BILINEAR_PIXELS, else MetalFX Spatial on Apple's Metal (a little cheaper than FSR 1
## there) and FSR 1 elsewhere. MetalFX off Metal falls back to FSR 1 / FSR 2.2.
static func upscaler_mode(choice: int, s: float, sharp: float) -> Viewport.Scaling3DMode:
	var metal := RenderingServer.get_current_rendering_driver_name() == "metal"
	match choice:
		1: return Viewport.SCALING_3D_MODE_BILINEAR
		2: return Viewport.SCALING_3D_MODE_FSR
		3: return Viewport.SCALING_3D_MODE_FSR2
		4: return Viewport.SCALING_3D_MODE_METALFX_SPATIAL if metal else Viewport.SCALING_3D_MODE_FSR
		5: return Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if metal else Viewport.SCALING_3D_MODE_FSR2
	if s >= 0.99:
		return Viewport.SCALING_3D_MODE_FSR if sharp > 0.01 else Viewport.SCALING_3D_MODE_BILINEAR
	var win := DisplayServer.window_get_size()
	if win.x * win.y > AUTO_BILINEAR_PIXELS:
		return Viewport.SCALING_3D_MODE_BILINEAR
	return Viewport.SCALING_3D_MODE_METALFX_SPATIAL if metal else Viewport.SCALING_3D_MODE_FSR


## Dynamic resolution, every frame: with a target ("dynamic_resolution"), the 3D render scale
## drops 5 % at a time (down to 60 % of the set scale) while the average frame takes longer than
## the target allows, and climbs back while frames have clear headroom. Only in a 3D scene with
## the window focused; a frame rate limit below the target lowers the target to it.
static func tick(p: Node, vp: Viewport, delta: float) -> void:
	var target: int = DYNAMIC_TARGETS[int(p.get_setting("dynamic_resolution"))]
	var limit: int = FPS_LIMITS[int(p.get_setting("fps_limit"))]
	if limit > 0 and target > 0:
		target = mini(target, limit)
	if target == 0 or not p.window_focused or vp.get_camera_3d() == null or p.get_tree().paused:
		if dynamic_factor != 1.0 and target == 0:
			dynamic_factor = 1.0
			apply_render_scale(p, vp)
		_frame_ms = 0.0
		return
	var ms := delta * 1000.0
	_frame_ms = ms if _frame_ms == 0.0 else lerpf(_frame_ms, ms, 0.1)
	_dyn_wait -= delta
	if _dyn_wait > 0.0:
		return
	_dyn_wait = 0.5
	var budget_ms := 1000.0 / target
	var f := dynamic_factor
	if _frame_ms > budget_ms * 1.04:
		f = maxf(0.6, f - 0.05)
	elif _frame_ms < budget_ms * 0.8:
		f = minf(1.0, f + 0.05)
	if f != dynamic_factor:
		dynamic_factor = f
		apply_render_scale(p, vp)


## Writes the HiDPI choice for the next start (see DISPLAY_OVERRIDE). Off renders the window at
## its size in points: on a Retina or scaled display a quarter of the pixels, so the HUD costs
## far less GPU time but looks softer.
static func save_hidpi(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "window/dpi/allow_hidpi", on)
	cfg.save(DISPLAY_OVERRIDE)


## Names for the "screen" option: the current screen, then each connected one.
static func screen_names() -> Array[String]:
	var out: Array[String] = ["Current screen"]
	for i in DisplayServer.get_screen_count():
		var s := DisplayServer.screen_get_size(i)
		out.append("Screen %d (%d x %d)" % [i + 1, s.x, s.y])
	return out
