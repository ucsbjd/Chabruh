shader_type canvas_item;
// Draws the foundry's packed surfer frames (tools/foundry, docs/foundry.md) in the wave's flat look.
// The frame texture is two frames wide. Left half: skin, shorts and board weights in RGB, coverage in A.
// Right half: light (R), rim (G), hair weight (B). The sprite quad is drawn twice as wide as the figure,
// so the right half is thrown away and only read as data. Every colour comes from the current mood
// (the uniforms share the MoodData property names, so world.gd feeds them); nothing is baked in.

uniform vec4 surfer_skin : source_color = vec4(0.85, 0.54, 0.38, 1.0);
uniform vec4 surfer_shorts : source_color = vec4(1.0, 0.24, 0.55, 1.0);
uniform vec4 surfer_board : source_color = vec4(0.78, 0.95, 0.21, 1.0);
uniform vec4 surfer_hair : source_color = vec4(0.23, 0.14, 0.09, 1.0);
uniform vec4 surfer_light : source_color = vec4(1.0, 0.85, 0.63, 1.0);
uniform vec4 surfer_shade : source_color = vec4(0.38, 0.38, 0.59, 1.0);
uniform vec4 surfer_rim : source_color = vec4(1.0, 0.82, 0.48, 1.0);

// Where the light value is cut into shade, middle and lit bands, and how soft the cuts are.
uniform float shade_below = 0.18;
uniform float lit_above = 0.5;
uniform float band_softness = 0.03;
uniform float rim_strength = 0.85;

void fragment() {
	// Stay inside the left half so filtering never reads the data half as colour.
	float margin = 0.5 * TEXTURE_PIXEL_SIZE.x;
	vec2 uv = vec2(clamp(UV.x, margin, 0.5 - margin), UV.y);
	if (UV.x > 0.5) {
		discard;
	}
	vec4 left = texture(TEXTURE, uv);
	vec4 right = texture(TEXTURE, uv + vec2(0.5, 0.0));

	vec4 w = vec4(left.rgb, right.b);
	w /= max(w.x + w.y + w.z + w.w, 0.0001);
	vec3 base = surfer_skin.rgb * w.x + surfer_shorts.rgb * w.y + surfer_board.rgb * w.z + surfer_hair.rgb * w.w;

	float lit = smoothstep(lit_above - band_softness, lit_above + band_softness, right.r);
	float lit_or_mid = smoothstep(shade_below - band_softness, shade_below + band_softness, right.r);
	// Shade is a violet-tinted, slightly darker version of the colour, never grey or black.
	vec3 shaded = mix(base * 0.7, surfer_shade.rgb, 0.4);
	vec3 mid = base;
	vec3 sunny = mix(base, surfer_light.rgb, 0.3) * 1.08;
	vec3 colour = mix(shaded, mid, lit_or_mid);
	colour = mix(colour, sunny, lit);
	colour = mix(colour, surfer_rim.rgb, clamp(right.g, 0.0, 1.0) * rim_strength);
	COLOR = vec4(colour, left.a);
}
