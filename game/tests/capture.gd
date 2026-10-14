extends SceneTree
## Renders the main scene in a real window and saves a PNG, so looks can be judged from true
## pixels (the browser pane's capture is colour-managed and washed out). Run it through
## tools/capture.ps1. Options go after `--`, as name=value:
##   out=path.png  size=0.5  hollow=0.5  peel=3.0  mood=sunset  frames=45  pose=ride  gallery=no
##   snaps=60,90,120   also save the frame at each of these frame numbers, as out-60.png and so on
##   height=0.9        where up the face the surfer is held, 0 low to 1 high
##   burst=0.8@70      fire a spray burst of that strength (0 to 1) when that frame is reached
## (peel is how many meters ahead of the peel point the surfer is.) It also prints the average frame
## time over the last two thirds of the frames. Add --disable-vsync (and use plenty of frames) to see
## what the GPU can sustain.

const DEFAULTS := {"out": "capture.png", "size": "0.5", "hollow": "0.5", "peel": "3.0", "mood": "sunset", "frames": "45", "pose": "ride", "gallery": "no", "snaps": "", "burst": "", "height": "", "s3d": ""}


func _initialize() -> void:
	var options := _read_options()
	var world: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame   # let the scene finish its _ready before configuring it
	root.get_node("Palette").select(options.mood, true)
	world.set_wave(float(options.size), float(options.hollow), float(options.peel))
	world.set_surfer_pose(options.pose)
	if options.s3d != "":  # the real-time surfer, optionally already blended to a pose (trim, crouch, bottom_turn)
		world._set_surfer_3d(true)
		if options.s3d != "yes":
			world._surfer3d.set_target(options.s3d, 1.0)
	if options.height != "":  # "0.9" holds there; "0.9:0.05" starts at 0.9 and aims at 0.05
		var heights: PackedStringArray = options.height.split(":")
		world.rider.place(world.rider.d, Rider.u_for(float(heights[0])))
		world._ride_input.height = float(heights[heights.size() - 1])
	if options.gallery == "yes":
		world.get_node("PoseGallery").open()
	var frames := int(options.frames)
	var timed_from := 0
	var snaps: Array[int] = []
	for text: String in String(options.snaps).split(",", false):
		snaps.append(int(text))
	var bursts := _read_bursts(options.burst)
	for i in frames:
		if i == frames / 3:   # time only the last two thirds, after start-up work has settled
			timed_from = Time.get_ticks_usec()
		for strength: float in bursts.get(i, []):
			world.burst(strength)
		await process_frame
		if i in snaps:
			root.get_texture().get_image().save_png(String(options.out).trim_suffix(".png") + "-%d.png" % i)
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


## "0.5@30,1.0@80" becomes {30: [0.5], 80: [1.0]}.
func _read_bursts(text: String) -> Dictionary:
	var result := {}
	for part in text.split(",", false):
		var pair := part.split("@")
		if pair.size() == 2:
			var frame := int(pair[1])
			var list: Array = result.get(frame, [])
			list.append(float(pair[0]))
			result[frame] = list
	return result
