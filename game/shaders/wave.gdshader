shader_type canvas_item;
// The wave, seen from the beach. The surfer rides right to left, so the open shoulder is on the
// left and the curl, lip and barrel are on the right, behind them.
//
// Layout is in height units: x runs 0..aspect, y runs 0..1 (down). The silhouette is a sloping
// wall that rises toward the right, topped by a circular hood. The hollow is an egg shape set
// off-centre inside the hood, so the lip between them is a crescent: thick where it joins the
// wall and tapering to a tip on the right. Everything else is flat bands of colour plus foam.

uniform float aspect = 1.7778;
uniform float layout_aspect = 1.7778;
uniform float time = 0.0;
uniform float travel = 0.0;

uniform vec4 wave_shadow : source_color;
uniform vec4 wave_deep : source_color;
uniform vec4 wave_mid : source_color;
uniform vec4 wave_light : source_color;
uniform vec4 wave_glint : source_color;
uniform vec4 hollow_dark : source_color;
uniform vec4 hollow_glow : source_color;
uniform vec4 foam_lit : source_color;
uniform vec4 foam_shade : source_color;

const float BASE_Y = 0.80;                       // where the face meets the trough
const float SHOULDER_Y = 0.66;                   // top of the wall at the far left
const float RIGHT_MARGIN = 0.45;                 // hood centre sits this far from the right edge
const float HOOD_R = 0.29;                       // outer radius of the curl
const float HOOD_CY = 0.43;                      // height of the hood's centre
const vec2 HOLLOW_OFFSET = vec2(0.04, 0.05);     // hollow centre relative to the hood centre
const float HOLLOW_R = 0.18;
const float HOLLOW_SQUASH = 0.55;                // stretches the hollow downward into an egg
const float LIP_END = 2.2;                       // angle from straight up where the lip's tip ends

// Top edge of the wall left of the curl: gentle at the shoulder, steeper as it builds.
float wall_top(float x, float x_l) {
	float t = clamp(x / x_l, 0.0, 1.0);
	return mix(SHOULDER_Y, HOOD_CY, pow(t, 1.9));
}

// Signed distance to the hollow: negative inside. Round on top, stretched into an egg below.
float hollow_dist(vec2 qi) {
	return (qi.y < 0.0 ? length(qi) : length(vec2(qi.x, qi.y * HOLLOW_SQUASH))) - HOLLOW_R;
}

// Flat-ish bands up the face: violet-blue shadow, deep teal, turquoise, then glowing light.
vec3 water_bands(float h) {
	float b = pow(h, 2.6);
	b = mix(b, floor(b * 6.0) / 6.0, 0.22);
	vec3 c = mix(wave_shadow.rgb, wave_deep.rgb, smoothstep(0.0, 0.30, b));
	c = mix(c, wave_mid.rgb, smoothstep(0.25, 0.62, b));
	c = mix(c, wave_light.rgb, smoothstep(0.58, 0.90, b));
	return mix(c, wave_glint.rgb, smoothstep(0.88, 1.0, b));
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * aspect + layout_aspect * 0.5, UV.y);
	float hood_x = layout_aspect - RIGHT_MARGIN;
	float x_l = max(hood_x - HOOD_R, 0.25);             // left edge of the curl
	vec2 q = p - vec2(hood_x, HOOD_CY);
	float r = length(q);

	// Silhouette: wall under its top edge, the hood circle (up to where the lip's tip ends), and a
	// foam bank that slopes away to the right. Positive means inside.
	float ang = atan(q.x, -q.y);                          // 0 straight up, positive toward the right
	float bank_slope = 0.14 * smoothstep(hood_x + HOOD_R - 0.02, hood_x + HOOD_R + 0.22, p.x);
	float top_y = p.x < x_l ? wall_top(p.x, x_l) : HOOD_CY + bank_slope;
	float s_body = p.y - top_y;
	float s_hood = ang < LIP_END ? HOOD_R - r : -1.0;
	float s = max(s_body, s_hood);
	float edge = fwidth(s) * 1.2 + 1e-5;
	float alpha = smoothstep(-edge, edge, s);
	if (alpha <= 0.0) {
		discard;
	}

	// How far up the face this pixel is, 0 at the trough and 1 at the crest. Past the curl's left
	// edge the face keeps rising so there is no seam where the hood begins.
	float rise = smoothstep(x_l, x_l + 0.08, p.x) * 0.10;
	float face_top = (p.x < x_l ? top_y : HOOD_CY) - rise;
	float h = clamp((BASE_Y - p.y) / max(BASE_Y - face_top, 0.05), 0.0, 1.0);
	vec3 col = water_bands(h);

	// Slow ripples flowing up the face, drifting with the travel of the camera.
	float ripple = sin(h * 34.0 - time * 1.1 + sin((p.x - travel * 0.9) * 7.0) * 1.5);
	col = mix(col, wave_light.rgb, smoothstep(0.88, 1.0, ripple) * 0.18 * (1.0 - h * 0.5));
	col = mix(col, wave_shadow.rgb, smoothstep(0.90, 1.0, -ripple) * 0.14);

	// The hollow and the shadow its lip throws on the face beside it.
	vec2 qi = p - (vec2(hood_x, HOOD_CY) + HOLLOW_OFFSET);
	float hd = hollow_dist(qi);
	col = mix(col, wave_shadow.rgb, (1.0 - smoothstep(0.0, 0.14, hd)) * 0.55);

	// White water behind the curl, in lumps of lit foam and violet shade. It sits behind the lip
	// and never over the hollow.
	float hollow_edge = fwidth(hd) * 1.2 + 1e-5;
	float hollow = 1.0 - smoothstep(-hollow_edge, hollow_edge, hd);
	float bank = smoothstep(hood_x + HOLLOW_R - 0.01, hood_x + HOLLOW_R + 0.05, p.x) * step(HOOD_CY - 0.02, p.y);
	float lump = 0.5 + 0.5 * sin(p.x * 34.0 + time * 1.1 + sin(p.y * 20.0) * 1.6) * sin(p.y * 27.0 - time * 0.8);
	float bank_shade = smoothstep(HOOD_CY, BASE_Y, p.y);
	vec3 bank_col = mix(foam_lit.rgb, foam_shade.rgb, 0.15 + 0.5 * bank_shade);
	bank_col = mix(bank_col, foam_lit.rgb, smoothstep(0.55, 0.85, lump) * 0.8);
	col = mix(col, bank_col, bank * (1.0 - hollow));

	// The lip: a crescent of water over the hollow, deep teal on its underside and glowing where it
	// is thin and lit through. Below the hollow's middle it fades into the face on the left, and
	// hangs down as a tip on the right.
	if (hd > 0.0 && s_hood > 0.0) {
		float lip = clamp(hd / (hd + s_hood), 0.0, 1.0);        // 0 at the hollow, 1 at the outer rim
		vec3 lip_col = mix(wave_deep.rgb, wave_mid.rgb, smoothstep(0.0, 0.25, lip));
		lip_col = mix(lip_col, wave_light.rgb, smoothstep(0.20, 0.75, lip));
		lip_col = mix(lip_col, wave_glint.rgb, smoothstep(0.70, 1.0, lip) * 0.8);
		float fade = mix(1.0 - smoothstep(HOOD_CY - 0.06, HOOD_CY + 0.14, p.y), 1.0, smoothstep(0.0, 0.15, q.x));
		col = mix(col, lip_col, fade);
	}

	// Inside the hollow: dark violet at the rim, glowing aqua toward the light at the far end.
	float depth = clamp(-hd / HOLLOW_R, 0.0, 1.0);
	vec3 inner = mix(hollow_dark.rgb, hollow_glow.rgb, pow(depth, 2.6) * 0.8);
	float spot = exp(-length((qi - vec2(0.0, 0.12)) * vec2(1.0, 0.9)) * 9.0);
	inner = mix(inner, hollow_glow.rgb, spot * 0.9);
	inner += hollow_glow.rgb * 0.05 * (0.5 + 0.5 * sin(hd * 70.0 - time * 0.9)) * (1.0 - depth);
	inner = mix(inner, wave_light.rgb, smoothstep(-0.035, 0.0, hd) * (1.0 - smoothstep(-0.10, 0.06, qi.y)) * 0.45);
	col = mix(col, inner, hollow);

	// Foam along the top edge of the wall, thickening as the wave gets closer to breaking.
	float build = clamp(p.x / x_l, 0.0, 1.0);
	float wobble = 0.5 * sin(p.x * 55.0 - time * 1.3) + 0.5 * sin(p.x * 23.0 + time * 0.8);
	float crest_w = (0.006 + 0.040 * build * build) * (0.75 + 0.25 * wobble);
	float crest_foam = (1.0 - smoothstep(crest_w - 0.003, crest_w + 0.003, s_body)) * step(p.x, x_l);

	// Foam along the outer rim of the hood, heaviest where the lip falls on the right.
	float swing = clamp(ang / 1.5708, -1.0, 1.0) * 0.5 + 0.5;
	float rim_w = mix(0.012, 0.085, smoothstep(0.30, 1.0, swing));
	float jag = 0.65 + 0.35 * sin(ang * 38.0 + time * 1.5) * sin(ang * 17.0 - time);
	float rim_foam = (1.0 - smoothstep(rim_w * jag - 0.004, rim_w * jag + 0.004, s_hood)) * step(q.y, 0.0);

	float foam = max(crest_foam, rim_foam);
	col = mix(col, mix(foam_lit.rgb, foam_shade.rgb, 0.25 * (1.0 - swing)), foam);

	// A wash of foam where the face meets the trough, fading out toward the low shoulder.
	float base_y = BASE_Y - 0.025 + 0.012 * sin(p.x * 17.0 - travel * 1.2 + time);
	float clumps = 0.5 + 0.5 * sin(p.x * 19.0 - travel * 1.1) * sin(p.x * 7.0 + time * 0.4 + 1.3);
	float wash = smoothstep(base_y - 0.015, base_y + 0.01, p.y) * smoothstep(0.35, 1.0, build) * mix(0.35, 1.0, clumps);
	col = mix(col, mix(wave_light.rgb, foam_lit.rgb, 0.55), wash * 0.5);

	COLOR = vec4(col, alpha);
}
