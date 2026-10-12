extends SceneTree
## Replays a recorded calibration run through the game's real RideInput and Rider, and prints what the
## surfer did in each move: how far they climbed, how far they slid, how much spray, and which move labels
## showed up. Use it to check the tuning against the hands that were recorded, without recording again.
##   godot_console --headless --path game --script res://tests/replay_calibration.gd -- calibration/session-X.json
## (use tools\replay.ps1, which fills in the path)

const VIEW := Vector2(1280.0, 720.0)
const STEP := 1.0 / 60.0


func _initialize() -> void:
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.ends_with(".json"):
			path = argument
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		print("could not read ", path)
		quit(1)
		return
	var wave := WaveModel.new()
	wave.size = 0.6
	var tuning := (load("res://data/tuning.tres") as TuningData).duplicate() as TuningData
	# Overrides for trying dials without editing the file: key=value, for example wheel_cap=2.5
	for argument in OS.get_cmdline_user_args():
		var parts := argument.split("=")
		if parts.size() == 2 and parts[0] in tuning:
			tuning.set(parts[0], float(parts[1]))
	var summaries := {}
	for trial: Dictionary in data.trials:
		var summary := _replay(trial, wave, tuning)
		var list: Array = summaries.get(trial.move, [])
		list.append(summary)
		summaries[trial.move] = list
	for move: String in summaries:
		var list: Array = summaries[move]
		var labels := {}
		var burst_total := 0
		var biggest := 0.0
		var lows := []
		var highs := []
		var behind := []
		var ahead := []
		for summary: Dictionary in list:
			lows.append(summary.u_min)
			highs.append(summary.u_max)
			behind.append(summary.d_min)
			ahead.append(summary.d_max)
			burst_total += summary.bursts
			biggest = maxf(biggest, summary.biggest)
			for label: String in summary.labels:
				labels[label] = labels.get(label, 0.0) + summary.labels[label]
		var shown := []
		for label: String in labels:
			if labels[label] > 0.25:
				shown.append("%s %.1fs" % [label, labels[label] / list.size()])
		print("%-14s u %.2f..%.2f   d %.1f..%.1f   sprays/trial %.1f (biggest %.2f)   labels: %s" % [
			move, _mean(lows), _mean(highs), _mean(behind), _mean(ahead), float(burst_total) / list.size(), biggest, ", ".join(shown)])
	quit(0)


func _replay(trial: Dictionary, wave: WaveModel, tuning: TuningData) -> Dictionary:
	var input := RideInput.new()
	input.tuning = tuning
	var rider := Rider.new()
	rider.place(Rider.d_for(RideInput.REST_STEER), Rider.u_for(RideInput.REST_HEIGHT))
	var events: Array = trial.events
	var next := 0
	var summary := {"u_min": 1.0, "u_max": 0.0, "d_min": 99.0, "d_max": -99.0, "bursts": 0, "biggest": 0.0, "labels": {}}
	var time := 0.0
	while time < float(trial.duration):
		while next < events.size() and float(events[next][0]) <= time:
			_feed(input, events[next])
			next += 1
		rider.step(STEP, input.steer, input.height, wave, tuning)
		var strength := rider.take_burst()
		if strength > 0.0:
			summary.bursts += 1
			summary.biggest = maxf(summary.biggest, strength)
		summary.u_min = minf(summary.u_min, rider.u)
		summary.u_max = maxf(summary.u_max, rider.u)
		summary.d_min = minf(summary.d_min, rider.d)
		summary.d_max = maxf(summary.d_max, rider.d)
		summary.labels[rider.move] = summary.labels.get(rider.move, 0.0) + STEP
		time += STEP
	input.free()
	return summary


func _feed(input: RideInput, row: Array) -> void:
	var kind: String = row[1]
	if kind == "wheel":
		var wheel := InputEventMouseButton.new()
		wheel.button_index = int(row[2])
		wheel.factor = float(row[3])
		wheel.pressed = true
		input.handle(wheel, VIEW, float(row[0]))
	elif kind == "mouse":
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(float(row[4]), float(row[5]))
		input.handle(motion, VIEW, float(row[0]))
	elif kind == "pan":
		var pan := InputEventPanGesture.new()
		pan.delta = Vector2(float(row[2]), float(row[3]))
		input.handle(pan, VIEW, float(row[0]))


func _mean(values: Array) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / maxf(values.size(), 1)
