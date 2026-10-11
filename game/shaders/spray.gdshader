shader_type canvas_item;
// Stippled spray: white ovals stretched along the radius, dense near `centre` and thinning out,
// like the spray in the key frames. The dots re-roll a few times a second, like hand-animated
// spray. `centre` is in height units (x runs 0..aspect, y runs 0..1).

uniform float aspect = 1.7778;
uniform float time = 0.0;
uniform vec2 centre = vec2(1.0, 0.4);
uniform float radius = 0.28;
uniform float strength = 1.0;

uniform vec4 foam_lit : source_color;

const float SPRAY_CELLS = 36.0;          // dots per screen height

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float stipple(vec2 p) {
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
	float dots = stipple(vec2(UV.x * aspect, UV.y)) * strength;
	if (dots <= 0.0) {
		discard;
	}
	COLOR = vec4(foam_lit.rgb, dots);
}
