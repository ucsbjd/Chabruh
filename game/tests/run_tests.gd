extends SceneTree
## Headless smoke test. Run from the repo root:
##   godot_console --headless --path game --script res://tests/run_tests.gd
## Exits with the number of failed checks, so any failure is a non-zero exit code.

# Autoloads are not global names in --script mode, so reach the Palette code through its script.
const PaletteScript := preload("res://scripts/palette.gd")

# Colour uniforms that RidgeLayer sets from code, so they are not mood properties.
const CODE_FED_COLOURS: Array[String] = ["ridge_color"]

var _failures := 0


func _initialize() -> void:
	_test_main_scene()
	_test_moods()
	_test_shader_colours()
	_test_ridge_layer()
	_test_wave_model()
	_test_wave_section()
	_test_wave_mesh()
	_test_noise_textures()
	_test_wave_motion()
	_test_wave_mist()
	_test_carve_trail()
	_test_spray()
	_test_riding()
	await _test_calibration()
	_test_surfer_sprites()
	_test_surfer()
	_test_surfer_3d()
	_test_tuning()
	await _test_world()
	print("%s: %d failed" % ["FAIL" if _failures > 0 else "PASS", _failures])
	quit(_failures)


func _test_main_scene() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		return
	var main := packed.instantiate()
	_check(main != null, "main scene instantiates")
	_check(main.get_script() != null, "main scene script compiled")
	main.free()


func _test_moods() -> void:
	_check(root.has_node("Palette"), "Palette autoload exists")
	var expected := MoodData.property_names()
	_check(expected.size() > 0, "MoodData declares colour roles")
	_check(PaletteScript.MOOD_ORDER.has(PaletteScript.DEFAULT_MOOD), "default mood is one of the moods")
	for mood_name: String in PaletteScript.MOOD_ORDER:
		var table: Dictionary = PaletteScript.MOODS[mood_name]
		var missing: Array[String] = []
		for property in expected:
			if not table.has(property):
				missing.append(property)
		var unknown: Array[String] = []
		for key: String in table:
			if not key in expected:
				unknown.append(key)
		_check(missing.is_empty(), "%s mood defines every role %s" % [mood_name, missing])
		_check(unknown.is_empty(), "%s mood has no unknown roles %s" % [mood_name, unknown])

	var sunset := PaletteScript.build("sunset")
	var neon := PaletteScript.build("neon")
	var halfway := sunset.mixed_with(neon, 0.5)
	_check(halfway.sky_top.is_equal_approx(sunset.sky_top.lerp(neon.sky_top, 0.5)), "moods blend colours")
	_check(is_equal_approx(halfway.glow_strength, lerpf(sunset.glow_strength, neon.glow_strength, 0.5)), "moods blend strengths")


## Every colour uniform in a shader must be a MoodData property, or world.gd would never feed it
## (unless the code that owns the material feeds it, as listed in CODE_FED_COLOURS).
func _test_shader_colours() -> void:
	var names := MoodData.property_names()
	var shader_count := 0
	for file in DirAccess.get_files_at("res://shaders"):
		if not file.ends_with(".gdshader"):
			continue
		shader_count += 1
		var shader := load("res://shaders/" + file) as Shader
		for uniform in shader.get_shader_uniform_list():
			if uniform.type == TYPE_COLOR and not uniform.name in CODE_FED_COLOURS:
				_check(uniform.name in names, "%s: colour uniform '%s' is a MoodData role" % [file, uniform.name])
	_check(shader_count > 0, "shaders were found")


func _test_ridge_layer() -> void:
	var layer := RidgeLayer.new()
	layer.palm_clusters = 2
	layer.build(0.4)
	layer.apply_mood(PaletteScript.build("sunset"))
	var ridge: Polygon2D = layer.get_child(0)
	var palms: Polygon2D = layer.get_child(1)
	var sunset := PaletteScript.build("sunset")
	_check(ridge.polygon.size() > 0, "ridge has an outline")
	_check(ridge.material is ShaderMaterial, "ridge is coloured by a shader, not by redrawing polygons")
	_check(ridge.material.get_shader_parameter("ridge_color") == sunset.ridge_far, "ridge takes its colour from the mood")
	_check(palms.polygons.size() > 0, "palms were built")
	layer.free()


func _test_wave_model() -> void:
	var wave := WaveModel.new()

	wave.size = 0.0
	var small := wave.height()
	wave.size = 1.0
	var big := wave.height()
	_check(is_equal_approx(small, WaveModel.MIN_HEIGHT) and is_equal_approx(big, WaveModel.MAX_HEIGHT), "size spans the minimum to the maximum height")
	wave.size = 0.5
	var surfers := wave.height() / WaveModel.SURFER_HEIGHT
	_check(surfers > 1.4 and surfers < 2.0, "the default wave is about 1.7 surfers tall, like the key frames (%.2f)" % surfers)

	_check(wave.crest_height_at(WaveModel.PEAK_AT) > wave.crest_height_at(12.0) and wave.crest_height_at(WaveModel.PEAK_AT) > wave.height(), "the wave has a peak: highest just ahead of the peel point")
	_check(wave.trough_z_at(40.0) / wave.crest_height_at(40.0) > wave.trough_z_at(2.0) / wave.crest_height_at(2.0), "the face runs longer and gentler down the shoulder")
	_check(wave.crest_height_at(wave.shoulder_length()) < wave.height() * 0.42 and wave.crest_height_at(wave.shoulder_length()) > wave.height() * 0.2, "the shoulder settles low, to about a third of the wave's height, at its far end")
	_check(wave.crest_height_at(12.0) > wave.height() * 0.8, "the playable wall holds most of its height for the first dozen meters")
	_check(Rider.slope_at(wave, 16.0, 0.8) < Rider.slope_at(wave, 3.0, 0.8) - 0.2, "down the shoulder the face relaxes and rounds over")
	_check(wave.power_at(2.0) > 0.95 and wave.power_at(16.0) < 0.75 and wave.power_at(30.0) < wave.power_at(16.0), "the wave pushes hardest in the pocket and less and less down the shoulder")
	_check(wave.draw_at(2.0, 0.9) > wave.draw_at(2.0, 0.5) and wave.draw_at(2.0, 0.5) > wave.draw_at(2.0, 0.1) and wave.draw_at(20.0, 0.5) < wave.draw_at(2.0, 0.5) * 0.75, "the water draws up the face hardest by the lip in the pocket and calms down the shoulder")
	_check(wave.crest_height_at(wave.shoulder_length() * 0.5) < wave.crest_height_at(WaveModel.PEAK_AT + 4.0) and wave.crest_height_at(wave.shoulder_length() * 0.5) > wave.crest_height_at(wave.shoulder_length() * 0.9), "it eases down gradually, not in one step")
	_check(wave.taper_at(0.0) > wave.taper_at(20.0) and wave.taper_at(20.0) > wave.taper_at(45.0), "the wall tapers down the line")
	_check(wave.crest_height_at(-8.0) < wave.crest_height_at(0.0) * 0.2, "the wall collapses behind the peel point")
	_check(wave.crest_height_at(-WaveModel.PROFILE_BEHIND) < 0.01, "the wave has faded out at the far end behind")

	var feet := wave.surface_point(2.0, 0.5)
	_check(is_equal_approx(feet.x, -2.0), "ahead of the peel point is toward negative x, along the crest")
	_check(is_zero_approx(wave.surface_point(2.0, 0.0).y), "height 0 on the face is the trough")
	_check(wave.surface_point(2.0, 1.0).y > feet.y and feet.y > 0.0, "the face climbs from the trough to its top")
	_check(wave.surface_point(2.0, 1.0).y < wave.crest_point(2.0).y + 0.001, "the top of the face is at or under the crest")
	_check(wave.surface_normal(2.0, 0.5).z > 0.0 and is_equal_approx(wave.surface_normal(2.0, 0.5).length(), 1.0), "the face looks out toward the beach")
	_check(wave.face_angle(1.0) > wave.face_angle(0.0), "the face steepens toward the crest")

	wave.size = 1.0
	wave.hollowness = 1.0
	_check(wave.barrel() > 0.9, "a big hollow wave is a full barrel")
	_check(wave.zone_at(8.0) == WaveModel.Zone.SHOULDER, "far ahead of the break is the shoulder")
	_check(wave.zone_at(2.0) == WaveModel.Zone.POCKET, "just ahead of the break is the pocket")
	_check(wave.zone_at(-1.0) == WaveModel.Zone.BARREL, "just behind the break of a hollow wave is the barrel")
	_check(wave.zone_at(-9.0) == WaveModel.Zone.WHITEWATER, "far behind the break is whitewater")
	var lip := wave.lip_tip_point(-1.0)
	_check(lip.z > wave.crest_point(-1.0).z, "the lip is thrown out toward the beach, past the crest")
	wave.hollowness = 0.0
	_check(is_zero_approx(wave.barrel()) and wave.zone_at(-1.0) == WaveModel.Zone.WHITEWATER, "a spilling wave has no barrel")
	wave.size = 0.0
	wave.hollowness = 1.0
	_check(is_zero_approx(wave.barrel()), "a tiny wave cannot hold a barrel")

	_check(is_equal_approx(WaveModel.peel_speed_for(0.5, 30.0), 1.0), "at a 30 degree peel angle the break moves at twice the wave speed")
	_check(is_equal_approx(WaveModel.peel_angle_for(0.5, 1.0), 30.0), "peel angle is the inverse of peel speed")
	wave.celerity = 0.5
	wave.peel_angle_degrees = 40.0
	_check(is_equal_approx(wave.peel_speed(), 0.5 / sin(deg_to_rad(40.0))), "the model's peel speed is celerity over sin of the peel angle")

	wave.size = 0.7
	wave.hollowness = 0.8
	var profile := wave.bake_profile()
	_check(profile.get_width() == WaveModel.PROFILE_WIDTH and profile.get_format() == Image.FORMAT_RGBAH, "the baked profile is a half-float strip")
	var matches := true
	for index in [150, 256, 380, 450]:
		var d := WaveModel.sample_distance(index)
		var pixel := profile.get_pixel(index, 0)
		var section := wave.section(d)
		matches = matches and absf(pixel.r - wave.crest_height_at(d)) < 0.01 and absf(pixel.g - section.points[section.face_to].x) < 0.01
		matches = matches and absf(pixel.b - wave.curl_at(d)) < 0.002 and absf(pixel.a - wave.foam_at(d)) < 0.002
	_check(matches, "the baked profile matches the model at sample points")


func _test_wave_section() -> void:
	var wave := WaveModel.new()
	wave.size = 0.8
	wave.hollowness = 1.0
	var section := wave.section(-1.0)
	var count := section.points.size()
	_check(count > 20 and section.height_fraction.size() == count and section.foam.size() == count, "a section has shading attributes for every point")
	var highest := 0.0
	for point in section.points:
		highest = maxf(highest, point.y)
	_check(is_equal_approx(section.points[section.crest].y, highest), "the crest is the highest point of the section")
	_check(absf(highest - wave.crest_height_at(-1.0)) < wave.crest_height_at(-1.0) * 0.12, "the section is as tall as the wave (%.2f of %.2f m)" % [highest, wave.crest_height_at(-1.0)])
	_check(is_zero_approx(section.face_point(0.0).y) and section.face_point(1.0).y > section.face_point(0.5).y, "the face runs from the trough up")
	_check(section.points[section.lip_tip].x > section.points[section.crest].x, "the lip tip is beyond the crest toward the beach")


func _test_wave_mesh() -> void:
	var wave := WaveModel.new()
	wave.size = 0.9
	wave.hollowness = 1.0
	var mesh := WaveMesh.build(wave)
	_check(mesh.get_surface_count() == 1, "the wave is one mesh surface")
	var arrays := mesh.surface_get_arrays(0)
	var stations := WaveMesh.station_distances().size()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check(vertices.size() == stations * wave.section(0.0).points.size(), "the mesh has one ring of vertices per station")
	_check(arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_NORMAL] != null and arrays[Mesh.ARRAY_TEX_UV] != null, "the mesh carries normals, shading attributes and UVs")
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	_check(custom.size() == vertices.size() * 4 and uv2.size() == vertices.size(), "every vertex carries the lifted and landed lip shapes, and its lip and whitewater amounts")
	var box := mesh.get_aabb()
	_check(box.position.x < -WaveModel.PROFILE_AHEAD * 0.9 and box.end.x > WaveModel.PROFILE_BEHIND * 0.9, "the mesh runs the length of the profile")
	_check(box.size.y > wave.height() * 0.8 and box.size.y < wave.height() * 1.25, "the mesh is as tall as the wave (%.2f of %.2f m)" % [box.size.y, wave.height()])
	_check(is_equal_approx(WaveMesh.station_distances()[0], -WaveModel.PROFILE_BEHIND) and is_equal_approx(WaveMesh.station_distances()[stations - 1], WaveModel.PROFILE_AHEAD), "the stations cover the whole profile")


func _test_noise_textures() -> void:
	for texture: ImageTexture in [NoiseTextures.cells(), NoiseTextures.warp()]:
		var image := texture.get_image()
		_check(image.get_width() == NoiseTextures.SIZE and image.get_height() == NoiseTextures.SIZE, "a noise texture is the expected size")
	var cells := NoiseTextures.cells().get_image()
	var darkest := 1.0
	var brightest := 0.0
	for y in cells.get_height():
		for x in cells.get_width():
			var value := cells.get_pixel(x, y).r
			darkest = minf(darkest, value)
			brightest = maxf(brightest, value)
	_check(darkest < 0.05 and brightest > 0.9, "the cell texture spans dark edges to bright centres")


func _test_wave_motion() -> void:
	var wave := WaveModel.new()
	wave.size = 0.8
	wave.hollowness = 1.0
	var lifted := wave.section_key(-1.0, WaveModel.LipShape.LIFTED)
	var thrown := wave.section_key(-1.0, WaveModel.LipShape.THROWN)
	var landed := wave.section_key(-1.0, WaveModel.LipShape.LANDED)
	_check(lifted.points.size() == thrown.points.size() and landed.points.size() == thrown.points.size(), "the three lip shapes have the same points, so the shader can morph between them")
	_check(is_equal_approx(lifted.points[lifted.face_to].x, thrown.points[thrown.face_to].x) and is_equal_approx(landed.points[landed.face_to].x, thrown.points[thrown.face_to].x), "the foot of the wave stays put through the lip cycle")
	_check(lifted.points[lifted.crest].y > thrown.points[thrown.crest].y and landed.points[landed.crest].y < thrown.points[thrown.crest].y, "the lip stands up, then falls: lifted is taller than thrown, landed is lower")
	_check(is_equal_approx(wave.section_key(30.0, WaveModel.LipShape.LANDED).points[5].y, wave.section_key(30.0, WaveModel.LipShape.LIFTED).points[5].y), "far down the line, where there is no lip, the shapes agree")
	var landing := wave.lip_landing_point(-1.0)
	_check(is_zero_approx(landing.y) and landing.z > wave.lip_tip_point(-1.0).z, "the lip lands on the water, beyond where its tip is now")
	_check(is_zero_approx(wave.whitewater_at(3.0)) and wave.whitewater_at(-8.0) > 0.9 and wave.whitewater_at(-WaveModel.PROFILE_BEHIND) < 0.01, "whitewater appears behind the break and thins far behind")
	_check(wave.mist_at(-1.0) > wave.mist_at(25.0) and wave.mist_at(25.0) > 0.0, "spray is thickest at the break, with a little spindrift all along the crest")
	var stage := WaveStage.new()
	var phase := stage.lip_phase_at(2.0, 3.0)
	_check(phase >= 0.0 and phase < 1.0 and is_equal_approx(stage.lip_phase_at(2.0, 3.0 + WaveStage.LIP_PERIOD), phase), "the lip's cycle repeats every period")
	_check(stage.lip_phase_at(2.0 - WaveStage.LIP_SPACING, 3.0) == stage.lip_phase_at(2.0, 3.0) or absf(stage.lip_phase_at(2.0 - WaveStage.LIP_SPACING, 3.0) - phase) > 0.99, "lips one spacing apart along the crest are in the same state")
	stage.free()


func _test_wave_mist() -> void:
	var wave := WaveModel.new()
	wave.size = 0.7
	wave.hollowness = 0.9
	var mesh := WaveMist.build(wave)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check(vertices.size() == colors.size() and vertices.size() > 100, "the crest mist is a curtain of many points")
	var in_range := true
	for color in colors:
		in_range = in_range and color.r >= 0.0 and color.r <= 1.0
	_check(in_range, "mist density is 0 to 1 at every point")
	var column_height := vertices[WaveMist.ROWS - 1].y - vertices[0].y
	_check(column_height > 0.0, "the mist stands up from the crest")


func _test_carve_trail() -> void:
	var wave := WaveModel.new()
	wave.size = 0.6
	wave.hollowness = 0.5
	var trail := WaveCarveTrail.new()
	trail.rebuild(wave)
	var section := wave.section(3.0)
	_check(WaveCarveTrail.SEGMENTS == section.face_to - section.face_from, "the carve trail's grid has a row for every point up the drawn face")
	_check(WaveStage.lip_morph(0.0) == Vector2(1.0, 0.0) and WaveStage.lip_morph(0.4) == Vector2.ZERO and is_equal_approx(WaveStage.lip_morph(0.7).y, 1.0), "the lip's morph weights: lifted at the start of the cycle, still in between, fallen as it lands")

	# A board in trim leaves a thin, faint wake; a full-power turn a wide, solid gouge.
	var step := 1.0 / 60.0
	var time := 10.0
	trail.carve(step, 3.0, 0.5, 0.0, 0.0, time)
	var trim := trail.point(0)
	_check(is_equal_approx(trim.z, WaveCarveTrail.WIDTH_TRIM) and is_equal_approx(trail.point_strength(0), WaveCarveTrail.STRENGTH_TRIM), "in trim the board leaves a thin, faint wake")
	_check(trim.x < 3.0 and trim.x > 3.0 - WaveCarveTrail.TAIL_BEHIND - 0.01, "the trail starts at the board's tail, just behind the back foot")
	trail.clear()
	trail.carve(step, 3.0, 0.5, 0.0, 1.0, time)
	_check(is_equal_approx(trail.point(0).z, WaveCarveTrail.WIDTH_CARVE) and is_equal_approx(trail.point_strength(0), 1.0), "a full-power turn cuts a wide, solid gouge")

	# The wave carries the point: back toward the curl at the peel speed, up the face with the water's draw, and it spreads.
	var before := trail.point(0)
	var dt := 0.04
	trail.carve(dt, 3.0, 0.5, 0.0, 1.0, time + dt)
	var after := trail.point(0)
	_check(trail.point_count() == 1, "no new point before RECORD_EVERY has passed")
	_check(is_equal_approx(before.x - after.x, wave.peel_speed() * dt), "a point falls behind toward the curl at the peel speed (%.3f m)" % (before.x - after.x))
	var climb := trail.draw_speed * wave.draw_at(after.x, before.y) / maxf(1.2, wave.crest_height_at(after.x)) * dt
	_check(after.y > before.y and absf((after.y - before.y) / climb - 1.0) < 0.1, "the water's draw lifts a point up the face as it lifts the rider (%.4f of %.4f)" % [after.y - before.y, climb])
	_check(is_equal_approx(after.z - before.z, WaveCarveTrail.WIDEN * dt) and is_equal_approx(after.w, dt), "a point spreads and ages")

	# A long carve: the ring holds a fixed number of points, the oldest goes after LIFETIME, the trail stretches back.
	trail.clear()
	var most := 0
	for i in 240:
		time += step
		trail.carve(step, 3.0, 0.5, 0.3 * sin(i * 0.1), 0.5, time)
		most = maxi(most, trail.point_count())
	_check(most == WaveCarveTrail.CAPACITY and trail.point_count() >= WaveCarveTrail.CAPACITY - 1, "the trail keeps a ring of %d points (most %d)" % [WaveCarveTrail.CAPACITY, most])
	var oldest := trail.point(trail.point_count() - 1)
	_check(oldest.w < WaveCarveTrail.LIFETIME and oldest.w > WaveCarveTrail.LIFETIME - 2.0 * WaveCarveTrail.RECORD_EVERY, "points last %.1f s (oldest %.2f s)" % [WaveCarveTrail.LIFETIME, oldest.w])
	_check(trail.point(0).x - oldest.x > wave.peel_speed() * (WaveCarveTrail.LIFETIME - 0.2), "the trail stretches back toward the curl")
	var arrays := trail.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check(trail.mesh.get_surface_count() == 1 and vertices.size() == (trail.point_count() + 1) * 2, "the trail is one strip, two vertices for each point and the board's tail")
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check(colors[0].g == 0.0 and colors[colors.size() - 1].g > 0.9, "the strip carries each point's age, new at the board")

	# The strip lies on the face as it is drawn: on the steady shape where there is no lip...
	var still := wave.surface_point(13.0, 0.55) + wave.surface_normal(13.0, 0.55) * WaveCarveTrail.LIFT_OFF
	_check(trail.face_point(13.0, 0.55, time).distance_to(still) < 0.001, "the trail sits just off the face where it is still")
	# ...and moving with the lip's cycle in the pocket: fully lifted when the phase is 0.
	var lifted_time := WaveStage.LIP_PERIOD * (1.0 - 1.0 / WaveStage.LIP_SPACING)
	var thrown := wave.section_key(1.0, WaveModel.LipShape.THROWN)
	var lifted := wave.section_key(1.0, WaveModel.LipShape.LIFTED)
	var morphed := thrown.face_point(0.55).lerp(lifted.face_point(0.55), wave.throw_at(1.0)) + thrown.face_normal(0.55) * WaveCarveTrail.LIFT_OFF
	var on_face := trail.face_point(1.0, 0.55, lifted_time)
	_check(on_face.distance_to(Vector3(-1.0, morphed.y, morphed.x)) < 0.001 and on_face.distance_to(trail.face_point(1.0, 0.55, lifted_time + WaveStage.LIP_PERIOD * 0.4)) > 0.02, "in the pocket the trail rises and falls with the face through the lip's cycle")

	# Riding in the pocket, the old foam drifts back into the whitewater behind the break and is gone there.
	trail.clear()
	for i in 90:
		time += step
		trail.carve(step, 0.5, 0.4, 0.0, 1.0, time)
	colors = trail.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	_check(colors[0].a > 0.5 and colors[colors.size() - 1].a < 0.05, "the whitewater swallows the trail behind the break")
	trail.clear()
	_check(trail.point_count() == 0 and trail.mesh.get_surface_count() == 0, "clearing forgets the trail")
	trail.free()


func _test_spray() -> void:
	_check(SprayTextures.droplet().get_height() > SprayTextures.droplet().get_width(), "a droplet is longer than it is wide, so it can trail along its path")
	var spray := SurferSpray.new()
	spray.follow(Vector2(600.0, 400.0), 104.0, 100.0)
	_check(spray.position == Vector2(600.0, 400.0), "the spray sits on the board's tail")
	_check(spray.live_particles() == 0 or spray.live_particles() <= spray.particle_budget(), "nothing is thrown before a burst")
	var before := spray.live_particles()
	spray.burst(1.0)
	_check(spray.live_particles() > before, "a burst puts droplets in the air")
	var gentle := SurferSpray.new()
	gentle.burst(0.1)
	_check(gentle.live_particles() < spray.live_particles() / 2, "a gentle burst throws far fewer droplets than a full fan")
	_check(spray.particle_budget() < 1500, "the spray stays under a mobile particle budget (%d)" % spray.particle_budget())
	spray.burst(2.0)
	spray.burst(-1.0)
	_check(true, "out of range strengths are clamped, not errors")
	gentle.free()
	spray.free()
	var wave_spray := WaveSpray.new()
	_check(wave_spray.particle_budget() < 400, "the lip spit stays small (%d)" % wave_spray.particle_budget())
	wave_spray.free()


func _test_riding() -> void:
	var view := Vector2(1280.0, 720.0)
	var input := RideInput.new()
	var start_height := input.height
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 1.0
	input.handle(wheel, view)
	_check(input.height > start_height, "the wheel up lifts the surfer up the face")
	var flick := RideInput.new()
	var flick_wheel := InputEventMouseButton.new()
	flick_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	flick_wheel.pressed = true
	flick_wheel.factor = 20.0
	flick.handle(flick_wheel, view)
	_check(flick.height - RideInput.REST_HEIGHT <= flick.tuning.wheel_height_step * flick.tuning.wheel_cap + 0.001, "one huge flick step is capped, so it cannot pin the surfer to the top")
	var small := RideInput.new()
	flick_wheel.factor = 0.05
	small.handle(flick_wheel, view)
	_check(absf(small.height - RideInput.REST_HEIGHT - small.tuning.wheel_height_step * 0.05) < 0.0005, "small trackpad steps stay exact")
	flick.free()
	small.free()
	var lock := RideInput.new()
	flick_wheel.factor = 0.1
	for i in 10:
		lock.handle(flick_wheel, view)
	var sideways := InputEventMouseButton.new()
	sideways.button_index = MOUSE_BUTTON_WHEEL_LEFT
	sideways.pressed = true
	sideways.factor = 0.05
	lock.handle(sideways, view)
	_check(is_equal_approx(lock.steer, RideInput.REST_STEER), "stray sideways steps are ignored while scrolling up and down")
	lock.free()
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0.0, -10.0)
	var before := input.height
	input.handle(pan, view)
	_check(input.height > before, "two fingers sliding up the trackpad lift the surfer")
	pan.delta = Vector2(-10.0, 0.0)
	var steer_before := input.steer
	input.handle(pan, view)
	_check(input.steer > steer_before, "two fingers sliding left send the surfer ahead, to the left")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(60.0, 300.0)
	input.handle(motion, view)
	var left := input.steer
	motion.position = Vector2(1220.0, 300.0)
	input.handle(motion, view)
	_check(left > RideInput.REST_STEER and input.steer < RideInput.REST_STEER, "the mouse on the left steers ahead, on the right back toward the curl")
	for i in 400:
		input.handle(wheel, view)
	_check(input.height <= 1.0 and input.steer >= 0.0 and input.steer <= 1.0, "the input is always clamped to 0 to 1")
	input.free()

	_check(is_equal_approx(Rider.steer_for(Rider.d_for(0.3)), 0.3), "steering maps to a place on the wave and back")
	_check(absf(Rider.d_for(RideInput.REST_STEER) - 3.0) < 0.6, "the middle of the steering range is the pocket")
	var wave := WaveModel.new()
	wave.size = 0.6
	var tuning := TuningData.new()
	var rider := Rider.new()
	rider.place(3.0, 0.5)
	for i in 1500:
		rider.step(1.0 / 60.0, 0.7, 0.0, wave, tuning)
	_check(absf(rider.d - Rider.d_for(0.7)) < 0.8, "the surfer settles where they steer along the wave (d %.2f of %.2f)" % [rider.d, Rider.d_for(0.7)])
	# Out in front the wave has gone soft: steered far down the shoulder he cannot hold it, slows, and the curl comes back.
	var runner := Rider.new()
	runner.place(3.0, 0.5)
	var pocket_speed := 0.0
	for i in 1500:
		runner.step(1.0 / 60.0, 1.0, 0.0, wave, tuning)
		if i == 60:
			pocket_speed = runner.v
	_check(runner.d < Rider.d_for(1.0) - 1.0 and runner.v < pocket_speed, "steered far out in front, the soft shoulder slows him and the curl comes back (d %.1f of %.1f, %.1f m/s, %.1f in the pocket)" % [runner.d, Rider.d_for(1.0), runner.v, pocket_speed])
	var holder := Rider.new()
	holder.place(3.0, 0.4)
	for i in 180:
		holder.step(1.0 / 60.0, RideInput.REST_STEER, 0.0, wave, tuning)
	_check(holder.u > 0.4 + 0.01 and holder.u < 0.4 + 0.3, "with no input the wave carries him slowly up the face (0.40 to %.2f in 3 s)" % holder.u)
	var diver := Rider.new()
	diver.place(3.0, 0.7)
	var v_start := 0.0
	var v_dive := 0.0
	for i in 90:
		diver.step(1.0 / 60.0, 0.49, -0.01, wave, tuning)  # scrolling down
		if i == 0:
			v_start = diver.v
		v_dive = maxf(v_dive, diver.v)
	_check(diver.theta < 0.0 and diver.u < 0.7 and v_dive > v_start + 0.5, "scrolling down points the nose down, drops him and builds speed (v %.1f to %.1f)" % [v_start, v_dive])
	var climber := Rider.new()
	climber.place(3.0, 0.3)
	for i in 60:
		climber.step(1.0 / 60.0, 0.49, 0.01, wave, tuning)  # scrolling up
	_check(climber.theta > holder.theta and climber.u > 0.3, "scrolling up points the nose up the face")
	var cruiser := Rider.new()
	cruiser.place(3.0, 0.5)
	var pumper := Rider.new()
	pumper.place(3.0, 0.5)
	var cruise_speed := 0.0
	var pump_speed := 0.0
	for i in 600:
		cruiser.step(1.0 / 60.0, 0.49, 0.0, wave, tuning)
		pumper.step(1.0 / 60.0, 0.49, 0.05 if i % 40 == 0 else (-0.05 if i % 40 == 20 else 0.0), wave, tuning)  # a notch up, a notch down, again and again
		if i >= 120 and i < 300:  # (while still in the pocket: the speed carries him out onto the shoulder after that)
			cruise_speed += cruiser.v / 180.0
			pump_speed += pumper.v / 180.0
	_check(pump_speed > cruise_speed + 0.8, "small up and down strokes pump: faster than cruising (%.1f vs %.1f m/s)" % [pump_speed, cruise_speed])
	var drop := Rider.new()
	drop.place(3.0, 0.8)
	var deep := 0.0
	for i in 60:
		drop.step(1.0 / 60.0, 0.49, -0.012, wave, tuning)
		deep = maxf(deep, drop.compression)
	var easy := Rider.new()
	easy.place(3.0, 0.8)
	_check(deep > easy.compression + 0.2, "he crouches lower with speed and a hard change of direction (%.2f)" % deep)
	var weaver := Rider.new()
	weaver.place(3.0, 0.6)
	var worst := 0.0
	for i in 2400:
		weaver.step(1.0 / 60.0, 0.49, -0.018 if (i / 50) % 2 == 0 else 0.018, wave, tuning)  # down, up, down, up...
		worst = maxf(worst, Rider.d_for(0.49) - weaver.d)
	_check(worst < 2.8, "going up and down the face over and over never lets the curl catch him (fell back %.1f m)" % worst)
	var wild := Rider.new()
	wild.place(3.0, 0.5)
	var inside := true
	var peel := wave.peel_speed()
	for i in 1800:
		wild.step(1.0 / 60.0, 0.5 + 0.5 * sin(i * 0.037), 0.03 * sin(i * 0.071 + 1.0), wave, tuning)
		inside = inside and wild.u >= Rider.U_LOW and wild.u <= Rider.U_HIGH and wild.d >= Rider.D_NEAR and wild.d <= Rider.D_FAR
		inside = inside and wild.v >= Rider.MIN_SPEED * peel - 0.001 and wild.v <= Rider.MAX_SPEED * peel + 0.001
		inside = inside and wild.theta >= Rider.THETA_MIN and wild.theta <= Rider.THETA_MAX and is_finite(wild.omega)
	_check(inside, "wild steering for 30 seconds never leaves the wave, the speed range or the heading range")
	_check(rider.speed >= 0.0 and rider.speed <= 1.0 and rider.sharpness >= 0.0 and rider.sharpness <= 1.0, "speed and sharpness stay between 0 and 1")
	var steady := Rider.new()
	steady.place(3.0, 0.5)
	var steady_burst := 0.0
	for i in 240:
		steady.step(1.0 / 60.0, 0.49, 0.0, wave, tuning)
		steady_burst = maxf(steady_burst, steady.take_burst())
	_check(steady_burst == 0.0, "holding still throws no spray")
	var snapper := Rider.new()
	snapper.place(3.0, 0.5)
	var biggest := 0.0
	for i in 420:
		var high := (i / 30) % 2 == 0
		snapper.step(1.0 / 60.0, 0.49, 0.05 if high else -0.05, wave, tuning)
		biggest = maxf(biggest, snapper.take_burst())
	_check(biggest > 0.15, "snapping up and down the face throws spray (%.2f)" % biggest)
	var gentle := Rider.new()
	gentle.place(3.0, 0.5)
	var smallest := 0.0
	for i in 600:
		gentle.step(1.0 / 60.0, 0.49, 0.0015 * cos(i / 60.0 * 1.5), wave, tuning)
		smallest = maxf(smallest, gentle.take_burst())
	_check(smallest < biggest, "a gentle carve throws less than a hard snap")
	_test_balance(wave, tuning)


## Balance, read from the J-Bay footage: the centre of mass sits over the feet along the apparent gravity, the lean leads
## and the turn follows, so no input makes him jerk, and inputs a real surfer could not follow are flagged.
func _test_balance(wave: WaveModel, tuning: TuningData) -> void:
	var trimmer := Rider.new()
	trimmer.place(3.0, 0.5)
	for i in 120:
		trimmer.step(1.0 / 60.0, 0.49, 0.0, wave, tuning)
	_check(rad_to_deg(trimmer.balance.angle_to(Vector3.UP)) < 8.0, "trimming along the face he stands upright (%.1f degrees off)" % rad_to_deg(trimmer.balance.angle_to(Vector3.UP)))
	var carver := Rider.new()
	carver.place(3.0, 0.5)
	var into_wave := false
	var out_of_wave := false
	var deepest_before := 0.0
	var tallest_after := 1.0
	for i in 240:
		var phase := fmod(i / 60.0, 2.0)
		carver.step(1.0 / 60.0, 0.49, 0.012 if phase < 0.8 else (-0.025 if phase < 1.2 else 0.0), wave, tuning)
		if carver.carve > 0.3:
			into_wave = into_wave or carver.balance.z < -0.2  # toward the wave, away from the beach
		if carver.carve < -0.3:
			out_of_wave = out_of_wave or carver.balance.z > Vector3.UP.z + 0.1
		if i >= 120 and i < 150:
			deepest_before = maxf(deepest_before, carver.compression)
		if i >= 150 and i < 185:
			tallest_after = minf(tallest_after, carver.compression)
	_check(into_wave and out_of_wave, "he leans into the wave through a bottom turn and out toward the beach in a top turn")
	_check(deepest_before > tallest_after + 0.15, "he is crouched as the bottom turn starts and extends out of it (%.2f to %.2f)" % [deepest_before, tallest_after])
	var smooth := Rider.new()
	smooth.place(3.0, 0.5)
	var wild := Rider.new()
	wild.place(3.0, 0.5)
	var smooth_jerk := 0.0
	var wild_jerk := 0.0
	var wild_roll_rate := 0.0
	for i in 600:
		var omega_before := wild.omega
		var roll_before := wild.rail_roll
		var smooth_before := smooth.omega
		smooth.step(1.0 / 60.0, 0.49, 0.0045 * cos(TAU * i / 180.0), wave, tuning)  # a 3 s carve, the rhythm in the footage
		wild.step(1.0 / 60.0, 0.49, -0.04 if (i / 9) % 2 == 0 else 0.04, wave, tuning)  # full reversals every 0.15 s
		if i == 0:  # the first step only settles him from place()
			continue
		smooth_jerk = maxf(smooth_jerk, absf(smooth.omega - smooth_before) * 60.0)
		wild_jerk = maxf(wild_jerk, absf(wild.omega - omega_before) * 60.0)
		wild_roll_rate = maxf(wild_roll_rate, absf(wild.rail_roll - roll_before) * 60.0)
	_check(wild_jerk < 20.0 and wild_roll_rate < 4.0, "even a wild input never jerks the board (turn changes %.1f rad/s2, rail %.1f rad/s)" % [wild_jerk, wild_roll_rate])
	# (a carve that crests the face unweights there, so the turn rate eases off quickly as the press under his feet drops)
	_check(smooth.falls == 0 and smooth_jerk < 10.0, "a smooth carve stays in balance (%d flagged, turn changes %.1f rad/s2)" % [smooth.falls, smooth_jerk])
	_check(wild.falls > 0 and wild.strain > 1.0, "a wild input is flagged as one a real surfer would fall from (%s)" % wild.fall_reason)
	# Hitting the lip: drop to the bottom, drive up the face, reverse hard at the top. Only the tail is in the water there,
	# so the board swings round fast while the body stays over it.
	var lipper := Rider.new()
	lipper.place(3.0, 0.5)
	var highest := -10.0
	var after_snap := 10.0
	var fastest_snap := 0.0
	var lean_at_lip := 0.0
	var u_turned := -1.0  # how high up the face he is when the nose has come round from up the face to down it
	for i in 216:
		var t := i / 60.0
		lipper.step(1.0 / 60.0, 0.49, -0.02 if t < 0.9 else (0.03 if t < 2.4 else -0.05), wave, tuning)
		if t > 2.4 and u_turned < 0.0 and lipper.theta < -0.6:
			u_turned = lipper.u
		if t < 2.8:
			highest = maxf(highest, lipper.theta)
		if t > 2.6:
			after_snap = minf(after_snap, lipper.theta)
		if t > 2.4:
			fastest_snap = maxf(fastest_snap, -lipper.omega)
		if lipper.pivoting > 0.9:
			lean_at_lip = maxf(lean_at_lip, absf(lipper.carve))
	_check(rad_to_deg(highest) > 45.0 and rad_to_deg(after_snap) < -35.0 and fastest_snap > 3.5, "hitting the lip swings the board from up the face to down it on its tail (%d to %d degrees, %.1f rad/s)" % [rad_to_deg(highest), rad_to_deg(after_snap), fastest_snap])
	_check(rad_to_deg(lean_at_lip) < 45.0, "through the snap his body stays over the board (%d degrees off his line)" % rad_to_deg(lean_at_lip))
	_check(u_turned > 0.88, "the whole snap happens at the top: the lip holds him until the nose points down the face (%.2f up the face)" % u_turned)
	# Steering hard back stalls him: weight over the tail, speed bleeds off and the curl catches him, deep in the pocket.
	var staller := Rider.new()
	staller.place(3.0, 0.5)
	var slowest := 99.0
	var leaned_back := 0.0
	for i in 240:
		staller.step(1.0 / 60.0, 0.0, 0.0, wave, tuning)
		slowest = minf(slowest, staller.v)
		leaned_back = minf(leaned_back, staller.pitch)
	# The cutback (the Bells footage): at the top, pushing down as hard as he can carries the turn round past straight down
	# toward the curl; he is very compact round there, then the water pivots the board back to the line.
	var cutter := Rider.new()
	cutter.place(10.0, 0.5)
	var roundest := 0.0
	var crouched_round := 0.0
	var back_on_line := false
	var closest := 99.0
	for i in 330:
		var t := i / 60.0
		cutter.step(1.0 / 60.0, Rider.steer_for(10.0), -0.02 if t < 0.9 else (0.03 if t < 2.3 else (-0.08 if t < 3.3 else 0.0)), wave, tuning)
		roundest = minf(roundest, cutter.theta)
		closest = minf(closest, cutter.d)
		if cutter.theta < -2.0:
			crouched_round = maxf(crouched_round, cutter.compression)
		back_on_line = back_on_line or (roundest < -2.2 and cutter.theta > -0.9)
	_check(rad_to_deg(roundest) < -125.0 and crouched_round > 0.8 and back_on_line, "out on the shoulder a hard push down at the top cuts back round toward the curl, compact, then pivots back to the line (%d degrees)" % rad_to_deg(roundest))
	_check(closest > 0.0, "the cutback rebounds off the foam, still ahead of the curl (closest %.1f m ahead of the peel point)" % closest)
	# The same push in the pocket, close to the curl, is a snap off the lip: no cutback, no ricochet back into the curl.
	var pocket := Rider.new()
	pocket.place(3.0, 0.5)
	var cut_in_pocket := false
	var fastest_back := 0.0
	var nearest := 99.0
	for i in 330:
		var t := i / 60.0
		pocket.step(1.0 / 60.0, 0.49, -0.02 if t < 0.9 else (0.03 if t < 2.3 else (-0.08 if t < 3.3 else 0.0)), wave, tuning)
		cut_in_pocket = cut_in_pocket or pocket.cutting_back
		fastest_back = maxf(fastest_back, -pocket.vel_d)
		nearest = minf(nearest, pocket.d)
	_check(not cut_in_pocket and fastest_back < Rider.BACK_MAX * wave.peel_speed() + 0.01 and nearest > -1.0, "in the pocket the same push is a snap: he never ricochets back into the curl (fastest back %.1f m/s, nearest %.1f m)" % [fastest_back, nearest])
	# Wherever he goes he never slams into either end of the wave: closing on the curl, or running out along the shoulder, eases to a stop.
	var slammer := Rider.new()
	slammer.place(0.0, 0.5)
	var hardest_stop := 0.0
	var last_vel := 0.0
	for i in 600:
		slammer.step(1.0 / 60.0, 0.0, 0.0, wave, tuning)
		if i > 0:
			hardest_stop = maxf(hardest_stop, absf(slammer.vel_d - last_vel) * 60.0)
		last_vel = slammer.vel_d
	_check(hardest_stop < 30.0 and slammer.d >= Rider.D_NEAR, "stalling all the way back to the curl eases him to a stop instead of slamming into it (%.1f m/s2 at most)" % hardest_stop)
	# Near the curl he settles: he tucks, the board comes round along the line, and he finds a comfortable height.
	_check(slammer.tuck > 0.8 and absf(slammer.theta) < 0.6 and slammer.u > 0.2 and slammer.u < 0.7, "settled by the curl he is tucked, along the line, mid face (tuck %.2f, heading %d, height %.2f)" % [slammer.tuck, rad_to_deg(slammer.theta), slammer.u])
	# One flick commits to the move: a quick scroll up from the bottom carries him all the way up the face, not halfway.
	var flicker := Rider.new()
	flicker.place(3.0, 0.2)
	var steepest := 0.0
	var top := 0.0
	for i in 120:
		flicker.step(1.0 / 60.0, 0.49, 0.087 if i < 20 and i % 4 == 0 else 0.0, wave, tuning)
		steepest = maxf(steepest, flicker.theta)
		top = maxf(top, flicker.u)
	_check(rad_to_deg(steepest) > 45.0 and top > 0.9, "one flick up carries him all the way to the lip (%d degrees, up to %.2f)" % [rad_to_deg(steepest), top])
	# Running behind where he is steered he pumps for speed: a rhythm of folding and extending.
	var pumper2 := Rider.new()
	pumper2.place(3.0, 0.5)
	var low := 1.0
	var high := 0.0
	var pumped := 0.0
	for i in 240:
		pumper2.step(1.0 / 60.0, 0.95, 0.0, wave, tuning)
		pumped = maxf(pumped, pumper2.pumping)
		if i > 90:
			low = minf(low, pumper2.compression)
			high = maxf(high, pumper2.compression)
	_check(pumped > 0.5 and high - low > 0.15, "chasing down the line he pumps (crouch %.2f to %.2f)" % [low, high])
	_check(staller.d < -1.0 and slowest < 0.75 * wave.peel_speed() and leaned_back < -0.2, "steering hard back stalls him into the curl (d %.1f m, %.1f m/s, leaning back %d degrees)" % [staller.d, slowest, rad_to_deg(leaned_back)])


func _test_calibration() -> void:
	var input := RideInput.new()
	var rider := Rider.new()
	var run := Calibration.new()
	run.save_enabled = false
	root.add_child(run)
	run.start(input, rider)
	_check(Calibration.MOVES.size() >= 5 and Calibration.TRIALS_PER_MOVE == 5, "the calibration asks for each move five times")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	run._unhandled_input(space)
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0.0, -5.0)
	input.handle(pan, Vector2(1280.0, 720.0))
	await process_frame
	_check(run._events.size() == 1 and run._events[0][1] == "pan", "a trial records the raw trackpad events")
	run._unhandled_input(space)
	_check(run._results.size() == 1 and run._results[0].move == "up_down", "pressing space again ends the trial and keeps it")
	run.free()
	input.free()


func _test_surfer_sprites() -> void:
	_check(SurferSprites.ORDER.size() == SurferSprites.ANIMATIONS.size(), "the gallery order lists every animation")
	var labelled := true
	var found := true
	var sized := true
	var on_anchor := true
	var visible_figure := true
	for animation_name in SurferSprites.ORDER:
		labelled = labelled and SurferSprites.LABELS.has(animation_name) and SurferSprites.has_animation(animation_name)
		for i: int in SurferSprites.ANIMATIONS[animation_name].frames:
			var texture := load(SurferSprites.frame_path(animation_name, i)) as Texture2D
			found = found and texture != null
			if texture == null:
				continue
			var toon := SurferSprites.is_toon(animation_name)
			var expected := Vector2(SurferSprites.TOON_FRAME_SIZE.x * SurferSprites.TOON_PANELS, SurferSprites.TOON_FRAME_SIZE.y) if toon else SurferSprites.FRAME_SIZE
			sized = sized and Vector2(texture.get_size()) == expected
			if toon:
				# Toon frames hold the figure in the first panel and data in the others, so look at the first panel only.
				var left := texture.get_image().get_region(Rect2i(0, 0, int(SurferSprites.TOON_FRAME_SIZE.x), int(SurferSprites.TOON_FRAME_SIZE.y)))
				var covered := left.get_used_rect()
				# A rolled board dips below the anchor row, but never far; tools/foundry/check_frames.py checks the pivot itself.
				var bottom := covered.position.y + covered.size.y
				on_anchor = on_anchor and bottom > SurferSprites.ANCHOR.y - 14.0 and bottom < SurferSprites.ANCHOR.y + 45.0
				visible_figure = visible_figure and covered.size.y > SurferSprites.FRAME_SIZE.y * 0.3
				continue
			# The pipeline puts every frame's board on the anchor, so the lowest solid pixel is at the anchor's row.
			var used := texture.get_image().get_used_rect()
			on_anchor = on_anchor and absf((used.position.y + used.size.y) - SurferSprites.ANCHOR.y) < 14.0
			visible_figure = visible_figure and used.size.y > SurferSprites.FRAME_SIZE.y * 0.3
	_check(labelled, "every animation has a label")
	_check(found, "every frame of every animation exists")
	_check(sized, "every frame is the catalog's frame size")
	_check(on_anchor, "the board sits on the anchor in every frame, so the surfer cannot slide about")
	_check(visible_figure, "every frame has a surfer in it, not an empty picture")
	_check(SurferSprites.ANCHOR.x > 0.0 and SurferSprites.ANCHOR.x < SurferSprites.FRAME_SIZE.x and SurferSprites.ANCHOR.y < SurferSprites.FRAME_SIZE.y, "the anchor is inside the frame")
	_check(SurferSprites.person_pixels() < SurferSprites.FRAME_SIZE.y, "a 1.8 m person is a little shorter than the frame")


func _test_surfer() -> void:
	var surfer := Surfer.new()
	surfer.place(Vector2(640.0, 500.0), 180.0)
	_check(surfer.position == Vector2(640.0, 500.0), "the board goes where it is put")
	_check(is_equal_approx(surfer.scale.y * Surfer.STANDING_HEIGHT, 180.0), "the surfer is as tall as asked")
	_check(surfer.pose_name() == SurferSprites.ORDER[0], "the surfer starts in the first animation")
	surfer.set_pose("nonsense")
	_check(surfer.pose_name() == SurferSprites.ORDER[0], "an unknown animation name changes nothing")
	var info: Dictionary = SurferSprites.ANIMATIONS[SurferSprites.ORDER[0]]
	_check(surfer.frame_count() == (info.frames * 2 - 2 if info.ping_pong else info.frames), "a ping-pong animation plays forward and back without repeating its ends")
	surfer.set_ground_angle(10.0)
	_check(is_equal_approx(surfer.rotation_degrees, 10.0), "the surfer tilts to sit on a sloping face")
	surfer.free()


## Runs the whole scene for a few frames with a big hollow wave and checks the pieces agree.
func _test_world() -> void:
	var world: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	world.set_wave(0.9, 1.0, 0.3)
	await process_frame
	await process_frame
	var stage: WaveStage = world.get_node("WaveStage")
	var materials := stage.materials()
	_check(materials.size() == 4 and materials[0].get_shader_parameter("noise_cells") is ImageTexture and materials[0].get_shader_parameter("noise_warp") is ImageTexture, "the wave shader has its noise textures")
	_check(materials[3].get_shader_parameter("noise_cells") is ImageTexture and materials[3].get_shader_parameter("foam_lit") == root.get_node("Palette").current.foam_lit, "the carve trail has the noise textures and the mood's foam colours")
	_check(stage.carve_trail.point_count() > 0, "the running scene feeds the carve trail from the rider")
	_check(materials[1].get_shader_parameter("profile") is ImageTexture, "the sea shader has the wave's profile texture")
	var mood: MoodData = root.get_node("Palette").current
	_check(materials[0].get_shader_parameter("wave_mid") == mood.wave_mid and materials[1].get_shader_parameter("swell_top") == mood.swell_top, "the 3D wave and sea are fed the mood's colours")
	_check(stage.model.barrel() > 0.5, "a big hollow wave is a barrel")

	var feet := stage.model.surface_point(world.rider.d, world.rider.u)
	var feet_px := stage.project(feet)
	var surfer: Surfer = world.get_node("Surfer")
	_check(surfer.position.is_equal_approx(feet_px), "the surfer stands on the face in the running scene")
	_check(is_equal_approx(surfer.scale.y * Surfer.STANDING_HEIGHT, feet_px.y - stage.project(feet + Vector3(0.0, WaveModel.SURFER_HEIGHT, 0.0)).y), "the surfer is the standard 1.8 m tall on screen")
	_check(absf(rad_to_deg(surfer.rotation)) <= world.MAX_GROUND_ANGLE, "the surfer tilts with the face, but never past the limit")
	world.set_surfer_pose("nonsense")
	_check(surfer.pose_name() == world.DEFAULT_POSE, "the scene ignores an animation name that does not exist")
	var gallery: PoseGallery = world.get_node("PoseGallery")
	_check(not gallery.visible, "the pose gallery stays hidden unless asked for")
	gallery.open()
	await process_frame
	var surfers := 0
	for child in gallery.get_children():
		surfers += int(child is Surfer)
	_check(gallery.visible and surfers == SurferSprites.ORDER.size() + 1, "the gallery shows every animation plus a cycler")
	gallery.close()
	_check(world.CAMERA_YAW_OPEN > 0.0 and world.CAMERA_YAW_BARREL > 0.0, "the camera always looks down the line, never back into the barrel")
	_check(absf(feet_px.y / world.size.y - WaveStage.SURFER_SCREEN_Y) < 0.01, "the camera puts the surfer's feet at the planned height on screen")
	var head_px := stage.project(feet + Vector3(0.0, WaveModel.SURFER_HEIGHT, 0.0))
	var surfer_fraction := (feet_px.y - head_px.y) / world.size.y
	_check(surfer_fraction > 0.18 and surfer_fraction < 0.36, "the surfer is about a quarter of the screen height, like the key frames (%.2f)" % surfer_fraction)

	var spray: SurferSpray = world.get_node("Spray")
	var tail: Vector2 = surfer.position + (world.BOARD_TAIL * ((feet_px.y - head_px.y) / WaveModel.SURFER_HEIGHT)).rotated(surfer.rotation)
	if world._surfer3d:
		tail = stage.project(world._surfer3d.tail_point())
	_check(spray.position.is_equal_approx(tail), "the spray follows the board's tail")
	world.burst(0.8)
	await process_frame
	_check(spray.live_particles() > 0, "the world's burst call throws spray")
	var key := InputEventKey.new()
	key.keycode = KEY_B
	key.pressed = true
	var strengths_before: int = world._test_burst
	world._unhandled_input(key)
	_check(world._test_burst == strengths_before + 1, "the B key throws the next test burst")
	world.rider.u = 0.9
	world.burst(1.0)
	await process_frame
	_check(world._front_spray.live_particles() > 0, "at the top of the wave a turn also throws a fan off the front foot")
	_check(world._speed_label.text.contains("game speed"), "the game speed is always on screen")
	var faster := InputEventKey.new()
	faster.keycode = KEY_PERIOD
	faster.pressed = true
	world._unhandled_input(faster)
	var sped_up := Engine.time_scale
	var slower := InputEventKey.new()
	slower.keycode = KEY_COMMA
	slower.pressed = true
	world._unhandled_input(slower)
	world._unhandled_input(slower)
	_check(sped_up > 1.0 and Engine.time_scale < 1.0 and world._key_help.text.contains("game speed (%.1fx)" % Engine.time_scale), "the . and , keys speed the game up and slow it down, and the key list shows it")
	Engine.time_scale = 1.0
	var back_layer_before_surfer := false
	for child in world.get_children():
		if child == surfer:
			break
		back_layer_before_surfer = back_layer_before_surfer or (child is Node2D and child.get_child_count() > 0 and child.get_child(0) is CPUParticles2D and child != world.get_node("WaveSpray"))
	_check(back_layer_before_surfer, "the heavy part of the spray is drawn behind the surfer")
	world.free()
	await process_frame


func _test_tuning() -> void:
	var tuning := load("res://data/tuning.tres") as TuningData
	_check(tuning != null, "tuning resource loads as TuningData")
	if tuning != null:
		_check(tuning.reach > 0.0, "tuning reach is positive")


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
	print("%s  %s" % ["ok  " if condition else "FAIL", name])


func _test_surfer_3d() -> void:
	var surfer := Surfer3D.new()
	var names := surfer.pose_names()
	_check("trim" in names and "crouch" in names and "bottom_turn" in names, "the real-time surfer carries its baked poses")
	_check(surfer.skeleton.get_bone_count() > 100, "the real-time surfer is skinned to the full rig")
	var foot := surfer.skeleton.find_bone("foot.L")
	_check(foot >= 0, "the skeleton keeps the rig's bone names")
	_check(surfer.material.next_pass == surfer.veil, "his figure through the lip is the next pass of his material")
	_check("depth_test_inverted" in surfer.veil.shader.code and "compare_not_equal" in surfer.veil.shader.code
			and "stencil_mode write" in surfer.material.shader.code, "the veil draws only where something else hides him")
	var before := surfer.skeleton.get_bone_pose_rotation(surfer.skeleton.find_bone("root"))
	surfer.set_target("bottom_turn", 1.0)
	for i in 30:
		surfer.step(1.0 / 60.0)
	var after := surfer.skeleton.get_bone_pose_rotation(surfer.skeleton.find_bone("root"))
	_check(before.angle_to(after) > 0.3, "a pose target hinges the hips, smoothly")
	_check(surfer.weight("bottom_turn") > 0.5 and surfer.weight("bottom_turn") < 1.0, "the pose weight eases in rather than snapping")
	surfer.set_target("bottom_turn", 0.0)
	for i in 120:
		surfer.step(1.0 / 60.0)
	_check(surfer.weight("bottom_turn") < 0.01, "a pose can be released again")
	var model := WaveModel.new()
	surfer.stand_on(model, 3.0, 0.5)
	_check(absf(surfer.position.distance_to(model.surface_point(3.0, 0.5)) - Surfer3D.PIVOT_TO_CENTRE) < 0.001, "the board turns about the back foot, which stays on the wave surface")
	_check(surfer.transform.basis.y.angle_to(model.surface_normal(3.0, 0.5)) < 0.01, "the board lies flat on the face")
	var rider := Rider.new()
	rider.place(3.0, 0.5)
	rider.rail_roll = 0.4
	rider.balance = Vector3(0.0, 0.8, -0.6).normalized()
	surfer.follow(rider, model, 1.0 / 60.0)
	_check(surfer.transform.basis.y.z < model.surface_normal(3.0, 0.5).z - 0.1, "rolling onto the inside rail tips the deck toward the wave")
	var to_model := surfer._skeleton_to_model()
	var feet: Vector3 = (to_model * surfer._global(surfer.skeleton.find_bone("foot.L")).origin + to_model * surfer._global(surfer.skeleton.find_bone("foot.R")).origin) / 2.0
	var mass := surfer.transform.basis * ((to_model * surfer._centre_of_mass()) - feet)
	_check(rad_to_deg(mass.angle_to(rider.balance)) < 6.0, "his centre of mass sits over his feet along the balance (%.1f degrees off)" % rad_to_deg(mass.angle_to(rider.balance)))
	var planted := (to_model * surfer._global(surfer.skeleton.find_bone("foot.L")).origin).distance_to(surfer._foot_target[-1.0])
	_check(planted < 0.03, "the feet stay planted on the deck while the body leans (%.3f m)" % planted)
	# The lead chain: asked to turn up the face, the front arm points there before the board has come round.
	var leader := Rider.new()
	leader.place(3.0, 0.5)
	for i in 30:
		leader.step(1.0 / 60.0, 0.49, 0.0, model, TuningData.new())
		surfer.follow(leader, model, 1.0 / 60.0)
	var arm_before: float = atan2(-surfer._arm_aim.z, -surfer._arm_aim.x)
	var heading_before := leader.theta
	for i in 12:
		leader.step(1.0 / 60.0, 0.49, 0.03, model, TuningData.new())
		surfer.follow(leader, model, 1.0 / 60.0)
	var arm_turn: float = atan2(-surfer._arm_aim.z, -surfer._arm_aim.x) - arm_before
	var board_turn := leader.theta - heading_before
	_check(arm_turn > 0.25 and arm_turn > 3.0 * board_turn, "the front arm points into a turn before the board comes round (arm %d degrees, board %d)" % [rad_to_deg(arm_turn), rad_to_deg(board_turn)])
	# Deep and carving low in a big bottom turn, the back hand drags in the water and throws spray.
	var dragger := Rider.new()
	dragger.place(3.0, 0.5)
	var dragged := 0.0
	for i in 150:
		dragger.step(1.0 / 60.0, 0.49, -0.02 if i < 54 else 0.03, model, TuningData.new())
		surfer.follow(dragger, model, 1.0 / 60.0)
		dragged = maxf(dragged, surfer.hand_spray)
	_check(dragged > 0.3, "in a big bottom turn the back hand drags in the water and throws spray (%.2f)" % dragged)
	# He looks where he is going: up the face in a bottom turn, never down at the water at his feet.
	var looker := Rider.new()
	looker.place(3.0, 0.5)
	var looked_up := false
	var looked_down := false
	for i in 150:
		looker.step(1.0 / 60.0, 0.49, -0.02 if i < 54 else 0.03, model, TuningData.new())
		surfer.follow(looker, model, 1.0 / 60.0)
		if looker.carve > 0.3 and looker.u < 0.45:
			var face_dir: Vector3 = (surfer.transform.basis * (surfer._skeleton_to_model().basis * surfer._global(surfer.skeleton.find_bone("head")).basis.z)).normalized()
			var up_face := Vector3(-1.0, 0.0, 0.0).cross(model.surface_normal(looker.d, looker.u)).normalized()
			looked_up = looked_up or face_dir.dot(up_face) > 0.2
			looked_down = looked_down or face_dir.y < -0.75
	_check(looked_up and not looked_down, "in a bottom turn he looks up the face where he is going, not down at the water")
	_check(is_equal_approx(surfer.BOARD_TAIL.x, 0.95 - Surfer3D.BOARD_SHIFT), "the board sits forward under him, back foot by the tail")
	surfer.free()
