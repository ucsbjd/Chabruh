shader_type canvas_item;
// The surfer's light, laid over its flat colours: a violet shade on the side away from the sun and a
// warm rim on the side toward it, like the key frames. One shader, two materials (is_rim 0 and 1).
// The colours come from the mood, so a mood fade only changes uniforms and never redraws a polygon.

uniform float is_rim = 0.0;
uniform float shade_strength = 0.34;
uniform float rim_strength = 0.8;

uniform vec4 surfer_shade : source_color;
uniform vec4 surfer_rim : source_color;

void fragment() {
	vec3 colour = mix(surfer_shade.rgb, surfer_rim.rgb, is_rim);
	COLOR = vec4(colour, mix(shade_strength, rim_strength, is_rim) * COLOR.a);
}
