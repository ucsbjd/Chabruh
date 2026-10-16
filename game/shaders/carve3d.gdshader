shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// The foam the board cuts into the face (see WaveCarveTrail), in the wave's own foam look: flat cream clumps shaded violet,
// sprinkled with white speckle. A fresh gouge is a solid band with ragged edges; as it ages it opens into the lace of the
// foam cells and thins away.
//
// Vertex colour: r = height up the face, g = age (0 new, 1 gone), a = how hard the rail cut here (already faded where the
// whitewater or the lip takes the foam). UV = meters along the board's path through the water and across the track, so
// the pattern stays on the water. UV2.x = across the track, -1 to 1.

uniform sampler2D noise_cells : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_warp : filter_linear_mipmap, repeat_enable;
uniform vec4 foam_lit : source_color;
uniform vec4 foam_shade : source_color;

void fragment() {
	float h = COLOR.r;
	float age = COLOR.g;
	float strength = COLOR.a;
	float across = UV2.x;

	// Solid in the middle of the cut, thinning to its sides and with age; the noise tears the edge into rags and clumps.
	float rag = texture(noise_warp, UV * vec2(0.9, 1.4)).r - 0.5;
	float clump = texture(noise_warp, UV * 0.35 + vec2(0.31, 0.62)).r - 0.5;
	float body = (1.0 - across * across) * strength * (1.0 - age * 0.5);
	float cover = body * 1.6 + rag * 0.6 + clump * 0.35;
	// Older foam keeps only the edges of its cells: the lace.
	float cell = texture(noise_cells, UV * 0.45).r;
	cover -= smoothstep(0.2, 0.9, age) * smoothstep(0.04, 0.3, cell) * 1.1;
	float edge = max(fwidth(cover), 0.002);
	float coverage = smoothstep(0.5 - edge, 0.5 + edge, cover);
	if (coverage < 0.01) {
		discard;
	}

	// Lit cream or violet shade, in flat patches: the fresh core of the cut catches the light; its sides, the foam low on
	// the face and old foam are in shade.
	float shade = texture(noise_warp, UV * 0.25 + vec2(0.7, 0.2)).r * 0.9 + (1.0 - h) * 0.3 + age * 0.45 + abs(across) * 0.45 - 0.4;
	shade = smoothstep(0.38, 0.62, shade);
	vec3 col = mix(foam_lit.rgb, foam_shade.rgb, shade);
	float speckle = step(0.56, texture(noise_cells, UV * 2.2).r);
	col = mix(col, foam_lit.rgb, speckle * shade * 0.85);

	ALBEDO = col;
	ALPHA = coverage;
}
