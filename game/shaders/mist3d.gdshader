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

varying vec3 wpos;
varying float amount;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	amount = COLOR.r;
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
