shader_type canvas_item;
// The wave, seen from the beach, in the style of the key frames (kling-04 and kling-05): flat jade
// bands, a thin warm rim line along the crest, a few pale cell-edge veins, cream foam with violet
// shade and a stippled spray cloud at the lip. The surfer rides right to left, so the wall builds
// to the left (ahead) and breaks to the right (behind).
//
// Shapes come from the WaveModel. The model bakes its profile into the `profile` texture: red is
// the crest height, green the base line, blue the lip throw, alpha the foam, all as a function of
// d, the distance ahead of the peel point. This shader only turns those numbers into pixels.
//
// Layout is in height units: x runs 0..layout_aspect, y runs 0..1 (down).

uniform float aspect = 1.7778;
uniform float layout_aspect = 1.7778;
uniform float time = 0.0;
uniform float travel = 0.0;

uniform sampler2D profile : filter_linear, repeat_disable;
uniform sampler2D noise_cells : filter_linear, repeat_enable;
uniform sampler2D noise_warp : filter_linear, repeat_enable;
uniform float peel_x = 1.2;
uniform float profile_d0 = -1.6;
uniform float profile_d1 = 4.0;
uniform float barrel = 0.0;
uniform float hollowness = 0.5;
uniform float wave_height = 0.4;

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

const float LIP_END = 2.2;               // angle from straight up where the lip's tip ends
const float SPRAY_CELLS = 36.0;          // spray dots per screen height

vec4 profile_at(float d) {
	float u = clamp((d - profile_d0) / (profile_d1 - profile_d0), 0.0, 1.0);
	return texture(profile, vec2(u, 0.5));
}

// A flat step with a softly blended edge: the posterised look of the key frames.
float band(float x, float edge, float soft) {
	return smoothstep(edge - soft, edge + soft, x);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Stippled spray: white ovals stretched along the radius, dense near `centre` and thinning out.
// The dots re-roll a few times a second, like hand-animated spray.
float stipple(vec2 p, vec2 centre, float radius) {
	vec2 rel = p - centre;
	float dist = length(rel);
	if (dist > radius || radius <= 0.0) {
		return 0.0;
	}
	vec2 dir = rel / max(dist, 1e-4);
	float seed = floor(time * 8.0);
	vec2 g = rel * SPRAY_CELLS;
	vec2 cell = floor(g);
	vec2 local = fract(g) - 0.5;
	local -= (vec2(hash21(cell + seed), hash21(cell + seed + 7.3)) - 0.5) * 0.5;
	float fall = 1.0 - dist / radius;
	float present = step(hash21(cell + seed + 3.1), pow(fall, 1.2) * 0.95);
	vec2 along = vec2(dot(local, dir), dot(local, vec2(-dir.y, dir.x)));
	float grow = mix(0.9, 1.5, dist / radius);
	float oval = 1.0 - smoothstep(0.14 * grow, 0.28 * grow, length(along * vec2(0.5, 1.5)));
	return present * oval;
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * aspect + layout_aspect * 0.5, UV.y);
	float d = peel_x - p.x;                              // ahead of the peel point is to the left
	vec4 pr = profile_at(d);
	float crest_h = pr.r;
	float base_y = pr.g;
	float foam_amt = pr.a;

	// The crest line rolls a little instead of being ruler-straight, and turns ragged where the
	// wall has collapsed into foam.
	float roll = (0.007 * sin(p.x * 2.3 + 0.8) + 0.004 * sin(p.x * 5.1 - 1.7)) * (crest_h / 0.4);
	float rag = (texture(noise_warp, vec2(p.x * 1.6 - travel * 0.5, 0.31)).r - 0.5) * 0.10 * smoothstep(0.1, 0.8, foam_amt);
	float crest_y = base_y - crest_h + roll + rag;

	// The hood: a circle over the break that, with the hollow cut out of it, becomes the lip.
	vec4 pr0 = profile_at(0.0);
	float hood_r = wave_height * 0.62 * barrel;
	vec2 hood_c = vec2(peel_x + 0.30 * hood_r, pr0.g - pr0.r + 0.92 * hood_r);
	vec2 q = p - hood_c;
	float ang = atan(q.x, -q.y);                         // 0 straight up, positive toward the right
	float s_hood = (barrel > 0.02 && ang < LIP_END) ? hood_r - length(q) : -1.0;

	float s_wall = p.y - crest_y;
	float s = max(s_wall, s_hood);
	float edge = fwidth(s) * 1.2 + 1e-5;
	float alpha = smoothstep(-edge, edge, s);

	// Spray cloud over the lip: spills outside the wave as well as over it.
	float mist_radius = min(wave_height * (0.70 + 0.30 * barrel), 0.30);
	vec2 mist_c = vec2(peel_x + 0.06, pr0.g - pr0.r - 0.01);
	float dots = stipple(p, mist_c, mist_radius);

	if (alpha <= 0.0) {
		if (dots <= 0.0) {
			discard;
		}
		COLOR = vec4(foam_lit.rgb, dots);
	} else {
		// Position up the face: 0 at the base line, 1 at the crest.
		float h = clamp((base_y - p.y) / max(crest_h, 0.02), 0.0, 1.0);

		// Flat jade bands with softly wobbling edges.
		float wob = texture(noise_warp, vec2(p.x * 0.25 - travel * 0.5, h * 0.5)).r - 0.5;
		float hb = h + wob * 0.06;
		vec3 col = wave_shadow.rgb;
		col = mix(col, wave_deep.rgb, band(hb, 0.12, 0.07));
		col = mix(col, wave_mid.rgb, band(hb, 0.40, 0.09));
		col = mix(col, wave_light.rgb, band(hb, 0.72, 0.10));

		// A few fine dark streaks hanging from the crest.
		float cx = (p.x - travel * 0.8) * 120.0;
		float lane = floor(cx);
		float streak_len = hash21(vec2(lane, 9.0));
		float streak = step(0.90, hash21(vec2(lane, 3.0))) * step(1.0 - streak_len * 0.9, h);
		col = mix(col, wave_shadow.rgb, streak * (1.0 - smoothstep(0.0, 0.2, abs(fract(cx) - 0.5))) * 0.45);

		// Pale cell-edge veins in the lower face, like the lace in fan A.
		float cell = texture(noise_cells, vec2((p.x - travel * 0.45) * 0.5, h * 0.45 + 0.1)).r;
		float vein = (1.0 - smoothstep(0.0, 0.12, cell)) * (1.0 - smoothstep(0.1, 0.7, h));
		col = mix(col, mix(foam_shade.rgb, foam_lit.rgb, 0.35), vein * 0.5);

		// Below the base line the water is deep jade with flat aqua streaks.
		float below = smoothstep(0.0, 0.012, p.y - base_y);
		float lines = smoothstep(0.93, 0.97, sin((p.y - base_y) * 70.0 + wob * 8.0 + p.x * 1.5));
		col = mix(col, wave_deep.rgb, below);
		col = mix(col, wave_glint.rgb, below * lines * 0.45);

		// Foam spills down the face from the crest as the wave breaks: cream on top, violet
		// shade lower down, with a ragged, streaky edge like the crashing lip in fan A.
		float drip = texture(noise_warp, vec2(p.x * 5.0, 0.7)).r - 0.5;
		float foam_line = 1.0 - foam_amt * 1.25 + drip * 0.35;
		float foam_mask = band(h, foam_line, 0.02) * step(0.01, foam_amt);
		float clump = smoothstep(0.02, 0.10, texture(noise_cells, vec2(p.x * 0.8, p.y * 1.6 - travel * 0.2)).r);
		float patches = smoothstep(0.52, 0.72, texture(noise_warp, vec2(p.x * 0.9, p.y * 1.3)).r);
		float shade = clamp((1.0 - smoothstep(foam_line, foam_line + 0.30, h)) * 0.75 + (1.0 - clump) * 0.45 + patches * 0.5, 0.0, 1.0);
		col = mix(col, mix(foam_lit.rgb, foam_shade.rgb, shade), foam_mask);

		// The barrel, when the wave is hollow enough: a thin crescent lip over a dark hollow.
		if (barrel > 0.02) {
			vec2 hq = p - (hood_c + vec2(0.30, 0.20) * hood_r);
			float hd = (hq.y < 0.0 ? length(hq) : length(vec2(hq.x, hq.y * 0.55))) - 0.56 * hood_r;
			if (hd > 0.0 && s_hood > 0.0) {
				float lip = clamp(hd / (hd + s_hood), 0.0, 1.0);
				vec3 lip_col = mix(wave_mid.rgb, wave_light.rgb, smoothstep(0.0, 0.5, lip));
				lip_col = mix(lip_col, foam_lit.rgb, smoothstep(0.7, 1.0, lip) * 0.9);
				float down = 1.0 - smoothstep(hood_c.y - 0.06 * hood_r, hood_c.y + 0.5 * hood_r, p.y);
				col = mix(col, lip_col, mix(down, 1.0, smoothstep(0.0, 0.15 * hood_r, q.x)));
			}
			float hollow_edge = fwidth(hd) * 1.2 + 1e-5;
			float hollow = 1.0 - smoothstep(-hollow_edge, hollow_edge, hd);
			float depth = clamp(-hd / (0.56 * hood_r), 0.0, 1.0);
			vec3 inner = mix(hollow_dark.rgb, hollow_glow.rgb, pow(depth, 2.4) * 0.8);
			float spot = exp(-length((hq - vec2(0.0, 0.10 * hood_r)) * vec2(1.0, 0.9)) / (0.11 * hood_r));
			col = mix(col, mix(inner, hollow_glow.rgb, spot * 0.9), hollow * barrel);

			// A cream foam edge along the outer rim of the lip, heaviest where it falls on the right.
			float swing = clamp(ang / 1.5708, -1.0, 1.0) * 0.5 + 0.5;
			float rim_w = mix(0.004, 0.05, smoothstep(0.3, 1.0, swing)) * (hood_r / 0.3);
			float jag = 0.65 + 0.35 * sin(ang * 38.0 + time * 1.5) * sin(ang * 17.0 - time);
			float rim_foam = (1.0 - smoothstep(rim_w * jag - 0.004, rim_w * jag + 0.004, s_hood)) * step(q.y, 0.0) * step(0.0, s_hood);
			col = mix(col, foam_lit.rgb, rim_foam * barrel);
		}

		// The warm rim line along the clean crest, but not along the edge of the foam.
		col = mix(col, wave_rim.rgb, (1.0 - smoothstep(0.0, 0.010, s)) * (1.0 - smoothstep(0.15, 0.6, foam_amt)));

		col = mix(col, foam_lit.rgb, dots);
		COLOR = vec4(col, max(alpha, dots));
	}
}
