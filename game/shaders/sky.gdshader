shader_type canvas_item;
// Backdrop: sky gradient, striped sun and halo above the horizon; open sea and the sun's
// glitter path below it. Layout is in height units: x runs 0..layout_aspect, y runs 0..1.

uniform float aspect = 1.7778;
uniform float layout_aspect = 1.7778;
uniform float time = 0.0;
uniform float horizon = 0.40;
uniform vec2 sun_pos = vec2(0.64, 0.30);

uniform vec4 sky_top : source_color;
uniform vec4 sky_violet : source_color;
uniform vec4 sky_pink : source_color;
uniform vec4 sky_peach : source_color;
uniform vec4 sky_horizon : source_color;
uniform vec4 sun : source_color;
uniform vec4 sun_low : source_color;
uniform vec4 sun_glow : source_color;
uniform vec4 haze : source_color;
uniform vec4 sea_horizon : source_color;
uniform vec4 sea_deep : source_color;
uniform vec4 sun_glint : source_color;

const float SUN_RADIUS = 0.28;       // a huge, low sun, as in the key frames
const float STRIPE_COUNT = 8.0;

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

vec3 sky_gradient(float t) {
	vec3 c = mix(sky_top.rgb, sky_violet.rgb, smoothstep(0.0, 0.30, t));
	c = mix(c, sky_pink.rgb, smoothstep(0.25, 0.55, t));
	c = mix(c, sky_peach.rgb, smoothstep(0.50, 0.80, t));
	return mix(c, sky_horizon.rgb, smoothstep(0.75, 1.0, t));
}

// The sun is a disc whose lower half is cut by stripes that widen toward the bottom.
vec3 paint_sun(vec3 col, vec2 p) {
	float d = distance(p, sun_pos);
	float sy = (p.y - sun_pos.y) / SUN_RADIUS;            // -1 at the top of the disc, 1 at the bottom
	float edge = fwidth(d) * 1.2 + 1e-5;
	float disc = 1.0 - smoothstep(SUN_RADIUS - edge, SUN_RADIUS + edge, d);

	float k = clamp((sy + 0.1) / 1.1, 0.0, 1.0);            // 0 where stripes begin, 1 at the bottom
	float rows = fract((sy + 1.0) * STRIPE_COUNT);
	float gap = mix(0.0, 0.62, k);
	float row_edge = fwidth(rows) * 1.2 + 1e-5;
	float cut = mix(1.0, smoothstep(gap - row_edge, gap + row_edge, rows), step(-0.1, sy));

	vec3 body = mix(sun.rgb, sun_low.rgb, smoothstep(-0.7, 1.0, sy));
	return mix(col, body, disc * cut);
}

vec3 paint_sky(vec2 p) {
	float t = p.y / horizon;
	vec3 col = sky_gradient(t);
	col = mix(col, haze.rgb, smoothstep(0.55, 1.0, t) * 0.35);
	col += sun_glow.rgb * exp(-distance(p, sun_pos) * 4.5) * 0.45;
	return paint_sun(col, p);
}

// Dashes of sunlight on the water below the sun, wider and sparser toward the viewer.
float glitter(vec2 p) {
	float depth = p.y - horizon;
	float width = 0.02 + depth * 0.30;
	float row_pos = pow(depth, 0.7) * 30.0 + time * 0.25;
	float row = floor(row_pos);
	float jitter = (hash11(row) - 0.5) * width * 0.9;
	float half_len = width * (0.30 + 0.70 * hash11(row + 13.0));
	float dash = 1.0 - smoothstep(half_len * 0.8, half_len, abs(p.x - sun_pos.x - jitter));
	float band = 1.0 - smoothstep(0.30, 0.46, fract(row_pos));
	float flicker = 0.65 + 0.35 * sin(time * 2.0 + row * 3.1);
	return dash * band * flicker;
}

vec3 paint_sea(vec2 p) {
	float t = (p.y - horizon) / (1.0 - horizon);
	vec3 col = mix(sea_horizon.rgb, sea_deep.rgb, pow(t, 0.55));
	float reach = 1.0 - smoothstep(0.0, 0.5, t);
	return mix(col, sun_glint.rgb, glitter(p) * (0.35 + 0.65 * reach));
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * aspect + layout_aspect * 0.5, UV.y);
	COLOR = vec4(p.y < horizon ? paint_sky(p) : paint_sea(p), 1.0);
}
