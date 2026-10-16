extends SceneTree
## Prints the rider's state through a scripted move as a table, so its timing can be compared with the footage
## (docs/balance.md, "Timing"). Run from the game folder:
##   godot_console --headless --path . --script res://tests/ride_trace.gd -- ride=cutback every=3
## ride: cutback (out on the shoulder, once), lip (in the pocket, once), cycle (lip hits every 4.4 s, as capture.ps1
## -Ride cycle), cutbacks (a cutback every 5 s, as -Ride cutback), carve (a smooth 3 s carve), weave (quick turns up and
## down the face). move: a move from MovePlayer instead (lip_hit, cutback, floater, tube, pump), played again each
## time it finishes. every: print every Nth frame.


func _initialize() -> void:
	var options := {"ride": "cutback", "every": "3", "seconds": "6", "size": "0.6", "move": "", "hollow": "0.5"}
	for argument in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	var wave := WaveModel.new()
	wave.size = float(options.size)
	wave.hollowness = float(options.hollow)
	var moves := MovePlayer.new()
	var input := RideInput.new()
	var tuning: TuningData = load("res://data/tuning.tres")
	var rider := Rider.new()
	var ride: String = options.ride
	var shoulder := ride == "cutback" or ride == "cutbacks"
	var steer := Rider.steer_for(10.0) if shoulder else RideInput.REST_STEER
	rider.place(10.0 if shoulder else 3.0, 0.5)
	var peel := wave.peel_speed()
	var every := int(options.every)
	if options.move != "":
		ride = "move " + options.move
		rider.place(3.0, 0.5)
	print("ride %s, peel speed %.2f m/s, wave %.1f m" % [ride, peel, wave.crest_height_at(rider.d)])
	print("   t      u      d   head  omega     v   v/Vp   dv/dt  power  burst  charge  rel  float  move")
	var last_v := 0.0
	for i in int(float(options.seconds) * 60.0):
		var t := i / 60.0
		var push := 0.0
		match ride:
			"cutback", "lip":
				push = -0.02 if t < 0.9 else (0.03 if t < 2.3 else (-0.08 if t < 3.3 else 0.0))
			"cutbacks":
				var phase := fmod(t, 5.0)
				push = -0.02 if phase < 0.9 else (0.03 if phase < 2.3 else (-0.08 if phase < 3.3 else 0.0))
			"cycle":
				var phase := fmod(t, 4.4)
				push = -0.02 if phase < 0.9 else (0.03 if phase < 2.4 else (-0.05 if phase < 2.8 else 0.0))
			"carve":
				push = 0.0045 * cos(TAU * i / 180.0)
			"weave":  # down and up the face over and over, 0.83 s each way (as tests/run_tests.gd)
				push = -0.018 if (i / 50) % 2 == 0 else 0.018
		if options.move != "":
			if not moves.playing():
				moves.play(options.move)
			moves.update(1.0 / 60.0, rider, input)
			steer = input.steer
			push = input.take_height_push()
		rider.step(1.0 / 60.0, steer, push, wave, tuning)
		var burst := rider.take_burst()
		var accel := (rider.v - last_v) * 60.0 if i > 0 else 0.0
		last_v = rider.v
		if i % every == 0 or burst > 0.0:
			print("%5.2f  %5.2f  %5.1f  %5d  %5.1f  %5.1f  %5.2f  %6.1f  %5.2f  %5.2f  %6.2f  %4.2f  %5.2f  %s" % [t, rider.u, rider.d,
				roundi(rad_to_deg(rider.theta)), rider.omega, rider.v, rider.v / peel, accel, rider.spray_power, burst, rider.charge,
				rider.release, rider.afloat, rider.move + ("" if options.move == "" else " / " + moves.phase)])
	input.free()
	quit(0)
