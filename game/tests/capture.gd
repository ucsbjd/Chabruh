extends SceneTree
## Renders the main scene in a real window and saves a PNG, so looks can be judged from true
## pixels (the browser pane's capture is colour-managed and washed out). Run it through
## tools/capture.ps1. Options go after `--`, as name=value:
##   out=path.png  size=0.5  hollow=0.5  peel=3.0  mood=sunset  frames=45
## (peel is how many meters ahead of the peel point the surfer is.) It also prints the average frame
## time over the last two thirds of the frames. Add --disable-vsync (and use plenty of frames) to see
## what the GPU can sustain.

const DEFAULTS := {"out": "capture.png", "size": "0.5", "hollow": "0.5", "peel": "3.0", "mood": "sunset", "frames": "45"}


func _initialize() -> void:
	var options := _read_options()
	var world: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame   # let the scene finish its _ready before configuring it
	root.get_node("Palette").select(options.mood, true)
	world.set_wave(float(options.size), float(options.hollow), float(options.peel))
	var frames := int(options.frames)
	var timed_from := 0
	for i in frames:
		if i == frames / 3:   # time only the last two thirds, after start-up work has settled
			timed_from = Time.get_ticks_usec()
		await process_frame
	var timed_frames := frames - frames / 3
	var per_frame_ms := (Time.get_ticks_usec() - timed_from) / 1000.0 / timed_frames
	root.get_texture().get_image().save_png(options.out)
	print("saved ", options.out)
	print("frame time %.2f ms (%.0f fps)" % [per_frame_ms, 1000.0 / per_frame_ms])
	quit(0)


func _read_options() -> Dictionary:
	var options := DEFAULTS.duplicate()
	for argument in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	return options
