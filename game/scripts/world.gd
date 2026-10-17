extends Control
## Composes the look: owns the shared layout (horizon, sun), advances time and travel, frames the
## 3D wave with the camera, stands the stand-in surfer on its surface, and feeds the current mood
## to every layer. Layers are the child nodes, drawn back to front.

## How fast the 2D scenery slides, in screen heights per second. The surfer travels right to left,
## so the world slides left to right.
const TRAVEL_SPEED := 0.16
const HORIZON := 0.40
const SUN_X_FRACTION := 0.40
const SUN_Y := 0.20
## The 2D backdrop is composed for at least this width (in screen heights). On a narrower screen
## the middle of it is shown and the sides are cropped. (The 3D wave crops through its camera.)
const MIN_LAYOUT_ASPECT := 1.5

## How quickly the camera follows the surfer, per second. A little lag is what lets you see them climb the face.
const CAMERA_FOLLOW_RATE := 3.5
## The water, and with it the scenery, slides past this much faster or slower with the surfer's speed.
const TRAVEL_SPEED_SLOW := 0.55
const TRAVEL_SPEED_FAST := 1.45
## The camera always looks down the line, left from behind the surfer, so the wave coming toward them
## fills the screen and the break stays at their back. It eases a little less far round as a barrel forms.
## Degrees, and the surfer's place across the screen. (Step 12 swung it 12 degrees further round, more behind his head:
## the view shows more of his back and of the wall running away down the line, less of the shoulder.)
const CAMERA_YAW_OPEN := 42.0
const CAMERA_YAW_BARREL := 36.0
const SURFER_SCREEN_X_OPEN := 0.47
const SURFER_SCREEN_X_BARREL := 0.50
const CAMERA_SWING_RATE := 2.5
## Temporary controls for trying waves: how fast the held keys change things, per second.
const SIZE_RATE := 0.4
const HOLLOW_RATE := 0.4
const DEFAULT_SIZE := 0.6
const DEFAULT_HOLLOW := 0.5
const DEFAULT_PEEL_OFFSET := 3.0
const DEFAULT_POSE := "surfer"
## The surfer sits on the face at an angle that follows the wave, but never tips past this, in degrees.
const MAX_GROUND_ANGLE := 14.0
## Where the board's tail is, in meters from the board's centre (right and down, before the board tilts):
## the spray is thrown from here.
const BOARD_TAIL := Vector2(0.8, 0.05)
## The water slides past the surfer this much faster than the far scenery, which is what carries the wake.
const WAKE_DRIFT_FACTOR := 1.7
## The temporary B key throws a burst of the next strength in this list, so they can be judged one by one.
const TEST_BURSTS: Array[float] = [0.15, 0.4, 0.7, 1.0]
## With ?autoburst in the URL (for a phone, which has no S key) a test burst is thrown this often, in seconds.
const AUTO_BURST_EVERY := 2.4
## The , and . keys slow everything down or speed it up (the ride, the wave, the spray), in these steps and limits.
const GAME_SPEED_STEP := 0.1
const GAME_SPEED_MIN := 0.5
const GAME_SPEED_MAX := 2.5
## At the top of the wave (above this height up the face) a turn also throws a fan off the front of the board, where
## the front foot drives the rail through the lip, this strong relative to the tail's.
const FRONT_SPRAY_FROM := 0.6
const FRONT_SPRAY_SHARE := 1.1
## The spray leaves the tail the way the rider throws it (off the outside of the turn, up over the crest at the lip): the
## direction is projected this many meters out to find its angle on screen, which stays between these angles (degrees,
## 0 is right, negative is up), so it never fires down into the face.
const SPRAY_PROBE := 1.5
const SPRAY_ANGLE_UP := -165.0
const SPRAY_ANGLE_DOWN := 20.0
## The hotkeys that play a move (MovePlayer), and how hollow the wave is made for the tube if it cannot barrel yet.
const MOVE_KEYS := {KEY_L: "lip_hit", KEY_C: "cutback", KEY_F: "floater", KEY_T: "tube", KEY_P: "pump"}
const TAKE_OVER_MOTION := 3.0       # pixels the mouse must move to take the controls back from a move being played

## The reef and the tide. The curl is baked into the mesh, so it follows the reef section at the peel point (sampled
## REEF_SAMPLE_D ahead of it) and the tide in reshapes, whenever one of them has moved more than RESHAPE_STEP.
const REEF_SAMPLE_D := 0.5
const RESHAPE_STEP := 0.03
## The test hotkeys put a section this far ahead of the rider, and the barrel hotkey a bowl this far ahead of the peel
## point, so it is pitching by the time the move has taken him back into the pocket.
const BARREL_NOW_AT := 6.0

## The camera moves a little through the ride, for depth. Out on the shoulder (from SHOULDER_LOOK_FROM to
## SHOULDER_LOOK_FULL meters ahead) it swings round to the right, more behind his head, so more of what is coming down the
## line shows (and he sits a little right of centre); a racecourse or a bowl coming does the same a little. In the tube
## it tucks in (yaw, lens and distance) so the almond mouth frames him. A slow sway keeps it alive. Degrees and meters.
const CAMERA_YAW_SHOULDER := 10.0
const SHOULDER_LOOK_FROM := 4.0
const SHOULDER_LOOK_FULL := 12.0
const SURFER_SCREEN_X_SHOULDER := 0.06
const CAMERA_YAW_SECTION := 8.0
const SECTION_LOOK_AHEAD := 10.0
const CAMERA_LOOK_RATE := 1.2
const CAMERA_YAW_TUBE := 22.0
const CAMERA_FOV_TUBE := 19.5
const CAMERA_DISTANCE_TUBE := 17.5
const CAMERA_SWAY := Vector2(1.4, 0.7)
const CAMERA_SWAY_RATES := Vector2(0.13, 0.31)
## Like a camera operator following his line: turned round toward the curl in a cutback, the camera pans back with him
## by up to this much (degrees), easing in and out at CAMERA_LOOK_RATE.
const CAMERA_HEADING_PAN := 8.0
## The real-time surfer is backlit, as in the key frames (kling-04 and kling-05): the low sun is over the sea in front of
## the camera, so his back is in shade and the light catches his shoulders, the top of his head and the edges of his
## arms. The light comes from straight ahead of the camera (KEY_AHEAD), a little to the sun's side (KEY_SIDE per screen
## of the sun's offset), and from above by KEY_UP_HORIZON with the sun on the horizon, more as it stands higher
## (KEY_UP_GAIN per screen height above it), between KEY_UP_LOW and KEY_UP_HIGH.
const KEY_AHEAD := 0.75
const KEY_SIDE := 1.5
const KEY_UP_HORIZON := 0.22
const KEY_UP_GAIN := 1.2
const KEY_UP_LOW := 0.12
const KEY_UP_HIGH := 0.5
## The camera test keys turn it in steps of CAMERA_STEP degrees, at most CAMERA_OFFSET_MAX either way.
const CAMERA_STEP := 10.0
const CAMERA_OFFSET_MAX := 90.0

## The green room. In the tube (more than TUBE_IN of it, between TUBE_D meters of the peel point and below TUBE_U up the
## face) the camera tucks in over TUCK_TIME, and deep in it (past DILATION_DEPTH) time slows to DILATION and the sound
## hushes. Held there SLINGSHOT_AFTER seconds, driving out toward the mouth (past SLINGSHOT_D) as the lip lands, the
## barrel spits him out: a dense cloud past him and SLINGSHOT_BOOST m/s of speed.
const TUBE_IN := 0.45
const TUBE_D := Vector2(-3.5, 1.5)
const TUBE_U := 0.5
const TUCK_TIME := 0.4
const DILATION_DEPTH := 0.6
const DILATION := 0.88
const DILATION_TIME := 0.4
const SLINGSHOT_AFTER := 0.9
const SLINGSHOT_D := -1.2
const SLINGSHOT_BOOST := 1.6
const TUBE_FORGET := 0.4            # seconds out of the tube before the time in it is forgotten
const SPIT_ANGLE := -170.0          # degrees on screen: out of the mouth, down the line (left) and a little up

## The soft wipeout: he drifts back with the foam at DRIFT_BACK of the peel speed, curled up (the tumble pose) and turning
## over TUMBLE_TURNS times (a whole number, so he comes up the right way), sinking TUMBLE_SINK meters; then sits astride
## the board (the sit pose), the board SIT_SINK down in the water, through the lull until the next swell stands him up.
const DRIFT_BACK := 0.6
const TUMBLE_TURNS := 1.0
const TUMBLE_SINK := 0.9
const SIT_SINK := 0.06

var _time := 0.0
var _travel := 0.0
var _crop := 0.0   # screen heights hidden on each side when the screen is narrower than the layout
## The surfer's motion on the wave, driven by the input.
var rider := Rider.new()
## How far ahead of the peel point the surfer is, in meters. Positive is ahead (to the left),
## negative is behind it, where the lip throws and the barrel is.
var peel_offset: float:
	get:
		return rider.d
var _swing := 0.0   # 0 on an open wave, 1 on a full barrel
var _first_frame := true
var _focus := Vector3.ZERO
var _ride_input := RideInput.new()
var _moves := MovePlayer.new()      # plays a move through the controls when its hotkey is pressed
var _tuning: TuningData = preload("res://data/tuning.tres")
var _calibration: Calibration
var _key_help := Label.new()
var _surfer3d: Surfer3D
var _readout := Label.new()
var _speed_label := Label.new()  # the game speed, always on screen so it shows in screenshots
var _front_spray := SurferSpray.new()
var _pose_index := SurferSprites.ORDER.find(DEFAULT_POSE)
var _test_burst := 0
var _auto_burst_in := AUTO_BURST_EVERY
var _auto_burst := false

## The reef under the wave, the evening going on, and the rhythm of ride, wipeout and lull.
var reef := SectionDirector.new()
var solar := SolarClock.new()
var cycle := RideCycle.new()
var music := MusicLayers.new()
var _overlay := TestOverlay.new()
var _game_speed := 1.0              # the , and . keys; the tube's dilation multiplies it
var _dilation := 1.0
var _tuck := 0.0                    # 0 open, 1 tucked in for the tube
var _look := 0.0                    # degrees the camera has swung round to look down the line
## Testing the camera (step 12): degrees added to the camera's swing by the overlay's camera keys, to find the angle.
var camera_offset := 0.0
var _shoulder_x := 0.0
var _heading_pan := 0.0                # degrees the camera has panned back with him as he turns toward the curl
var _tube_time := 0.0
var _out_of_tube := 0.0
var _slung := false
var _size_offset := 0.0             # the - = and [ ] keys (and set_wave) move the wave from what the tide gives
var _hollow_offset := 0.0
var _mood_from_clock := true        # the evening sets the look, unless a mood was asked for
var _last_blend: Array = []
var _sun_y := SUN_Y
var _audio_started := false

var _ridges: Array[RidgeLayer] = []
## Each shader material with the mood properties it declares as uniforms.
var _mood_uniforms: Array[Dictionary] = []
var _materials: Array[ShaderMaterial] = []

@onready var _stage: WaveStage = $WaveStage
@onready var _surfer: Surfer = $Surfer
@onready var _spray: SurferSpray = $Spray
@onready var _wave_spray: WaveSpray = $WaveSpray
@onready var _panel: DebugPanel = $DebugPanel


func _init() -> void:
	# Attached now, not in _ready, so a scene that is never started cannot orphan them.
	add_child(_ride_input)
	add_child(music)


func _notification(what: int) -> void:
	# The labels and the second fan are attached in _ready; a scene freed before that must free them itself.
	if what == NOTIFICATION_PREDELETE:
		for orphan: Node in [_key_help, _readout, _speed_label, _front_spray, _overlay]:
			if is_instance_valid(orphan) and orphan.get_parent() == null:
				orphan.free()


func _ready() -> void:
	_add_key_help()
	# The second fan, off the front foot, sits with the tail's fan in front of the surfer.
	add_child(_front_spray)
	move_child(_front_spray, _spray.get_index() + 1)
	_front_spray.set_wake(0.0)
	var url_speed := UrlParams.get_value("speed")
	if url_speed.is_valid_float():
		_game_speed = clampf(url_speed.to_float(), GAME_SPEED_MIN, GAME_SPEED_MAX)
	Engine.time_scale = _game_speed
	_stage.model.reef = reef
	reef.enabled = UrlParams.get_value("reef") != "off"
	var url_solar := UrlParams.get_value("solar")
	if url_solar.is_valid_float():
		solar.time = url_solar.to_float()
	solar.running = UrlParams.get_value("clock") != "off"
	_mood_from_clock = not UrlParams.has("mood")
	_add_overlay()
	_show_game_speed()
	_set_surfer_3d(not UrlParams.has("sprite"))  # the real-time surfer is the default; ?sprite or the 3 key brings the sprite back
	for child in get_children():
		if child is RidgeLayer:
			child.build(HORIZON)
			_ridges.append(child)
		elif child is CanvasItem and child.material is ShaderMaterial:
			_register(child.material)
	for material in _stage.materials():
		_register(material)
	_register(_surfer.toon_material)
	_stage.carve_trail.draw_speed = _tuning.v_draw_base
	_auto_burst = UrlParams.has("autoburst")
	if UrlParams.has("calibrate"):
		_calibration = Calibration.new()
		add_child(_calibration)
		_calibration.start(_ride_input, rider)
	_panel.values_changed.connect(_on_panel_changed)
	resized.connect(_on_resized)
	Palette.changed.connect(_apply_mood)
	_feed_evening()
	_on_resized()
	_apply_mood()
	var tide := solar.tide()
	set_wave(_url_number("size", tide.x), _url_number("hollow", tide.y), _url_number("peel", DEFAULT_PEEL_OFFSET))
	var requested_pose := UrlParams.get_value("pose")
	set_surfer_pose(requested_pose if SurferSprites.has_animation(requested_pose) else DEFAULT_POSE)


func _process(delta: float) -> void:
	_time += delta
	_ride_input.process(delta)
	_read_held_keys(delta)
	var model := _stage.model
	var lip_phase := WaveStage.lip_phase_at(rider.d, _time)
	var lip_landing := lip_phase >= WaveStage.LIP_LANDING_PHASE and lip_phase < 0.92
	match cycle.update(delta, rider, model, lip_landing):
		"wipeout":
			_on_wipeout()
		"lull":
			_on_lull()
		"ride":
			_place_rider(DEFAULT_PEEL_OFFSET)
	model.swell = cycle.swell
	if cycle.riding():
		_moves.update(delta, rider, _ride_input)
		rider.step(delta, _ride_input.steer, _ride_input.take_height_push(), model, _tuning)
		solar.advance(delta, rider.flow)
	else:
		_drift_while_down(delta)
		_ride_input.take_height_push()
	reef.maturity = solar.maturity()
	reef.update(delta, model.peel_speed())
	_follow_tide_and_reef()
	_feed_evening()
	_update_tube(delta)
	music.set_flow(rider.flow if cycle.riding() else 0.0)
	music.set_lull(not cycle.riding())
	_spray.set_flow(rider.flow)
	_front_spray.set_flow(rider.flow)
	Engine.time_scale = _game_speed * _dilation
	_show_game_speed()
	if _overlay.visible:
		_overlay.set_status(_status_text())
	if _readout.visible:
		_readout.text = "%s   speed %.1f m/s   heading %d deg   turn %.1f   crouch %.2f   lean %d deg   load %.1f g   stall %.1f
charge %.1f   release %.1f   float %.1f   spray %.2f   %s" % [
			rider.move, rider.v, roundi(rad_to_deg(rider.theta)), rider.omega, rider.compression, roundi(rad_to_deg(rider.carve)), rider.load_g,
			rider.stall, rider.charge, rider.release, rider.afloat, rider.spray_power, _balance_note()]
		_readout.modulate = Color(1.0, 0.55, 0.5, 0.9) if rider.strain > 1.0 else Color(1, 1, 1, 0.6)
	var strength := rider.take_burst()
	if strength > 0.0:
		burst(strength, rider.burst_release)
		music.splash(strength * 0.6)
	_spray.set_wake(lerpf(0.2, 1.0, rider.speed) if cycle.riding() else 0.0)
	_travel += TRAVEL_SPEED * lerpf(TRAVEL_SPEED_SLOW, TRAVEL_SPEED_FAST, rider.speed) * delta
	for material in _materials:
		material.set_shader_parameter("time", _time)
		material.set_shader_parameter("travel", _travel)
	for ridge in _ridges:
		ridge.place(_travel, size.y, _crop)
	_place_surfer_and_spray()
	_wave_spray.update(_stage, _time)
	if cycle.riding():
		_stage.carve_trail.carve(delta, rider.d, rider.u, rider.theta, rider.spray_power, _time)
	if _auto_burst:
		_auto_burst_in -= delta
		if _auto_burst_in <= 0.0:
			_auto_burst_in = AUTO_BURST_EVERY
			_throw_test_burst()


## Browsers only let sound start after the player touches the page, so the first press anywhere starts it.
func _input(event: InputEvent) -> void:
	if not _audio_started and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch) and event.is_pressed():
		_audio_started = true
		music.start()


func _unhandled_input(event: InputEvent) -> void:
	_ride_input.handle(event, size)
	if _moves.playing() and _takes_over(event):
		_moves.stop()
	if event is InputEventKey and event.pressed and not event.echo and MOVE_KEYS.has(event.keycode):
		play_move(MOVE_KEYS[event.keycode])
	elif event is InputEventKey and _overlay.handle_key(event):
		pass
	elif event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_M:
			_next_look()
		elif event.pressed and not event.echo and event.keycode == KEY_R:
			_size_offset = 0.0
			_hollow_offset = 0.0
			var tide := solar.tide()
			set_wave(tide.x, tide.y, DEFAULT_PEEL_OFFSET)
			_ride_input.reset()
		elif event.pressed and not event.echo and event.keycode == KEY_O:
			set_surfer_pose(SurferSprites.ORDER[(_pose_index + 1) % SurferSprites.ORDER.size()])
		elif event.pressed and not event.echo and event.keycode == KEY_B:
			_throw_test_burst()
		elif event.pressed and not event.echo and event.keycode == KEY_1:
			if _surfer3d:
				_surfer3d.set_target("bottom_turn", 1.0 - _surfer3d.target("bottom_turn"))
			else:
				_surfer.play_once("bottom_turn")
		elif event.pressed and not event.echo and event.keycode == KEY_2 and _surfer3d:
			_surfer3d.set_target("crouch", 1.0 - _surfer3d.target("crouch"))
		elif event.pressed and not event.echo and event.keycode == KEY_3:
			_set_surfer_3d(_surfer3d == null)
		elif event.pressed and not event.echo and event.keycode == KEY_H:
			_key_help.visible = not _key_help.visible
			_readout.visible = _key_help.visible
			_overlay.visible = _key_help.visible
		elif event.pressed and (event.keycode == KEY_COMMA or event.keycode == KEY_PERIOD):
			var step := GAME_SPEED_STEP if event.keycode == KEY_PERIOD else -GAME_SPEED_STEP
			_game_speed = clampf(snappedf(_game_speed + step, GAME_SPEED_STEP), GAME_SPEED_MIN, GAME_SPEED_MAX)
			Engine.time_scale = _game_speed * _dilation
			_show_game_speed()
	# A double click or double tap moves the evening on (touches arrive as emulated mouse clicks).
	elif event is InputEventMouseButton:
		if event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			_next_look()


## Plays a move through the controls (MovePlayer.MOVES): the hotkeys L, C, F, T and P. The tube needs a wave that
## barrels, so if this one cannot a reef bowl is sent in to make it pitch.
func play_move(move_name: String) -> void:
	if move_name == "tube" and _stage.model.barrel() < WaveModel.BARREL_THRESHOLD + 0.1:
		reef.force(SectionDirector.Kind.REEF_BOWL, BARREL_NOW_AT)
		_follow_tide_and_reef()
	_moves.play(move_name)
	_show_game_speed()


## The M key and a double click: the next part of the evening (or the next mood, if one was asked for in the URL).
func _next_look() -> void:
	if _mood_from_clock:
		solar.next_phase()
	else:
		Palette.cycle()


## Testing: sends a reef section of `kind` in from down the line, a few seconds away.
func send_section(kind: SectionDirector.Kind) -> void:
	reef.force(kind, maxf(rider.d, 0.0) + SectionDirector.FORCE_AHEAD)


## Testing: a barrel now. A bowl comes in at the peel point and the barrel crouch takes him back into the pocket.
func barrel_now() -> void:
	if not cycle.riding():
		return
	reef.force(SectionDirector.Kind.REEF_BOWL, BARREL_NOW_AT)
	_follow_tide_and_reef()
	_moves.play("tube")


## Testing: a soft wipeout now.
func wipeout_now() -> void:
	if cycle.riding():
		cycle.wipeout()
		_on_wipeout()


## Testing: a lull now.
func lull_now() -> void:
	if cycle.state != RideCycle.State.LULL:
		cycle.lull()
		_on_lull()


## Testing: the reef's sections stop coming (or start again).
func toggle_reef() -> void:
	reef.enabled = not reef.enabled


## Testing: holds the evening where it is (or lets it run on).
func toggle_evening() -> void:
	solar.running = not solar.running


func toggle_sound() -> void:
	music.set_muted(not music.is_muted())


## Testing: jumps the evening to phase `index` (SolarClock.PHASE_NAMES), handing the look back to the clock.
func evening_phase(index: int) -> void:
	_mood_from_clock = true
	_last_blend = []
	solar.jump_to_phase(index)


## The wave follows the tide (and the - = [ ] keys) and the reef at the peel point: the live parts of the reef go straight
## to the shaders; the curl is rebuilt over a few frames whenever the shape has moved more than RESHAPE_STEP.
func _follow_tide_and_reef() -> void:
	var model := _stage.model
	var tide := solar.tide()
	model.peel_mult = tide.z * reef.peel_mult_at(REEF_SAMPLE_D)
	if _stage.reshaping():
		return
	var wave_size := clampf(tide.x + _size_offset, 0.0, 1.0)
	var hollowness := clampf(tide.y + _hollow_offset, 0.0, 1.0)
	var reef_size := reef.size_delta_at(REEF_SAMPLE_D)
	var reef_hollow := reef.hollow_delta_at(REEF_SAMPLE_D)
	var moved := maxf(maxf(absf(wave_size - model.size), absf(hollowness - model.hollowness)),
			maxf(absf(reef_size - model.reef_size), absf(reef_hollow - model.reef_hollow)))
	if moved > RESHAPE_STEP:
		model.size = wave_size
		model.hollowness = hollowness
		model.reef_size = reef_size
		model.reef_hollow = reef_hollow
		_stage.reshape()


## The evening sets the look (blending the moods) and where the sun is.
func _feed_evening() -> void:
	if _mood_from_clock:
		var blend := solar.mood_blend()
		if _last_blend.is_empty() or blend[0] != _last_blend[0] or blend[1] != _last_blend[1] or absf(blend[2] - _last_blend[2]) > 0.003:
			_last_blend = blend
			Palette.blend(blend[0], blend[1], blend[2])
	var sun_y := solar.sun_height()
	if absf(sun_y - _sun_y) > 0.0005:
		_sun_y = sun_y
		_place_sun()


## The green room: tucking the camera in, slowing time, hushing the sound, and the spit out of the barrel.
func _update_tube(delta: float) -> void:
	var model := _stage.model
	var depth := model.barrel_amount_at(rider.d, rider.u) if cycle.riding() else 0.0
	var in_tube := depth > TUBE_IN and rider.d > TUBE_D.x and rider.d < TUBE_D.y and rider.u < TUBE_U
	_tuck = lerpf(_tuck, 1.0 if in_tube else 0.0, 1.0 - exp(-delta / TUCK_TIME))
	if in_tube:
		_tube_time += delta
		_out_of_tube = 0.0
	else:
		_out_of_tube += delta
		if _out_of_tube > TUBE_FORGET:
			_tube_time = 0.0
			_slung = false
	var deep := in_tube and depth > DILATION_DEPTH and not _slung
	_dilation = lerpf(_dilation, DILATION if deep else 1.0, 1.0 - exp(-delta / DILATION_TIME))
	music.set_hush(depth if in_tube and not _slung else 0.0)
	# The barrel hotkey's crouch ends once the bowl has gone by, so he drives out instead of staying under the foam.
	if _moves.playing() and _moves.move == "tube" and model.barrel() < WaveModel.BARREL_THRESHOLD and reef.weight_of(SectionDirector.Kind.REEF_BOWL, REEF_SAMPLE_D) < 0.3:
		_moves.stop()
		_place_rider_steer(DEFAULT_PEEL_OFFSET)
	var phase := WaveStage.lip_phase_at(rider.d, _time)
	if not _slung and _tube_time >= SLINGSHOT_AFTER and rider.d > SLINGSHOT_D and rider.vel_d > 0.0 and phase >= WaveStage.LIP_LANDING_PHASE:
		spit_out()


## The barrel spits him out onto the open face: a dense cloud past him, a shove of speed, and time and sound snap back.
func spit_out() -> void:
	_slung = true
	_dilation = 1.0
	var model := _stage.model
	var mouth := model.surface_point(rider.d + 0.5, 0.35)
	var at := _stage.project(mouth)
	var pixels_per_meter := at.distance_to(_stage.project(mouth + Vector3.UP))
	_wave_spray.blast(at, pixels_per_meter, SPIT_ANGLE)
	rider.boost(SLINGSHOT_BOOST)
	music.splash(0.8)


func _on_wipeout() -> void:
	_moves.stop()
	_spray.splash(1.0)
	music.splash(1.0)
	solar.step_back()
	rider.flow *= 0.6
	_tube_time = 0.0


## The lull: the sea goes glassy and he sits up in the water waiting, back in the lineup, while the reef starts afresh.
func _on_lull() -> void:
	_moves.stop()
	reef.sections.clear()
	_place_rider(DEFAULT_PEEL_OFFSET)
	_ride_input.reset()


## Down in the water (tumbling, or waiting in a lull) the rider is not ridden: he drifts back with the foam.
func _drift_while_down(delta: float) -> void:
	if cycle.state == RideCycle.State.WIPEOUT:
		rider.d -= DRIFT_BACK * _stage.model.peel_speed() * delta
		rider.u = lerpf(rider.u, 0.1, 1.0 - exp(-delta / 0.6))
	rider.v = 0.0
	rider.speed = 0.0
	rider.omega = 0.0


## Testing: one line on what the reef, the evening, the flow and the tube are doing.
func _status_text() -> String:
	var here: String = SectionDirector.NAMES[reef.kind_at(rider.d)]
	var next := reef.next_ahead(rider.d + 0.5)
	var coming := "%s in %d m" % [SectionDirector.NAMES[next.kind], roundi(next.d_center - next.half_width - rider.d)] if next != null and next.d_center - next.half_width > rider.d else "nothing coming"
	var tide := solar.tide()
	return "%s %.2f%s   tide: size %.2f, hollow %.2f, peel x%.2f\nreef here: %s, next: %s\nflow %.2f   tube %.2f   time x%.2f   %s" % [
		solar.phase_name(), solar.time, "" if solar.running else " (held)", tide.x, tide.y, _stage.model.peel_mult,
		here, coming, rider.flow, _tuck, _dilation, RideCycle.State.keys()[cycle.state].to_lower()] + "
camera %+d degrees (9 0 turn it, I resets)" % roundi(camera_offset)


## Turns the camera round by `degrees` from where it is (0 puts it back to the default), to try angles (step 12).
func turn_camera(degrees: float) -> void:
	camera_offset = 0.0 if degrees == 0.0 else clampf(camera_offset + degrees, -CAMERA_OFFSET_MAX, CAMERA_OFFSET_MAX)


## The test hotkeys and their buttons down the right of the screen.
func _add_overlay() -> void:
	_overlay.add_group("reef sections (arrive in about 3 s)")
	_overlay.add_action(KEY_4, "cruiser wall", send_section.bind(SectionDirector.Kind.CRUISER_WALL))
	_overlay.add_action(KEY_5, "deep channel", send_section.bind(SectionDirector.Kind.DEEP_CHANNEL))
	_overlay.add_action(KEY_6, "racecourse", send_section.bind(SectionDirector.Kind.RACECOURSE))
	_overlay.add_action(KEY_7, "reef bowl", send_section.bind(SectionDirector.Kind.REEF_BOWL))
	_overlay.add_action(KEY_8, "reef sections on / off", toggle_reef)
	_overlay.add_group("events")
	_overlay.add_action(KEY_G, "barrel now", barrel_now)
	_overlay.add_action(KEY_K, "wipeout", wipeout_now)
	_overlay.add_action(KEY_Y, "lull", lull_now)
	_overlay.add_group("evening")
	_overlay.add_action(KEY_Z, "high golden", evening_phase.bind(0))
	_overlay.add_action(KEY_X, "80s sunset", evening_phase.bind(1))
	_overlay.add_action(KEY_V, "electric dusk", evening_phase.bind(2))
	_overlay.add_action(KEY_N, "bioluminescent night", evening_phase.bind(3))
	_overlay.add_action(KEY_U, "hold / run the evening", toggle_evening)
	_overlay.add_action(KEY_Q, "sound on / off", toggle_sound)
	_overlay.add_group("camera")
	_overlay.add_action(KEY_9, "turn camera left", turn_camera.bind(-CAMERA_STEP))
	_overlay.add_action(KEY_0, "turn camera right", turn_camera.bind(CAMERA_STEP))
	_overlay.add_action(KEY_I, "camera back to default", turn_camera.bind(0.0))
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_overlay.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_overlay.offset_left = -14.0
	_overlay.offset_right = -14.0
	_overlay.offset_top = 36.0
	add_child(_overlay)


## Whether an input event is the player taking the controls back from a move being played.
func _takes_over(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		return event.relative.length() > TAKE_OVER_MOTION
	if event is InputEventKey:
		return event.pressed and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D]
	return event is InputEventMouseButton or event is InputEventPanGesture or event is InputEventScreenDrag or event is InputEventScreenTouch


## Debug: whether the input is one a real surfer could ride. He never falls here, but the readout says when he would.
func _balance_note() -> String:
	var note := "balance ok" if rider.strain <= 1.0 else "a real surfer would fall: " + rider.strain_reason
	return "%s   (strain %.1f, %d times so far)" % [note, rider.strain, rider.falls]


## Sets the wave's size and hollowness (both 0 to 1) and how far ahead of the peel point, in
## meters, the surfer is.
## The tide keeps moving the wave through the evening; this sets how far from the tide's wave it is.
func set_wave(wave_size: float, hollowness: float, ahead_of_peel: float) -> void:
	var tide := solar.tide()
	_size_offset = wave_size - tide.x
	_hollow_offset = hollowness - tide.y
	_stage.model.size = wave_size
	_stage.model.hollowness = hollowness
	_stage.model.reef_size = reef.size_delta_at(REEF_SAMPLE_D)
	_stage.model.reef_hollow = reef.hollow_delta_at(REEF_SAMPLE_D)
	_place_rider(clampf(ahead_of_peel, DebugPanel.PEEL_MIN, DebugPanel.PEEL_MAX))
	_stage.rebuild()
	_first_frame = true
	_panel.show_values(wave_size, hollowness, peel_offset)


## Points the steering at a place along the wave without moving him: he rides there.
func _place_rider_steer(meters_ahead: float) -> void:
	_ride_input.steer = Rider.steer_for(meters_ahead)


## Puts the surfer at a place along the wave (and mid face) and points the input at it, so they stay there.
func _place_rider(meters_ahead: float) -> void:
	_ride_input.steer = Rider.steer_for(meters_ahead)
	_ride_input.height = RideInput.REST_HEIGHT
	rider.place(meters_ahead, Rider.u_for(RideInput.REST_HEIGHT))
	_stage.carve_trail.clear()


## Throws spray off the board's tail, strength 0 (a flick) to 1 (the full fan). The rider calls this from the riding;
## `giant` (0 to 1) is how much of it is the speed he sheds stopping at the top, which throws the giant fan.
func burst(strength: float, giant := 0.0) -> void:
	var tail := _surfer3d.tail_point() if _surfer3d else Vector3.ZERO
	_spray.burst(strength, _spray_angle(tail), giant)
	# At the top of the wave the front foot drives the rail through the lip and throws its own, bigger fan.
	var top := smoothstep(FRONT_SPRAY_FROM, 0.85, rider.u)
	if top > 0.05:
		var front := _surfer3d.front_foot_point() if _surfer3d else Vector3.ZERO
		_front_spray.burst(clampf(strength * FRONT_SPRAY_SHARE * top, 0.0, 1.0), _spray_angle(front), giant)


## Which way on screen the spray leaves a point on the board (degrees, 0 right, negative up), from the way the rider
## throws it. The sprite surfer has no board in the 3D stage, so its spray keeps the fan's usual angle.
func _spray_angle(from: Vector3) -> float:
	if _surfer3d == null:
		return SurferSpray.FAN_CENTRE
	var a := _stage.project(from)
	var b := _stage.project(from + rider.spray_dir * SPRAY_PROBE)
	if a.distance_to(b) < 1.0:
		return SurferSpray.FAN_CENTRE
	var angle := rad_to_deg((b - a).angle())
	# (pointing down and to the left, the nearest allowed angle is up and to the left, round the other way)
	if angle > SPRAY_ANGLE_DOWN:
		return SPRAY_ANGLE_UP if angle > 90.0 + SPRAY_ANGLE_DOWN * 0.5 else SPRAY_ANGLE_DOWN
	return maxf(angle, SPRAY_ANGLE_UP)


## Shows the game speed in the corner and in the key list.
func _show_game_speed() -> void:
	_speed_label.text = "game speed %.1fx" % _game_speed + ("   playing: " + MovePlayer.LABELS[_moves.move] if _moves.playing() else "")
	_key_help.text = _key_help_text()


## Temporary: the next of the rising test strengths, so each fan can be judged (B key, or ?autoburst on a phone).
func _throw_test_burst() -> void:
	burst(TEST_BURSTS[_test_burst % TEST_BURSTS.size()])
	_test_burst += 1


## Plays one of the surfer's animations from SurferSprites (temporary: step 6 picks them from how they ride).
func set_surfer_pose(pose_name: String) -> void:
	_pose_index = maxi(SurferSprites.ORDER.find(pose_name), 0)
	_surfer.set_pose(pose_name)


## Frames the camera on the surfer and stands the surfer and the spray cloud on the wave.
func _place_surfer_and_spray() -> void:
	var model := _stage.model
	var feet := model.surface_point(rider.d, rider.u)
	var delta := get_process_delta_time()
	# (down in the water the camera lets him go gently, and the wave rolls on away from it)
	var follow_rate := CAMERA_FOLLOW_RATE * (1.0 if cycle.riding() else 0.4)
	_focus = feet if _first_frame else _focus.lerp(feet, 1.0 - exp(-follow_rate * delta))
	var target_swing := model.barrel()
	_swing = target_swing if _first_frame else lerpf(_swing, target_swing, 1.0 - exp(-CAMERA_SWING_RATE * delta))
	var shoulder := smoothstep(SHOULDER_LOOK_FROM, SHOULDER_LOOK_FULL, rider.d)
	var coming := maxf(reef.weight_of(SectionDirector.Kind.RACECOURSE, rider.d + SECTION_LOOK_AHEAD), reef.weight_of(SectionDirector.Kind.REEF_BOWL, rider.d + SECTION_LOOK_AHEAD))
	var look := CAMERA_YAW_SHOULDER * shoulder + CAMERA_YAW_SECTION * coming
	_look = look if _first_frame else lerpf(_look, look, 1.0 - exp(-CAMERA_LOOK_RATE * delta))
	_shoulder_x = lerpf(_shoulder_x, SURFER_SCREEN_X_SHOULDER * shoulder, 1.0 - exp(-CAMERA_LOOK_RATE * delta))
	_first_frame = false
	var sway := CAMERA_SWAY.x * sin(_time * CAMERA_SWAY_RATES.x * TAU) + CAMERA_SWAY.y * sin(_time * CAMERA_SWAY_RATES.y * TAU + 1.3)
	_heading_pan = lerpf(_heading_pan, CAMERA_HEADING_PAN * (1.0 - cos(rider.theta)) * 0.5, 1.0 - exp(-CAMERA_LOOK_RATE * delta))
	var yaw := lerpf(lerpf(CAMERA_YAW_OPEN, CAMERA_YAW_BARREL, _swing) + _look + sway - _heading_pan, CAMERA_YAW_TUBE, _tuck) + camera_offset
	var screen_x := lerpf(lerpf(SURFER_SCREEN_X_OPEN, SURFER_SCREEN_X_BARREL, _swing) + _shoulder_x, SURFER_SCREEN_X_BARREL, _tuck)
	_stage.frame(_focus, yaw, screen_x, lerpf(WaveStage.CAMERA_FOV, CAMERA_FOV_TUBE, _tuck), lerpf(WaveStage.CAMERA_DISTANCE, CAMERA_DISTANCE_TUBE, _tuck))
	var feet_px := _stage.project(feet)
	var head_px := _stage.project(feet + Vector3(0.0, WaveModel.SURFER_HEIGHT, 0.0))
	_surfer.place(feet_px, feet_px.y - head_px.y)
	if _surfer3d:
		_light_surfer()
		_surfer3d.follow(rider, model, get_process_delta_time())
		_sink_surfer()
		_spray.set_hand_drag(_stage.project(_surfer3d.hand_spray_point), _surfer3d.hand_spray)
		_spray.set_rail(rider.rail_spray, _spray_angle(_surfer3d.tail_point()))
	else:
		_spray.set_hand_drag(Vector2.ZERO, 0.0)
		_spray.set_rail(rider.rail_spray, SurferSpray.FAN_CENTRE)
	# Tilt the surfer with the face: the slope of the wave under their feet, ahead of them to the left.
	var ahead_px := _stage.project(model.surface_point(rider.d + 0.6, rider.u))
	var behind_px := _stage.project(model.surface_point(rider.d - 0.6, rider.u))
	var slope := rad_to_deg(atan2(behind_px.y - ahead_px.y, behind_px.x - ahead_px.x))
	_surfer.set_ground_angle(clampf(slope, -MAX_GROUND_ANGLE, MAX_GROUND_ANGLE))

	var pixels_per_meter := (feet_px.y - head_px.y) / WaveModel.SURFER_HEIGHT
	var drift := TRAVEL_SPEED * size.y * WAKE_DRIFT_FACTOR
	if _surfer3d:  # off the real board: its tail, and the front foot
		_spray.follow(_stage.project(_surfer3d.tail_point()), pixels_per_meter, drift)
		_front_spray.follow(_stage.project(_surfer3d.front_foot_point()), pixels_per_meter, drift)
	else:
		_spray.follow(feet_px + (BOARD_TAIL * pixels_per_meter).rotated(_surfer.rotation), pixels_per_meter, drift)
		_front_spray.follow(feet_px, pixels_per_meter, drift)


## Temporary: - and = change the wave's size, [ and ] its hollowness. (The arrow keys and WASD ride.)
func _read_held_keys(delta: float) -> void:
	var size_change := (float(Input.is_key_pressed(KEY_EQUAL)) - float(Input.is_key_pressed(KEY_MINUS))) * SIZE_RATE * delta
	var hollow_change := (float(Input.is_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_key_pressed(KEY_BRACKETLEFT))) * HOLLOW_RATE * delta
	if size_change != 0.0 or hollow_change != 0.0:
		_size_offset = clampf(_size_offset + size_change, -1.0, 1.0)
		_hollow_offset = clampf(_hollow_offset + hollow_change, -1.0, 1.0)
		var tide := solar.tide()
		_panel.show_values(clampf(tide.x + _size_offset, 0.0, 1.0), clampf(tide.y + _hollow_offset, 0.0, 1.0), peel_offset)


## Down in the water: tumbling under the foam after a wipeout (curled up, arms round his head), then sitting astride
## the board through the lull.
func _sink_surfer() -> void:
	if cycle.riding():
		_surfer3d.set_down(0.0, 0.0)
		return
	var tumble := cycle.tumble()
	var wiping := cycle.state == RideCycle.State.WIPEOUT
	# (he uncurls while still under the foam, so he comes up already sitting on the board)
	var curl := smoothstep(0.0, 0.12, tumble) * (1.0 - smoothstep(0.5, 0.75, tumble)) if wiping else 0.0
	var sit := smoothstep(0.5, 0.85, tumble) if wiping else cycle.sunk()
	var sink := SIT_SINK * sit + TUMBLE_SINK * sin(PI * tumble)
	var spin := Basis(Vector3.RIGHT, TAU * TUMBLE_TURNS * smoothstep(0.0, 1.0, tumble))
	_surfer3d.transform = Transform3D(spin * _surfer3d.transform.basis, _surfer3d.transform.origin + Vector3.DOWN * sink)
	_surfer3d.set_down(sit, curl)


## A faint key list in the lower left for testing. H hides it.
func _add_key_help() -> void:
	_key_help.text = _key_help_text()
	_key_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_help.modulate = Color(1, 1, 1, 0.6)
	_key_help.add_theme_font_size_override("font_size", 15)
	_key_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_key_help.add_theme_constant_override("outline_size", 5)
	_key_help.add_theme_constant_override("line_spacing", -4)
	_key_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_key_help.position += Vector2(14.0, -225.0)
	add_child(_key_help)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.modulate = Color(1, 1, 1, 0.6)
	_readout.add_theme_font_size_override("font_size", 15)
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_readout.add_theme_constant_override("outline_size", 5)
	_readout.position = Vector2(14.0, 44.0)
	add_child(_readout)
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_label.modulate = Color(1, 1, 1, 0.6)
	_speed_label.add_theme_font_size_override("font_size", 15)
	_speed_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_speed_label.add_theme_constant_override("outline_size", 5)
	# (it grows to the left, so the move being played fits on screen beside the speed)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_speed_label.offset_left = -14.0
	_speed_label.offset_right = -14.0
	_speed_label.offset_top = 14.0
	add_child(_speed_label)


func _key_help_text() -> String:
	return "\n".join([
		"1   bottom turn (3D: toggle)", "2   crouch (3D only, toggle)", "3   3D surfer on / off",
		"L  hit the lip   C  cutback (hold down)   F  floater", "T  barrel crouch   P  pump   (any control takes over)",
		"O   next animation", "B   spray burst", "M   next part of the evening", "R   reset", "- =   wave size", "[ ]   hollow",
		", .   game speed (%.1fx)" % _game_speed, "H   hide this (and the test buttons)"])


## Swaps the sprite surfer for the real-time one that lives inside the wave's 3D stage (or back).
func _set_surfer_3d(on: bool) -> void:
	if on and _surfer3d == null:
		_surfer3d = Surfer3D.new()
		_stage.add_actor(_surfer3d)
		_register(_surfer3d.material)
		_register(_surfer3d.veil)
		_apply_mood()
	elif not on and _surfer3d != null:
		_surfer3d.queue_free()
		_surfer3d = null
	_surfer.visible = not on
	# (the spray behind the real-time surfer leaves out his silhouette; the sprite sits above the back layer anyway)
	for spray: SurferSpray in [_spray, _front_spray]:
		spray.set_surfer_mask(_stage.surfer_mask() if on else null)


func _on_panel_changed(wave_size: float, hollowness: float, ahead_of_peel: float) -> void:
	set_wave(wave_size, hollowness, ahead_of_peel)


func _register(material: ShaderMaterial) -> void:
	var declared: Array[String] = []
	for uniform in material.shader.get_shader_uniform_list():
		declared.append(uniform.name)
	var wanted: Array[String] = []
	for property in MoodData.property_names():
		if property in declared:
			wanted.append(property)
	_materials.append(material)
	_mood_uniforms.append({"material": material, "names": wanted})


func _on_resized() -> void:
	var aspect := size.x / size.y
	var layout_aspect := maxf(aspect, MIN_LAYOUT_ASPECT)
	_crop = (layout_aspect - aspect) * 0.5
	for material in _materials:
		material.set_shader_parameter("aspect", aspect)
		material.set_shader_parameter("layout_aspect", layout_aspect)
		material.set_shader_parameter("horizon", HORIZON)
	_place_sun()


## Lights the real-time surfer from the sun: in front of the camera, over the sea, as high as it stands (see KEY_AHEAD).
func _light_surfer() -> void:
	var camera := _stage.camera_basis()
	var ahead := Vector3(-camera.z.x, 0.0, -camera.z.z).normalized()
	var side := Vector3(camera.x.x, 0.0, camera.x.z).normalized()
	var up := clampf(KEY_UP_HORIZON + KEY_UP_GAIN * (HORIZON - _sun_y), KEY_UP_LOW, KEY_UP_HIGH)
	var key := (ahead * KEY_AHEAD + side * KEY_SIDE * (SUN_X_FRACTION - 0.5) + Vector3.UP * up).normalized()
	_surfer3d.material.set_shader_parameter("key_dir", key)
	_surfer3d.veil.set_shader_parameter("key_dir", key)


## The sun sinks through the evening (SolarClock.sun_height); the sky, the glow and the sea's glitter follow it.
func _place_sun() -> void:
	if size.y <= 0.0:
		return
	var layout_aspect := maxf(size.x / size.y, MIN_LAYOUT_ASPECT)
	var sun_pos := Vector2(layout_aspect * SUN_X_FRACTION, _sun_y)
	for material in _materials:
		material.set_shader_parameter("sun_pos", sun_pos)


func _apply_mood() -> void:
	var mood := Palette.current
	for entry in _mood_uniforms:
		for name: String in entry.names:
			entry.material.set_shader_parameter(name, mood.get(name))
	for ridge in _ridges:
		ridge.apply_mood(mood)
	_spray.apply_mood(mood)
	_front_spray.apply_mood(mood)
	_wave_spray.apply_mood(mood)


## A number from the page URL (for example ?size=0.8), or `fallback` when it is missing.
func _url_number(key: String, fallback: float) -> float:
	var text := UrlParams.get_value(key)
	return text.to_float() if text.is_valid_float() else fallback
