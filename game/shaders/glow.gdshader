shader_type canvas_item;
render_mode blend_add;
// Sun bloom: adds light around the sun and along the horizon on top of everything below it.

uniform float aspect = 1.7778;
uniform float layout_aspect = 1.7778;
uniform float horizon = 0.40;
uniform vec2 sun_pos = vec2(0.64, 0.30);

uniform vec4 glow : source_color;
uniform float glow_strength = 0.35;

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * aspect + layout_aspect * 0.5, UV.y);
	float halo = exp(-distance(p, sun_pos) * 4.2);
	float band = exp(-abs(p.y - horizon) * 10.0) * 0.25;
	COLOR = vec4(glow.rgb * (halo + band) * glow_strength, 1.0);
}
