class_name MusicChecks
extends RefCounted
## Checks for MusicLayers, called from the main runner as `MusicChecks.run(_check, self)`.

const CUTOFF_TOLERANCE_HZ := 1.0
const SETTLE_SECONDS := 5.0          # longer than every fade, so values have arrived
const AUDIBLE_DB := -1.0
const SILENT_DB := -60.0
const PEAK_LIMIT_DB := -1.0


static func run(check: Callable, tree: SceneTree) -> void:
	var music := MusicLayers.new()
	tree.root.add_child(music)

	var env_bus := AudioServer.get_bus_index(MusicLayers.ENV_BUS)
	var music_bus := AudioServer.get_bus_index(MusicLayers.MUSIC_BUS)
	check.call(env_bus >= 0, "music: Environment bus exists")
	check.call(music_bus >= 0, "music: Music bus exists")
	check.call(_has_low_pass(env_bus), "music: Environment bus has a low-pass filter")
	check.call(_has_low_pass(music_bus), "music: Music bus has a low-pass filter")

	check.call(not music.ready_to_play(), "music: not ready before generating")
	music.start()   # before generation: must simply start once ready
	music.generate_now()
	check.call(music.ready_to_play(), "music: generation finishes")
	print("music: generated in %.0f ms" % music.generation_msec())

	var same_length := true
	var all_loop := true
	var first := music.stem_stream(0)
	for k in MusicLayers.STEM_COUNT:
		var stream := music.stem_stream(k)
		if stream == null or first == null:
			same_length = false
			all_loop = false
			continue
		same_length = same_length and stream.data.size() == first.data.size()
		all_loop = all_loop and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD \
				and stream.loop_end == MusicLayers.LOOP_SAMPLES
	check.call(same_length and first != null
			and first.data.size() == MusicLayers.LOOP_SAMPLES * 2, "music: four stems of equal length")
	check.call(all_loop, "music: every stem loops over the whole loop")
	check.call(music.music_peak_db() < PEAK_LIMIT_DB, "music: full mix peaks under -1 dBFS")

	music.set_flow(0.0)
	music._advance(SETTLE_SECONDS)
	check.call(music.stem_volume_db(0) > AUDIBLE_DB, "music: pad plays at flow 0")
	check.call(_quiet_from(music, 1), "music: stems 2 to 4 silent at flow 0")

	music.set_flow(1.0)
	music._advance(SETTLE_SECONDS)
	var all_in := true
	for k in MusicLayers.STEM_COUNT:
		all_in = all_in and music.stem_volume_db(k) > AUDIBLE_DB
	check.call(all_in, "music: every stem in at flow 1")

	music.set_flow(0.3)
	music._advance(SETTLE_SECONDS)
	check.call(music.stem_volume_db(1) > SILENT_DB and music.stem_volume_db(2) <= SILENT_DB,
			"music: flow 0.3 brings the bass in but not the drums")

	music.set_hush(1.0)
	music._advance(SETTLE_SECONDS)
	var filter := music.environment_filter()
	check.call(absf(filter.cutoff_hz - MusicLayers.ENV_CUTOFF_DEEP_HZ) < CUTOFF_TOLERANCE_HZ,
			"music: deep in the barrel the sea is cut to 650 Hz")
	check.call(absf(filter.resonance - MusicLayers.ENV_RESONANCE_DEEP) < 0.01,
			"music: resonance rises in the barrel")
	check.call(music.music_filter().cutoff_hz < MusicLayers.MUSIC_CUTOFF_OPEN_HZ * 0.5,
			"music: the score is softened in the barrel")
	check.call(music.roar_volume_db() > AUDIBLE_DB, "music: the tube roar comes up")
	music.set_hush(0.0)
	music._advance(SETTLE_SECONDS)
	check.call(absf(filter.cutoff_hz - MusicLayers.ENV_CUTOFF_OPEN_HZ) < CUTOFF_TOLERANCE_HZ,
			"music: out of the barrel the sea opens to 18 kHz")
	check.call(music.roar_volume_db() <= SILENT_DB, "music: no roar outside the barrel")

	music.set_flow(1.0)
	music.set_lull(true)
	music._advance(SETTLE_SECONDS)
	check.call(_quiet_from(music, 1), "music: a lull silences stems 2 to 4 even at flow 1")
	check.call(music.stem_volume_db(0) > AUDIBLE_DB, "music: the pad stays through a lull")
	music.set_lull(false)

	music.set_muted(true)
	check.call(music.is_muted(), "music: mute is reported")
	music.set_muted(false)
	music.splash(1.0)
	check.call(not music.is_muted(), "music: unmute is reported")

	music.free()


static func _has_low_pass(bus: int) -> bool:
	if bus < 0:
		return false
	for e in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, e) is AudioEffectLowPassFilter:
			return true
	return false


static func _quiet_from(music: MusicLayers, first: int) -> bool:
	for k in range(first, MusicLayers.STEM_COUNT):
		if music.stem_volume_db(k) > SILENT_DB:
			return false
	return true
