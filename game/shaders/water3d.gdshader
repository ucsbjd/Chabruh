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
uniform vec3 sun_dir = vec3(-0.62, 0.20, -0.76);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = length(cam - wpos);

	// Slow broad swells in colour, with the sea sliding past the camera.
	vec2 flow = wpos.xz - vec2(scroll, 0.0);
	float swell = texture(noise_warp, flow * 0.012).r;
	vec3 col = mix(swell_deep.rgb, swell_top.rgb, smoothstep(0.30, 0.70, swell));

	// A lace of pale cell-edge lines, thinning out with distance so they never shimmer.
	float cell = texture(noise_cells, flow * 0.04).r;
	float width = 0.13 + fwidth(cell) * 2.2;
	float lace = (1.0 - smoothstep(0.0, width, cell)) * (1.0 - smoothstep(70.0, 260.0, dist));
	col = mix(col, swell_line.rgb, lace * 0.75);

	// Shadow and foam around the base of the wave, where the profile says it is.
	float d = clamp((-wpos.x - profile_d0) / (profile_d1 - profile_d0), 0.0, 1.0);
	vec4 pr = texture(profile, vec2(d, 0.5));
	float from_trough = wpos.z - pr.g;                      // beach side of the wave's base is positive
	float near_wave = 1.0 - smoothstep(0.0, 4.0 + pr.r, abs(from_trough));
	col = mix(col, wave_shadow.rgb, near_wave * 0.35);

	float ragged = texture(noise_warp, flow * 0.09).r - 0.5;
	float wash = (1.0 - smoothstep(0.0, 0.7 + pr.a * 2.6, from_trough + ragged * 1.2)) * step(0.0, from_trough + 0.5);
	float foam_amount = wash * (0.15 + 0.85 * pr.a);
	float clump = smoothstep(0.02, 0.10, texture(noise_cells, flow * 0.16).r);
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
