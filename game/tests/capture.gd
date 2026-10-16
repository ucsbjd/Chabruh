extends SceneTree
## Renders the main scene in a real window and saves a PNG, so looks can be judged from true
## pixels (the browser pane's capture is colour-managed and washed out). Run it through
## tools/capture.ps1. Options go after `--`, as name=value:
##   out=path.png  size=0.5  hollow=0.5  peel=3.0  mood=sunset  frames=45  pose=ride  gallery=no
##   snaps=60,90,120   also save the frame at each of these frame numbers, as out-60.png and so on
##   height=0.9        where up the face the surfer is held, 0 low to 1 high
##   burst=0.8@70      fire a spray burst of that strength (0 to 1) when that frame is reached
##   carve=3.0         carve up and down the face smoothly, one full cycle in this many seconds (the footage's rhythm)
##   ride=cycle        drop to the bottom, bottom turn up the face, hit the lip, again every 4.4 s
##   ride=stall        steer hard back for 3 s (stall into the pocket), then let go, again every 6 s
##   ride=cutback      the cutback the C key plays (MovePlayer), again each time it finishes
##   move=lip_hit      any move the hotkeys play (lip_hit, cutback, floater, tube, pump), again each time it finishes
##   ride=chase        steer far down the line, so he pumps for speed
##   ride=floater      drive up to the top and let go, so he floats along it
##   readout=yes       show the debug readout (speed, lean, load, balance)
##   solar=1.5         the evening at that time (0 golden .. 3 night), held there, with the tide's wave (size and hollow
##                     are then ignored); without it the mood option is used and the evening is held
##   reef=on           let reef sections come by themselves (off by default, so captures repeat)
##   events=bowl@0,wipeout@200   at those frames: a section (wall, channel, race, bowl) sent in from down the line, or
##                     barrel (G), wipeout (K), lull (Y)
##   overlay=no        hide the test buttons and key list
## (peel is how many meters ahead of the peel point the surfer is.) It also prints the average frame
## time over the last two thirds of the frames. Add --disable-vsync (and use plenty of frames) to see
## what the GPU can sustain.

const DEFAULTS := {"out": "capture.png", "size": "0.5", "hollow": "0.5", "peel": "3.0", "mood": "sunset", "frames": "45", "pose": "ride", "gallery": "no", "snaps": "", "burst": "", "height": "", "s3d": "", "cycle": "0", "carve": "0", "readout": "no", "ride": "", "move": "", "solar": "", "reef": "off", "events": "", "overlay": "yes"}


func _initialize() -> void:
	var options := _read_options()
	var ride_from := -1.0
	var ride_to := -1.0
	var world: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame   # let the scene finish its _ready before configuring it
	world.solar.running = false
	world.reef.enabled = options.reef == "on"
	world.reef.sections.clear()
	if options.solar != "":
		world.evening_phase(0)
		world.solar.time = float(options.solar)
		var tide: Vector3 = world.solar.tide()
		world.set_wave(tide.x, tide.y, float(options.peel))
	else:
		world._mood_from_clock = false
		root.get_node("Palette").select(options.mood, true)
		world.set_wave(float(options.size), float(options.hollow), float(options.peel))
	if options.overlay == "no":
		world._overlay.visible = false
		world._key_help.visible = false
	var events := _read_events(options.events)
	world.set_surfer_pose(options.pose)
	if options.s3d != "":  # the real-time surfer, optionally already blended to a pose (trim, crouch, bottom_turn)
		world._set_surfer_3d(true)
		if options.s3d != "yes":
			world._surfer3d.set_target(options.s3d, 1.0)
	if options.height != "":  # "0.9" holds there; "0.9:0.05" starts at 0.9 and aims at 0.05
		var heights: PackedStringArray = options.height.split(":")
		world.rider.place(world.rider.d, Rider.u_for(float(heights[0])))
		ride_from = float(heights[0])
		ride_to = float(heights[heights.size() - 1])
		world._ride_input.height = ride_from
	if options.readout == "yes":
		world._readout.visible = true
	if options.gallery == "yes":
		world.get_node("PoseGallery").open()
	var frames := int(options.frames)
	var ride_frames := 40  # a ride from one height to another is a scroll over this many frames
	var timed_from := 0
	var snaps: Array[int] = []
	for text: String in String(options.snaps).split(",", false):
		snaps.append(int(text))
	var bursts := _read_bursts(options.burst)
	var track := []  # where the surfer is on screen in each snap, so a contact sheet can follow him
	for i in frames:
		if i == frames / 3:   # time only the last two thirds, after start-up work has settled
			timed_from = Time.get_ticks_usec()
		for strength: float in bursts.get(i, []):
			world.burst(strength)
		for event: String in events.get(i, []):
			_trigger(world, event)
		if options.ride == "cycle":
			var phase := fmod(i / 60.0, 4.4)
			world._ride_input.nudge_height(-0.02 if phase < 0.9 else (0.03 if phase < 2.4 else (-0.05 if phase < 2.8 else 0.0)))
		elif options.ride == "cutback" or options.move != "":
			if not world._moves.playing():
				world.play_move("cutback" if options.move == "" else options.move)
		elif options.ride == "chase":
			world._ride_input.steer = 0.95
		elif options.ride == "floater":
			world._ride_input.nudge_height(0.012 if fmod(i / 60.0, 5.0) < 1.2 else 0.0)
		elif options.ride == "stall":
			world._ride_input.steer = 0.0 if fmod(i / 60.0, 6.0) < 3.0 else RideInput.REST_STEER
		elif float(options.carve) > 0.0:  # a smooth carve: scroll up then down, one cycle per `carve` seconds at 60 frames a second
			world._ride_input.nudge_height(0.0045 * cos(TAU * i / (60.0 * float(options.carve))))
		elif int(options.cycle) > 0:  # scroll down and up over and over, this many frames each way
			world._ride_input.nudge_height(-0.018 if (i / int(options.cycle)) % 2 == 0 else 0.018)
		elif ride_from >= 0.0 and ride_from != ride_to:
			world._ride_input.nudge_height(lerpf(ride_from, ride_to, clampf(float(i + 1) / ride_frames, 0.0, 1.0)) - lerpf(ride_from, ride_to, clampf(float(i) / ride_frames, 0.0, 1.0)))
		await process_frame
		if i in snaps:
			root.get_texture().get_image().save_png(String(options.out).trim_suffix(".png") + "-%d.png" % i)
			track.append(_surfer_on_screen(world, i))
	var timed_frames := frames - frames / 3
	var per_frame_ms := (Time.get_ticks_usec() - timed_from) / 1000.0 / timed_frames
	root.get_texture().get_image().save_png(options.out)
	print("saved ", options.out)
	if not track.is_empty():
		var file := FileAccess.open(String(options.out).trim_suffix(".png") + "-track.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(track))
	print("frame time %.2f ms (%.0f fps)" % [per_frame_ms, 1000.0 / per_frame_ms])
	quit(0)


## The snap's frame, the surfer's feet on screen and his height in pixels, plus the rider's state for the record.
func _surfer_on_screen(world: Control, frame: int) -> Dictionary:
	var model: WaveModel = world._stage.model
	var feet: Vector3 = model.surface_point(world.rider.d, world.rider.u)
	var feet_px: Vector2 = world._stage.project(feet)
	var head_px: Vector2 = world._stage.project(feet + Vector3(0.0, WaveModel.SURFER_HEIGHT, 0.0))
	var rider: Rider = world.rider
	return {"frame": frame, "x": feet_px.x, "y": feet_px.y, "tall": feet_px.y - head_px.y, "u": rider.u, "theta": rad_to_deg(rider.theta),
		"omega": rider.omega, "carve": rad_to_deg(rider.carve), "load": rider.load_g, "crouch": rider.compression, "move": rider.move,
		"stall": rider.stall, "hand_spray": world._surfer3d.hand_spray if world._surfer3d else 0.0}


func _read_options() -> Dictionary:
	var options := DEFAULTS.duplicate()
	for argument in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	return options


## "bowl@0,wipeout@200" becomes {0: ["bowl"], 200: ["wipeout"]}.
func _read_events(text: String) -> Dictionary:
	var result := {}
	for part in text.split(",", false):
		var pair := part.split("@")
		if pair.size() == 2:
			var list: Array = result.get(int(pair[1]), [])
			list.append(pair[0])
			result[int(pair[1])] = list
	return result


func _trigger(world: Control, event: String) -> void:
	var kinds := {"wall": SectionDirector.Kind.CRUISER_WALL, "channel": SectionDirector.Kind.DEEP_CHANNEL,
		"race": SectionDirector.Kind.RACECOURSE, "bowl": SectionDirector.Kind.REEF_BOWL}
	if kinds.has(event):
		world.send_section(kinds[event])
	elif event == "barrel":
		world.barrel_now()
	elif event == "wipeout":
		world.wipeout_now()
	elif event == "lull":
		world.lull_now()


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
