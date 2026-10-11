shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// The wave's body, flat-shaded in the style of the key frames (kling-04 and kling-05). The mesh
// is a real 3D shape, so perspective, the curl of the lip and the barrel's window all come from
// the geometry. This shader only turns the geometry into a few flat jade bands, a warm rim line,
// cream foam with violet shade, and a dark glowing hollow.
//
// Vertex colour: r = height up the wave, g = foam, b = depth inside the barrel, a = how thin
// (translucent) the water is. UV = (meters along the outline, meters along the crest).

uniform sampler2D noise_cells : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_warp : filter_linear_mipmap, repeat_enable;
uniform float time = 0.0;
uniform vec3 sun_dir = vec3(-0.62, 0.20, -0.76);   // toward the sun: ahead, a little up, offshore

uniform vec4 wave_shadow : source_color;
uniform vec4 wave_deep : source_color;
uniform vec4 wave_mid : source_color;
uniform vec4 wave_light : source_color;
uniform vec4 wave_glint : source_color;
uniform vec4 wave_rim : source_color;
uniform vec4 hollow_dark : source_color;
uniform vec4 hollow_glow : source_color;
uniform vec4 foam_lit : source_color;
uniform vec4 foam_shade : source_color;
uniform vec4 sea_horizon : source_color;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// A flat step with a softly blended edge: the posterised look of the key frames.
float band(float x, float edge, float soft) {
	return smoothstep(edge - soft, edge + soft, x);
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - wpos;
	float dist = length(to_cam);
	vec3 v = to_cam / dist;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	float h = COLOR.r;
	float foam = COLOR.g;
	float cav = COLOR.b;
	float thin = COLOR.a;

	// Whitewater is cut into a ragged, streaky edge: notches hang from its top like drips.
	float streaks = texture(noise_warp, UV * vec2(0.03, 0.55)).r;
	float notch = foam * smoothstep(0.72, 1.0, h) * (0.30 + streaks * 1.2);
	if (notch > 0.62) {
		discard;
	}

	// Backlit: faces that look at the camera are in shade, and thin water glows with light
	// shining through it.
	float lit = dot(n, normalize(sun_dir)) * 0.5 + 0.5;
	float warp = texture(noise_warp, UV * vec2(0.035, 0.03)).r - 0.5;
	float tone = clamp(0.06 + h * 0.84 + (lit - 0.5) * 0.18 + thin * 0.28 - cav * 0.30 + warp * 0.12, 0.0, 1.0);
	vec3 col = wave_shadow.rgb;
	col = mix(col, wave_deep.rgb, band(tone, 0.14, 0.07));
	col = mix(col, wave_mid.rgb, band(tone, 0.40, 0.09));
	col = mix(col, wave_light.rgb, band(tone, 0.68, 0.10));
	col = mix(col, wave_glint.rgb, band(tone, 0.92, 0.04));

	// Fine dark streaks hanging from the crest, and pale cell-edge veins in the lower face.
	float drip = step(0.80, texture(noise_warp, vec2(UV.y * 0.55, 0.37)).r) * smoothstep(0.55, 0.95, h) * (1.0 - cav);
	col = mix(col, wave_shadow.rgb, drip * 0.45);
	float cell = texture(noise_cells, UV * 0.05).r;
	float vein = (1.0 - smoothstep(0.0, 0.10 + fwidth(cell) * 2.0, cell)) * (1.0 - smoothstep(0.1, 0.8, h)) * (1.0 - cav);
	col = mix(col, mix(foam_shade.rgb, foam_lit.rgb, 0.4), vein * 0.7);

	// Inside the barrel: dark violet-navy, glowing where light shines through the thin lip.
	col = mix(col, hollow_dark.rgb, cav * 0.80);
	// The tube glows where the wall is thin and up under the lip, and stays dark low down, so the
	// hollow has depth: a bright mouth, a dark throat.
	float glow = clamp(smoothstep(0.05, 0.6, thin) + smoothstep(0.50, 0.95, h) * 0.7, 0.0, 1.0);
	col = mix(col, hollow_glow.rgb, cav * glow * 0.9);

	// Foam: cream clumps with violet shade.
	float clump = smoothstep(0.02, 0.10, texture(noise_cells, UV * 0.22 + vec2(0.0, time * 0.01)).r);
	// Where foam begins the edge hangs down the face in vertical drips, like the crashing lip in fan A.
	float drips = texture(noise_warp, vec2(UV.x * 0.02, UV.y * 0.5)).r - 0.5;
	float blotch = texture(noise_warp, UV * 0.09).r - 0.5;
	float foam_mask = smoothstep(0.5 - 0.015, 0.5 + 0.015, foam + drips * 0.9 * (1.0 - h * 0.4) + blotch * 0.25);
	float shade = clamp((1.0 - clump) * 0.5 + (1.0 - h) * 0.45 + smoothstep(0.55, 0.75, texture(noise_warp, UV * 0.03).r) * 0.4, 0.0, 1.0);
	col = mix(col, mix(foam_lit.rgb, foam_shade.rgb, shade), foam_mask);

	// The warm rim line along steep silhouettes, and a bright line along the top of the crest.
	float fresnel = 1.0 - clamp(dot(n, v), 0.0, 1.0);
	float steep = 1.0 - smoothstep(0.55, 0.85, n.y);
	float rim = smoothstep(0.76, 0.88, fresnel) * steep * smoothstep(0.15, 0.4, h);
	float crest_line = smoothstep(0.45, 0.8, n.y) * smoothstep(0.86, 0.98, h);
	float no_foam = 1.0 - smoothstep(0.05, 0.4, foam);
	col = mix(col, wave_rim.rgb, max(rim, crest_line) * no_foam);

	// Far parts fade into the haze.
	col = mix(col, sea_horizon.rgb, smoothstep(45.0, 240.0, dist) * 0.85);

	ALBEDO = col;
}
