shader_type canvas_item;
// Colour grade and vignette as one soft tint over the frame: violet at the top, warm at the
// bottom, darker toward the corners. It blends over the image, so it needs no screen read.

uniform float aspect = 1.7778;

uniform vec4 grade_top : source_color;
uniform vec4 grade_bottom : source_color;
uniform float grade_strength = 0.10;
uniform vec4 vignette : source_color;
uniform float vignette_strength = 0.38;

void fragment() {
	vec2 centred = (UV - 0.5) * vec2(aspect, 1.0);
	float corner = smoothstep(0.55, 1.15, length(centred));
	vec3 tint = mix(grade_top.rgb, grade_bottom.rgb, UV.y);
	vec3 col = mix(tint, vignette.rgb, corner);
	COLOR = vec4(col, clamp(grade_strength + corner * vignette_strength, 0.0, 0.85));
}
