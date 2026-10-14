shader_type canvas_item;
// Draws the foundry's packed surfer frames (tools/foundry, docs/foundry.md) in the wave's flat look.
// A frame texture is three panels wide, each one frame wide (the sprite quad is drawn three times as wide, so
// everything right of the first panel is discarded and only read as data):
//   panel 0: R skin, G shorts, B board weights, A coverage
//   panel 1: R hair, G tattoo ink, B trim weights
//   panel 2: R stripe A, G stripe B, B light
// Every colour comes from the current mood (uniforms share the MoodData property names, so world.gd feeds
// them); nothing is baked into the frames.

uniform vec4 surfer_skin : source_color = vec4(0.85, 0.54, 0.38, 1.0);
uniform vec4 surfer_shorts : source_color = vec4(1.0, 0.44, 0.38, 1.0);
uniform vec4 surfer_board : source_color = vec4(0.96, 0.91, 0.82, 1.0);
uniform vec4 surfer_hair : source_color = vec4(0.89, 0.75, 0.45, 1.0);
uniform vec4 surfer_ink : source_color = vec4(0.16, 0.11, 0.18, 1.0);
uniform vec4 surfer_trim : source_color = vec4(0.25, 0.82, 0.77, 1.0);
uniform vec4 surfer_stripe_a : source_color = vec4(1.0, 0.24, 0.55, 1.0);
uniform vec4 surfer_stripe_b : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform vec4 surfer_light : source_color = vec4(1.0, 0.85, 0.63, 1.0);
uniform vec4 surfer_shade : source_color = vec4(0.38, 0.38, 0.59, 1.0);
uniform vec4 surfer_rim : source_color = vec4(1.0, 0.82, 0.48, 1.0);

// Where the light value is cut into shade, middle and lit bands, and how soft the cuts are.
uniform float shade_below = 0.18;
uniform float lit_above = 0.5;
uniform float band_softness = 0.03;
// The sunward silhouette edge: how many texture pixels wide, and how strong.
uniform float rim_pixels = 2.0;
uniform float rim_strength = 0.85;

void fragment() {
	// Plain expressions, no arrays, loops or discard: the simplest code that mobile GPUs all compile.
	// Stay inside panel 0 so filtering never reads the data panels as colour.
	highp float third = 1.0 / 3.0;
	highp float margin = 0.5 * TEXTURE_PIXEL_SIZE.x;
	highp vec2 uv = vec2(clamp(UV.x, margin, third - margin), UV.y);
	vec4 p0 = texture(TEXTURE, uv);
	vec4 p1 = texture(TEXTURE, uv + vec2(third, 0.0));
	vec4 p2 = texture(TEXTURE, uv + vec2(2.0 * third, 0.0));

	vec3 base = surfer_skin.rgb * p0.r + surfer_shorts.rgb * p0.g + surfer_board.rgb * p0.b
			+ surfer_hair.rgb * p1.r + surfer_ink.rgb * p1.g + surfer_trim.rgb * p1.b
			+ surfer_stripe_a.rgb * p2.r + surfer_stripe_b.rgb * p2.g;
	float total = p0.r + p0.g + p0.b + p1.r + p1.g + p1.b + p2.r + p2.g;
	base /= max(total, 0.0001);

	float lit = smoothstep(lit_above - band_softness, lit_above + band_softness, p2.b);
	float not_shade = smoothstep(shade_below - band_softness, shade_below + band_softness, p2.b);
	// Shade is a violet-tinted, slightly darker version of the colour, never grey or black.
	vec3 shaded = mix(base * 0.7, surfer_shade.rgb, 0.4);
	vec3 sunny = mix(base, surfer_light.rgb, 0.3) * 1.08;
	vec3 colour = mix(shaded, base, not_shade);
	colour = mix(colour, sunny, lit);
	// The rim is where the figure is covered but the pixels toward the sun (up and left) are empty.
	float toward_sun = texture(TEXTURE, uv + rim_pixels * TEXTURE_PIXEL_SIZE * vec2(-1.0, -1.0)).a;
	float rim = clamp(p0.a - toward_sun, 0.0, 1.0);
	colour = mix(colour, surfer_rim.rgb, rim * rim_strength);
	// Everything right of the first panel is data, not picture.
	COLOR = vec4(colour, p0.a * step(UV.x, third));
}
