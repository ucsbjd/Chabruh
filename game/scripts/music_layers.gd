class_name MusicLayers
extends Node
## The score and the sea, made entirely in code at load: four looping synthwave stems that fade
## in as the ride flows, plus a surf bed, a lap for the lulls, a tube roar and a spray whoosh.
##
## Progress is felt, not counted, so flow only ever adds layers: a warm pad that never leaves, then
## the bassline, the gated drums and the sunset arp. Inside the barrel the world goes hollow: the
## sea is low-passed hard, the music softly, and a low roar comes up.
##
## Everything is rendered into PackedFloat32Arrays by small resumable tasks that `_process` runs
## for about 3 ms a frame (the web build is single-threaded), then packed into 16-bit
## AudioStreamWAVs. All four stems share one length and start in the same frame, so they stay in
## lock-step and only their volume ever changes.

const STEM_COUNT := 4
const STEM_PAD := 0
const STEM_BASS := 1
const STEM_DRUMS := 2
const STEM_LEAD := 3

const MUSIC_BUS := &"Music"
const ENV_BUS := &"Environment"
const MASTER_BUS := &"Master"


# Re-exported from MusicDsp for callers and tests that know only this class.
const LOOP_SAMPLES := MusicDsp.LOOP_SAMPLES
const SAMPLE_RATE := MusicDsp.SAMPLE_RATE

# --- Playback feel.
const FLOW_FADE_SECONDS := 1.2
const LULL_FADE_SECONDS := 1.5
const MUTE_FADE_SECONDS := 0.25
const HUSH_SMOOTH_SECONDS := 0.12
const STEM_FLOW_RANGES: Array[Vector2] = [
	Vector2(-1.0, 0.0), Vector2(0.20, 0.40), Vector2(0.45, 0.65), Vector2(0.75, 0.90),
]
const SILENT_DB := -80.0
const ENV_CUTOFF_OPEN_HZ := 18000.0
const ENV_CUTOFF_DEEP_HZ := 650.0
const ENV_RESONANCE_OPEN := 0.5
const ENV_RESONANCE_DEEP := 1.4
const MUSIC_CUTOFF_OPEN_HZ := 20000.0
const MUSIC_CUTOFF_DEEP_HZ := 2400.0
const MUSIC_RESONANCE := 0.5
const MUSIC_HUSH_DUCK_DB := -5.0
const OCEAN_HUSH_DUCK_DB := -3.0
const ROAR_CURVE := 1.5
const LAP_BASE_GAIN := 0.35
const LAP_LULL_GAIN := 1.0
const SPLASH_DB_SOFT := -18.0
const SPLASH_DB_BIG := -2.0
const SPLASH_PITCH_SOFT := 1.15
const SPLASH_PITCH_BIG := 0.85
const SPLASH_PITCH_JITTER := 0.06
const NOISE_SEED := 1983

var _flow := 0.0
var _hush_target := 0.0
var _hush := 0.0
var _lull := false
var _muted := false
var _mute_level := 1.0
var _lap_level := LAP_BASE_GAIN
var _stem_level := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])

var _start_requested := false
var _music_ready := false
var _beds_ready := false
var _music_playing := false
var _beds_playing := false

var _stem_players: Array[AudioStreamPlayer] = []
var _ocean_player: AudioStreamPlayer
var _lap_player: AudioStreamPlayer
var _roar_player: AudioStreamPlayer
var _splash_players: Array[AudioStreamPlayer] = []
var _splash_next := 0
var _splash_stream: AudioStreamWAV

var _env_filter: AudioEffectLowPassFilter
var _music_filter: AudioEffectLowPassFilter

var _tasks: Array[MusicTasks.Task] = []
var _task_index := 0
var _gen_usec := 0
var _music_peak := 0.0
var _rng := RandomNumberGenerator.new()

# Render buffers, freed once each is packed into its stream.
var _tab_sine := PackedFloat32Array()
var _tab_saw := PackedFloat32Array()
var _tab_saw_soft := PackedFloat32Array()
var _tab_square := PackedFloat32Array()
var _stem_bufs: Array[PackedFloat32Array] = []
var _stem_gains := PackedFloat32Array()   # per-stem balance, then times the mix scale
var _mix_peak := PackedFloat32Array([0.0])
var _stem_streams: Array[AudioStreamWAV] = []
var _bed_encoders: Array[MusicTasks.Encode] = []
var _stem_encoders: Array[MusicTasks.Encode] = []


# Set up in _init rather than _ready, so the node works (and generate_now runs) even before it
# enters a tree that is not ready yet, as in headless tests.
func _init() -> void:
	_rng.seed = NOISE_SEED
	_env_filter = _ensure_bus(ENV_BUS)
	_music_filter = _ensure_bus(MUSIC_BUS)
	_make_players()
	_plan()
	_advance(0.0)


func _ready() -> void:
	# start() may have been asked for before the node could play (players need the tree).
	_start_ready_players()


func _process(delta: float) -> void:
	if _task_index < _tasks.size():
		_generate_for(MusicDsp.GEN_BUDGET_USEC)
	_advance(delta)


# --- Public API ----------------------------------------------------------------------------------

## Begins playback. Call it from the first user gesture (browsers block audio before one). Safe to
## call again; if generation is still running, each part starts as soon as it is ready.
func start() -> void:
	_start_requested = true
	_start_ready_players()


func ready_to_play() -> bool:
	return _music_ready and _beds_ready


## 0..1, how well the ride is flowing. Feed it every frame; the stems fade on their own.
func set_flow(flow: float) -> void:
	_flow = clampf(flow, 0.0, 1.0)


## 0..1, how deep in the barrel.
func set_hush(amount: float) -> void:
	_hush_target = clampf(amount, 0.0, 1.0)


## A lull between sets: only the pad and the lapping water.
func set_lull(on: bool) -> void:
	_lull = on


func set_muted(on: bool) -> void:
	_muted = on


func is_muted() -> bool:
	return _muted


## A soft whoosh for a spray burst or a wipeout, 0..1.
func splash(strength: float) -> void:
	if _splash_stream == null or not _start_requested or not is_inside_tree():
		return
	var s := clampf(strength, 0.0, 1.0)
	var player := _splash_players[_splash_next]
	_splash_next = (_splash_next + 1) % _splash_players.size()
	player.volume_db = lerpf(SPLASH_DB_SOFT, SPLASH_DB_BIG, s)
	player.pitch_scale = lerpf(SPLASH_PITCH_SOFT, SPLASH_PITCH_BIG, s) \
			* (1.0 + randf_range(-SPLASH_PITCH_JITTER, SPLASH_PITCH_JITTER))
	player.play()


## Renders everything at once. For tests and tools; the game lets `_process` spread it out.
func generate_now() -> void:
	_generate_for(1 << 40)


## Total CPU time spent generating so far, in milliseconds.
func generation_msec() -> float:
	return _gen_usec / 1000.0


## Peak of the full four-stem mix as packed, in dBFS (0 until the music is ready).
func music_peak_db() -> float:
	return linear_to_db(maxf(_music_peak, MusicDsp.SILENT_GAIN))


func stem_stream(index: int) -> AudioStreamWAV:
	return _stem_streams[index] if index < _stem_streams.size() else null


func stem_volume_db(index: int) -> float:
	return _stem_players[index].volume_db


func environment_filter() -> AudioEffectLowPassFilter:
	return _env_filter


func music_filter() -> AudioEffectLowPassFilter:
	return _music_filter


func roar_volume_db() -> float:
	return _roar_player.volume_db


## Moves every smoothed value on by `delta` seconds. `_process` calls it; tests call it directly.
func _advance(delta: float) -> void:
	_mute_level = move_toward(_mute_level, 0.0 if _muted else 1.0, delta / MUTE_FADE_SECONDS)
	var fade := LULL_FADE_SECONDS if _lull else FLOW_FADE_SECONDS
	for k in STEM_COUNT:
		_stem_level[k] = move_toward(_stem_level[k], _stem_target(k), delta / fade)
		# Squared, so a fade spends its time in the quiet half and never jumps in.
		_stem_players[k].volume_db = _gain_db(_stem_level[k] * _stem_level[k])
	_lap_level = move_toward(_lap_level, LAP_LULL_GAIN if _lull else LAP_BASE_GAIN,
			delta / LULL_FADE_SECONDS)
	_lap_player.volume_db = _gain_db(_lap_level)

	var follow := 0.0 if delta <= 0.0 else 1.0 - exp(-delta / HUSH_SMOOTH_SECONDS)
	_hush = lerpf(_hush, _hush_target, follow)
	# Exponential in frequency, so each step of depth closes the sound by the same musical amount.
	_env_filter.cutoff_hz = ENV_CUTOFF_OPEN_HZ * pow(ENV_CUTOFF_DEEP_HZ / ENV_CUTOFF_OPEN_HZ, _hush)
	_env_filter.resonance = lerpf(ENV_RESONANCE_OPEN, ENV_RESONANCE_DEEP, _hush)
	_music_filter.cutoff_hz = MUSIC_CUTOFF_OPEN_HZ \
			* pow(MUSIC_CUTOFF_DEEP_HZ / MUSIC_CUTOFF_OPEN_HZ, _hush)
	_roar_player.volume_db = _gain_db(pow(_hush, ROAR_CURVE))
	_ocean_player.volume_db = OCEAN_HUSH_DUCK_DB * _hush

	var master_db := _gain_db(_mute_level)
	var music_bus := AudioServer.get_bus_index(MUSIC_BUS)
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, master_db + MUSIC_HUSH_DUCK_DB * _hush)
	var env_bus := AudioServer.get_bus_index(ENV_BUS)
	if env_bus >= 0:
		AudioServer.set_bus_volume_db(env_bus, master_db)


func _stem_target(k: int) -> float:
	if k == STEM_PAD:
		return 1.0
	if _lull:
		return 0.0
	var r: Vector2 = STEM_FLOW_RANGES[k]
	return smoothstep(r.x, r.y, _flow)


static func _gain_db(gain: float) -> float:
	return SILENT_DB if gain <= MusicDsp.SILENT_GAIN else maxf(linear_to_db(gain), SILENT_DB)


# --- Buses and players ---------------------------------------------------------------------------

## Finds or makes a bus that sends to Master and carries one low-pass filter, and returns the filter.
static func _ensure_bus(bus_name: StringName) -> AudioEffectLowPassFilter:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, MASTER_BUS)
	for e in AudioServer.get_bus_effect_count(idx):
		var effect := AudioServer.get_bus_effect(idx, e) as AudioEffectLowPassFilter
		if effect != null:
			return effect
	var filter := AudioEffectLowPassFilter.new()
	filter.cutoff_hz = MUSIC_CUTOFF_OPEN_HZ if bus_name == MUSIC_BUS else ENV_CUTOFF_OPEN_HZ
	filter.resonance = MUSIC_RESONANCE
	AudioServer.add_bus_effect(idx, filter)
	return filter


func _make_players() -> void:
	for k in STEM_COUNT:
		_stem_players.append(_player(MUSIC_BUS, "Stem%d" % (k + 1)))
	_ocean_player = _player(ENV_BUS, "Ocean")
	_lap_player = _player(ENV_BUS, "Lap")
	_roar_player = _player(ENV_BUS, "Roar")
	for i in MusicDsp.SPLASH_POOL:
		_splash_players.append(_player(ENV_BUS, "Splash%d" % i))


func _player(bus_name: StringName, node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = bus_name
	add_child(p)
	return p


func _start_ready_players() -> void:
	if not _start_requested or not is_inside_tree():
		return
	if _beds_ready and not _beds_playing:
		_beds_playing = true
		_ocean_player.play()
		_lap_player.play()
		_roar_player.play()
	if _music_ready and not _music_playing:
		_music_playing = true
		# Same frame, same length, same rate: they start together and never drift apart.
		for p in _stem_players:
			p.play()


# --- Generation driver ---------------------------------------------------------------------------

func _generate_for(budget_usec: int) -> void:
	var t0 := Time.get_ticks_usec()
	while _task_index < _tasks.size():
		if _tasks[_task_index].step(MusicDsp.GEN_CHUNK):
			_task_index += 1
		if Time.get_ticks_usec() - t0 >= budget_usec:
			break
	_gen_usec += Time.get_ticks_usec() - t0
	if _task_index >= _tasks.size():
		_tasks.clear()
		_task_index = 0


func _plan() -> void:
	# One by one: an Array literal would hold copies, not these buffers.
	_tab_sine.resize(MusicDsp.TABLE_SIZE)
	_tab_saw.resize(MusicDsp.TABLE_SIZE)
	_tab_saw_soft.resize(MusicDsp.TABLE_SIZE)
	_tab_square.resize(MusicDsp.TABLE_SIZE)
	_tasks.append(MusicTasks.TableTask.new(_tab_sine, 1, false))
	_tasks.append(MusicTasks.TableTask.new(_tab_saw, MusicDsp.SAW_HARMONICS, false))
	_tasks.append(MusicTasks.TableTask.new(_tab_saw_soft, MusicDsp.SAW_SOFT_HARMONICS, false))
	_tasks.append(MusicTasks.TableTask.new(_tab_square, MusicDsp.SQUARE_HARMONICS, true))
	# The sea first: it can start playing while the music is still being written.
	_plan_beds()
	_plan_music()


func _plan_beds() -> void:
	var ocean := MusicTasks.NoiseBed.new(MusicDsp.OCEAN_SAMPLES, _rng)
	ocean.low_hz = 320.0
	ocean.hiss_hz = 2200.0
	ocean.base_low = 0.55
	ocean.swell_low = 0.45
	ocean.base_hiss = 0.15
	ocean.swell_hiss = 0.1
	ocean.swell_cycles = Vector2(3, 5)   # swells every 6.5 and 3.9 s, so the sea never pulses evenly
	ocean.events = PackedFloat32Array([0.08, 0.41, 0.74])
	ocean.event_attack = 0.5
	ocean.event_decay = 2.2
	ocean.event_low = 0.5
	ocean.event_hiss = 1.0
	var lap := MusicTasks.NoiseBed.new(MusicDsp.LAP_SAMPLES, _rng)
	lap.low_hz = 520.0
	lap.hiss_hz = 1500.0
	lap.base_low = 0.1
	lap.swell_low = 0.1
	lap.base_hiss = 0.02
	lap.swell_cycles = Vector2(2, 3)
	lap.events = PackedFloat32Array([0.0, 0.27, 0.52, 0.81])
	lap.event_attack = 0.12
	lap.event_decay = 0.5
	lap.event_low = 1.0
	lap.event_hiss = 0.35
	var roar := MusicTasks.NoiseBed.new(MusicDsp.ROAR_SAMPLES, _rng)
	roar.low_hz = 110.0
	roar.hiss_hz = 420.0
	roar.base_low = 1.0
	roar.swell_low = 0.25
	roar.base_hiss = 0.25
	roar.swell_cycles = Vector2(1, 2)
	var splash_task := MusicTasks.Splash.new(int(MusicDsp.SPLASH_SECONDS * MusicDsp.SAMPLE_RATE), _rng)

	# Order matches _finish_beds: ocean, lap, roar, splash.
	_bed_encoders.append(_plan_bed(ocean, ocean.out, MusicDsp.OCEAN_PEAK_DB))
	_bed_encoders.append(_plan_bed(lap, lap.out, MusicDsp.LAP_PEAK_DB))
	_bed_encoders.append(_plan_bed(roar, roar.out, MusicDsp.ROAR_PEAK_DB))
	_bed_encoders.append(_plan_bed(splash_task, splash_task.out, MusicDsp.SPLASH_PEAK_DB))
	_tasks.append(MusicTasks.CallTask.new(_finish_beds))


# Named methods, not lambdas, for the finishing steps: a lambda kept alive in a task leaks at exit.
func _finish_beds() -> void:
	_ocean_player.stream = _wav(_bed_encoders[0].words, true)
	_lap_player.stream = _wav(_bed_encoders[1].words, true)
	_roar_player.stream = _wav(_bed_encoders[2].words, true)
	_splash_stream = _wav(_bed_encoders[3].words, false)
	for p in _splash_players:
		p.stream = _splash_stream
	_bed_encoders.clear()
	_beds_ready = true
	_start_ready_players()


## Queues a bed's render, its seam fold (looping beds), peak normalising and packing.
func _plan_bed(render: MusicTasks.Task, buf: PackedFloat32Array, peak_db: float) -> MusicTasks.Encode:
	_tasks.append(render)
	if render is MusicTasks.NoiseBed:
		_tasks.append(MusicTasks.CallTask.new((render as MusicTasks.NoiseBed).fold))
	var gain := PackedFloat32Array([0.0])
	_tasks.append(MusicTasks.Normalise.new(buf, db_to_linear(peak_db), gain))
	var enc := MusicTasks.Encode.new(buf, gain, 0)
	_tasks.append(enc)
	return enc


func _plan_music() -> void:
	for k in STEM_COUNT:
		var buf := PackedFloat32Array()
		buf.resize(MusicDsp.LOOP_SAMPLES)
		_stem_bufs.append(buf)
	_stem_gains.resize(STEM_COUNT)
	var pad := _stem_bufs[STEM_PAD]
	var bass := _stem_bufs[STEM_BASS]
	var drums := _stem_bufs[STEM_DRUMS]
	var lead := _stem_bufs[STEM_LEAD]

	for bar in MusicDsp.BARS:
		var bar_start := bar * MusicDsp.SAMPLES_PER_BAR
		var tones: Array = MusicDsp.CHORD_TONES[bar]
		_tasks.append(MusicTasks.PadChord.new(pad, _tab_saw, bar_start, tones, _rng))
		for e in MusicDsp.STEPS_PER_BAR / 2:
			var midi: int = MusicDsp.CHORD_ROOTS[bar] + (12 if e % 2 == 1 else 0)
			var vel := MusicDsp.BASS_ACCENT if e % 2 == 0 else MusicDsp.BASS_OFFBEAT
			_tasks.append(MusicTasks.BassNote.new(bass, _tab_saw, _tab_sine,
					bar_start + e * 2 * MusicDsp.SAMPLES_PER_STEP, midi, vel))
		for step in MusicDsp.STEPS_PER_BAR:
			var at := bar_start + step * MusicDsp.SAMPLES_PER_STEP
			if step in MusicDsp.KICK_STEPS:
				_tasks.append(MusicTasks.Kick.new(drums, _tab_sine, at, MusicDsp.KICK_VELOCITY))
			elif step == MusicDsp.KICK_PUSH_STEP and bar % 2 == 1:
				_tasks.append(MusicTasks.Kick.new(drums, _tab_sine, at, MusicDsp.KICK_PUSH_VELOCITY))
			if step in MusicDsp.SNARE_STEPS:
				_tasks.append(MusicTasks.Snare.new(drums, _tab_sine, at, MusicDsp.SNARE_VELOCITY, _rng))
			if step % 2 == 0:
				var hat_vel := MusicDsp.HAT_OFFBEAT_VELOCITY if step % 4 == 2 						else MusicDsp.HAT_ONBEAT_VELOCITY
				_tasks.append(MusicTasks.Hat.new(drums, at, hat_vel, _rng))
			var arp_index: int = MusicDsp.ARP_PATTERN[step % MusicDsp.ARP_PATTERN.size()]
			var tone: int = tones[arp_index] + MusicDsp.ARP_OCTAVE
			_tasks.append(MusicTasks.Pluck.new(lead, _tab_square, at, tone,
					MusicDsp.ARP_ACCENT if step % 4 == 0 else MusicDsp.ARP_SOFT))
	for note in MusicDsp.LEAD_NOTES:
		_tasks.append(MusicTasks.LeadNote.new(lead, _tab_saw_soft, _tab_sine,
				int(note.x) * MusicDsp.SAMPLES_PER_BEAT, int(note.y),
				int(note.z) * MusicDsp.SAMPLES_PER_BEAT))

	_tasks.append(MusicTasks.PadFilter.new(pad))
	_tasks.append(MusicTasks.Echo.new(lead))
	for k in STEM_COUNT:
		_tasks.append(MusicTasks.SumSquares.new(_stem_bufs[k], _stem_gains, k))
	_tasks.append(MusicTasks.CallTask.new(_balance_stems))
	_tasks.append(MusicTasks.MixPeak.new(_stem_bufs, _stem_gains, _mix_peak))
	_tasks.append(MusicTasks.CallTask.new(_scale_mix))
	for k in STEM_COUNT:
		var enc := MusicTasks.Encode.new(_stem_bufs[k], _stem_gains, k)
		_stem_encoders.append(enc)
		_tasks.append(enc)
	_tasks.append(MusicTasks.CallTask.new(_finish_music))


func _finish_music() -> void:
	for k in STEM_COUNT:
		var stream := _wav(_stem_encoders[k].words, true)
		_stem_streams.append(stream)
		_stem_players[k].stream = stream
	_stem_encoders.clear()
	_stem_bufs.clear()
	_tab_sine = PackedFloat32Array()
	_tab_saw = PackedFloat32Array()
	_tab_saw_soft = PackedFloat32Array()
	_tab_square = PackedFloat32Array()
	_music_ready = true
	_start_ready_players()


## Turns each stem's sum of squares into a gain that brings it to its share of the mix.
func _balance_stems() -> void:
	for k in STEM_COUNT:
		var rms := sqrt(_stem_gains[k] / MusicDsp.LOOP_SAMPLES)
		_stem_gains[k] = MusicDsp.STEM_RMS_BALANCE[k] / maxf(rms, MusicDsp.SILENT_GAIN)


func _scale_mix() -> void:
	var scale := db_to_linear(MusicDsp.MUSIC_PEAK_DB) / maxf(_mix_peak[0], MusicDsp.SILENT_GAIN)
	for k in STEM_COUNT:
		_stem_gains[k] *= scale
	_music_peak = db_to_linear(MusicDsp.MUSIC_PEAK_DB)


static func _wav(words: PackedInt32Array, looping: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MusicDsp.SAMPLE_RATE
	wav.stereo = false
	# Each int32 holds two 16-bit samples, so its little-endian bytes are already the PCM data.
	wav.data = words.to_byte_array()
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = words.size() * 2
	return wav
