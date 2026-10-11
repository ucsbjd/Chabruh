shader_type canvas_item;
// Foreground swell: the near water in front of the wave, with slow crests sliding past.

uniform float aspect = 1.7778;
uniform float layout_aspect = 1.7778;
uniform float time = 0.0;
uniform float travel = 0.0;

uniform vec4 swell_top : source_color;
uniform vec4 swell_deep : source_color;
uniform vec4 swell_line : source_color;

const float TOP_Y = 0.845;
const float SCROLL = 1.35;      // near water slides faster than the far scenery

float crest_y(float x) {
	float u = x - travel * SCROLL;
	return TOP_Y + 0.016 * sin(u * 5.0 + time * 0.7) + 0.009 * sin(u * 13.0 - time * 0.9);
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * aspect + layout_aspect * 0.5, UV.y);
	float s = p.y - crest_y(p.x);
	float edge = fwidth(s) * 1.2 + 1e-5;
	float alpha = smoothstep(-edge, edge, s);
	if (alpha <= 0.0) {
		discard;
	}

	float depth = clamp((p.y - TOP_Y) / (1.0 - TOP_Y), 0.0, 1.0);
	vec3 col = mix(swell_top.rgb, swell_deep.rgb, pow(depth, 0.7));

	float crest_line = 1.0 - smoothstep(0.0, 0.012, s);
	float second_y = 0.045 + 0.012 * sin((p.x - travel * SCROLL) * 3.0 - time * 0.5);
	float second_line = 1.0 - smoothstep(0.0, 0.007, abs(s - second_y));
	col = mix(col, swell_line.rgb, max(crest_line * 0.85, second_line * 0.35));

	COLOR = vec4(col, alpha);
}
