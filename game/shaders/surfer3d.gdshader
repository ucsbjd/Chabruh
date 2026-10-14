shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
// The real-time surfer in the wave's flat look: the same mood colours as the sprite shader (surfer_toon.gdshader),
// but the light bands come from the surface normal and the sun, and the rim from the view angle. Each vertex
// carries its region number in the vertex colour (red = region / 10): 0 skin, 1 shorts, 2 board, 3 hair, 5 trim,
// 6 and 7 the board's stripes. Because he is drawn inside the wave's own 3D stage, the lip and the mist can pass
// in front of him.

uniform vec4 surfer_skin : source_color = vec4(0.85, 0.54, 0.38, 1.0);
uniform vec4 surfer_shorts : source_color = vec4(1.0, 0.44, 0.38, 1.0);
uniform vec4 surfer_board : source_color = vec4(0.96, 0.91, 0.82, 1.0);
uniform vec4 surfer_hair : source_color = vec4(0.89, 0.75, 0.45, 1.0);
uniform vec4 surfer_trim : source_color = vec4(0.25, 0.82, 0.77, 1.0);
uniform vec4 surfer_stripe_a : source_color = vec4(1.0, 0.24, 0.55, 1.0);
uniform vec4 surfer_stripe_b : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform vec4 surfer_light : source_color = vec4(1.0, 0.85, 0.63, 1.0);
uniform vec4 surfer_shade : source_color = vec4(0.38, 0.38, 0.59, 1.0);
uniform vec4 surfer_rim : source_color = vec4(1.0, 0.82, 0.48, 1.0);

// The sun, as the direction toward it in the stage's world (x along the crest, y up, z toward the camera).
uniform vec3 key_dir = vec3(-0.55, 0.70, 0.45);
uniform float shade_below = -0.05;
uniform float lit_above = 0.35;
uniform float band_softness = 0.05;
uniform float rim_width = 0.38;
uniform float rim_strength = 0.85;

varying float region;
varying vec3 world_normal;

float is_region(float r, float k) {
	return 1.0 - step(0.5, abs(r - k));
}

void vertex() {
	region = COLOR.r * 10.0;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 base = surfer_skin.rgb * is_region(region, 0.0)
			+ surfer_shorts.rgb * is_region(region, 1.0)
			+ surfer_board.rgb * is_region(region, 2.0)
			+ surfer_hair.rgb * is_region(region, 3.0)
			+ surfer_trim.rgb * is_region(region, 5.0)
			+ surfer_stripe_a.rgb * is_region(region, 6.0)
			+ surfer_stripe_b.rgb * is_region(region, 7.0);
	float known = is_region(region, 0.0) + is_region(region, 1.0) + is_region(region, 2.0) + is_region(region, 3.0)
			+ is_region(region, 5.0) + is_region(region, 6.0) + is_region(region, 7.0);
	base = mix(surfer_skin.rgb, base, step(0.5, known));

	vec3 n = normalize(world_normal);
	float l = dot(n, normalize(key_dir));
	float lit = smoothstep(lit_above - band_softness, lit_above + band_softness, l);
	float not_shade = smoothstep(shade_below - band_softness, shade_below + band_softness, l);
	// Shade is a violet-tinted, slightly darker version of the colour, never grey or black.
	vec3 shaded = mix(base * 0.7, surfer_shade.rgb, 0.4);
	vec3 sunny = mix(base, surfer_light.rgb, 0.3) * 1.08;
	vec3 colour = mix(shaded, base, not_shade);
	colour = mix(colour, sunny, lit);
	// A rim line along the silhouette on the side facing the sun.
	float edge = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width, 1.0, edge) * smoothstep(-0.1, 0.4, l);
	ALBEDO = mix(colour, surfer_rim.rgb, rim * rim_strength);
}
