shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// The sea as a real plane running to the horizon, so its lines converge in perspective. Deep
// teal with a lace of pale cell-edge lines like fan A, haze toward the horizon, and white water
// around the base of the wave where it is breaking.

uniform sampler2D profile : filter_linear, repeat_disable;
uniform sampler2D noise_cells : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_warp : filter_linear_mipmap, repeat_enable;
uniform float time = 0.0;
uniform float scroll = 0.0;          // meters the sea has slid past the camera
uniform float profile_d0 = -30.0;
uniform float profile_d1 = 60.0;

uniform vec4 swell_top : source_color;
uniform vec4 swell_deep : source_color;
uniform vec4 swell_line : source_color;
uniform vec4 sea_horizon : source_color;
uniform vec4 foam_lit : source_color;
uniform vec4 foam_shade : source_color;
uniform vec4 wave_shadow : source_color;
uniform vec4 sun_glint : source_color;
uniform vec4 sky_peach : source_color;
uniform vec3 sun_dir = vec3(-0.62, 0.20, -0.76);

// The reef (SectionDirector): two sections as (centre d, half width, height gain, kind), where kind is 0 wall,
// 1 channel, 2 racecourse, 3 bowl; and the swell, the whole wave's height as a factor (near 0 in a lull).
// WaveModel.section_key does the same sums for the rider, so keep them together.
uniform vec4 reef_a = vec4(1000.0, 0.001, 0.0, 0.0);
uniform vec4 reef_b = vec4(1000.0, 0.001, 0.0, 0.0);
uniform float swell = 1.0;

float reef_weight(vec4 r, float d) {
	return 1.0 - smoothstep(0.0, 1.0, abs(d - r.x) / r.y);
}

// How much of the wave's height the reef and the swell give it at d.
float reef_scale(float d) {
	return swell * (1.0 + reef_weight(reef_a, d) * reef_a.z + reef_weight(reef_b, d) * reef_b.z);
}

// How much bowl (kind 3) or of the kinds from `kind` up (2: racecourse and bowl) there is at d, 0 to 1.
float reef_kind(float d, float kind) {
	return min(reef_weight(reef_a, d) * step(kind - 0.5, reef_a.w) + reef_weight(reef_b, d) * step(kind - 0.5, reef_b.w), 1.0);
}

// One section's reef patch: mottled in the reef's own place, so it travels with the section.
float reef_patch(vec4 r, float d, float z) {
	float mottle = texture(noise_warp, vec2(d - r.x, z) * 0.055 + 0.17).r;
	return reef_weight(r, d) * step(2.5, r.w) * smoothstep(0.30, 0.55, mottle);
}

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = length(cam - wpos);

	// Slow broad swells in colour, with the sea sliding past the camera.
	vec2 flow = wpos.xz - vec2(scroll, 0.0);
	float broad = texture(noise_warp, flow * 0.012).r;
	vec3 col = mix(swell_deep.rgb, swell_top.rgb, smoothstep(0.30, 0.70, broad));

	// The sea reflects the sky in big patches: violet and pink under the horizon haze, gold where
	// the sun's light lands, like the foreground of the key frame.
	float tint = texture(noise_warp, flow * 0.02 + vec2(0.37, 0.11)).r;
	float far_amount = smoothstep(14.0, 120.0, dist);
	vec3 sky_violet_patch = mix(foam_shade.rgb, sea_horizon.rgb, 0.45);
	col = mix(col, sky_violet_patch, smoothstep(0.52, 0.72, tint) * 0.55 * far_amount);
	col = mix(col, sun_glint.rgb, smoothstep(0.72, 0.86, texture(noise_warp, flow * 0.045 + 0.6).r) * 0.45 * far_amount);

	// A lace of pale cell-edge lines, thinning out with distance so they never shimmer.
	float cell = texture(noise_cells, flow * 0.03).r;
	float width = 0.035 + fwidth(cell) * 1.4;
	float lace = (1.0 - smoothstep(0.0, width, cell)) * (1.0 - smoothstep(70.0, 260.0, dist));
	col = mix(col, mix(swell_line.rgb, foam_lit.rgb, 0.55), lace * 0.7);

	// Shadow and foam around the base of the wave, where the profile says it is.
	float d = clamp((-wpos.x - profile_d0) / (profile_d1 - profile_d0), 0.0, 1.0);
	vec4 pr = texture(profile, vec2(d, 0.5));
	float from_trough = wpos.z - pr.g;                      // beach side of the wave's base is positive
	float calm_sea = smoothstep(0.1, 0.6, swell);           // in a lull there is no wave to shade or foam the water
	float near_wave = (1.0 - smoothstep(0.0, 4.0 + pr.r, abs(from_trough))) * calm_sea;
	col = mix(col, wave_shadow.rgb, near_wave * 0.35);

	// A shallow reef bowl shows through the water in front of the wave before the wave reaches it: soft dark violet
	// patches with warm coral in them.
	float wd = -wpos.x;
	float reef = max(reef_patch(reef_a, wd, wpos.z), reef_patch(reef_b, wd, wpos.z));
	reef *= smoothstep(-1.0, 2.0, from_trough) * (1.0 - smoothstep(8.0, 26.0, from_trough));
	float coral = smoothstep(0.55, 0.75, texture(noise_warp, wpos.xz * 0.13 + vec2(0.4, 0.8)).r);
	col = mix(col, mix(mix(foam_shade.rgb, wave_shadow.rgb, 0.45), sky_peach.rgb, coral * 0.5), 0.6 * reef);

	float ragged = texture(noise_warp, flow * 0.09).r - 0.5;
	float lumps = texture(noise_warp, flow * 0.25 + vec2(time * 0.08, 0.0)).r - 0.5;   // the churned water is choppy, not smooth
	float wash = (1.0 - smoothstep(0.0, 0.7 + pr.a * 4.2, from_trough + ragged * (1.2 + pr.a * 3.0) + lumps * pr.a * 2.5)) * step(0.0, from_trough + 0.5);
	float foam_amount = wash * (0.15 + 0.85 * pr.a) * calm_sea;
	float clump = smoothstep(0.0, 0.5, texture(noise_warp, flow * 0.12).r);
	col = mix(col, mix(foam_lit.rgb, foam_shade.rgb, (1.0 - clump) * 0.6), clamp(foam_amount * step(0.5, pr.r) * 1.4, 0.0, 1.0));

	// The sun's glitter: flat dashes of light on the sea below the sun, sparse and short nearby and
	// long and dense toward the horizon, like the glitter path in the sky layer.
	vec3 away = (wpos - cam) / dist;
	float toward_sun = dot(normalize(away.xz), normalize(-sun_dir.xz));
	float path = smoothstep(0.985, 0.999, toward_sun);
	float dash_noise = texture(noise_warp, vec2(flow.x * 0.35, flow.y * 0.9 + time * 0.05)).r;
	float dash = smoothstep(0.62, 0.70, dash_noise) * path * smoothstep(8.0, 60.0, dist);
	col = mix(col, sun_glint.rgb, dash * (1.0 - smoothstep(120.0, 420.0, dist) * 0.5));

	// The far sea fades into the horizon colour.
	col = mix(col, sea_horizon.rgb, smoothstep(60.0, 420.0, dist));
	ALBEDO = col;
}
