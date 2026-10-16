shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Spray blowing off the crest: flat white ovals drifting up and back, like the droplets in the key
// frames. A thin curtain mesh (see WaveMist) only gives them somewhere to be; the shader cuts it into
// dots, dense where the wave is breaking and sparse along the unbroken crest. Near the crest the
// droplets are in the wave's shadow and go violet; higher up they catch the low sun, cream and peach,
// and a few of them glint.
//
// Vertex colour red = how much mist there is here. UV = (meters along the crest, 0 at the crest to 1 at the top).

uniform float time = 0.0;
uniform vec3 wind = vec3(0.8, 1.5, 0.0);        // meters per second: along the crest (back), up
uniform vec4 foam_lit : source_color;
uniform vec4 foam_shade : source_color;
uniform vec4 sun_glint : source_color;

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

// Feathering: a crest down the line that is about to pitch (a racecourse or a bowl coming) blows more spray, and taller.
const float FEATHER = 0.8;
const float FEATHER_RISE = 0.9;     // meters the curtain stands taller

varying vec3 wpos;
varying float amount;

void vertex() {
	float d = -VERTEX.x;
	float feather = reef_kind(d, 2.0) * smoothstep(4.0, 8.0, d);
	VERTEX.yz *= reef_scale(d);
	VERTEX.y += UV.y * feather * FEATHER_RISE * swell;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	amount = clamp(COLOR.r * (1.0 + FEATHER * feather) + 0.12 * feather, 0.0, 1.0) * smoothstep(0.05, 0.5, swell);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float up = UV.y;
	float thin = pow(1.0 - up, 1.4);
	vec2 dir = normalize(wind.xy);
	vec2 across = vec2(-dir.y, dir.x);

	float dots = 0.0;
	vec3 col = foam_lit.rgb;
	float glints = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float cells_per_meter = layer == 0 ? 6.0 : 11.0;
		float carried = layer == 0 ? 1.0 : 1.5;
		vec2 g = (wpos.xy - wind.xy * time * carried) * cells_per_meter;
		vec2 cell = floor(g);
		vec2 local = fract(g) - 0.5;
		float h1 = hash21(cell + float(layer) * 17.0);
		float h2 = hash21(cell + 5.3);
		float h3 = hash21(cell + 9.1);
		// Droplets live a moment, then another one appears: the cell's roll changes a few times a second.
		float flicker = hash21(cell + floor(time * 2.5 + h1 * 4.0));
		local -= (vec2(h1, h2) - 0.5) * 0.55;
		float present = step(flicker, amount * thin * (layer == 0 ? 0.62 : 0.42));
		vec2 stretch = vec2(dot(local, dir), dot(local, across));
		float size = mix(0.30, 0.15, up) * (0.55 + 0.9 * h3) * (layer == 0 ? 1.0 : 0.65);
		float oval = (1.0 - smoothstep(size * 0.78, size, length(stretch * vec2(0.55, 1.35)))) * present;
		if (oval > dots) {
			dots = oval;
			glints = step(0.86, h2) * step(0.5, fract(time * 2.2 + h1 * 9.0));
			col = mix(foam_shade.rgb, foam_lit.rgb, 0.3 + 0.7 * smoothstep(0.0, 0.5, up + (h3 - 0.5) * 0.4));
			col = mix(col, sun_glint.rgb, smoothstep(0.35, 0.8, up) * 0.45);
		}
	}
	if (dots < 0.5) {
		discard;
	}
	ALBEDO = mix(col, sun_glint.rgb, glints);
}
