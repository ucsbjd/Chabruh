shader_type spatial;
render_mode unshaded, cull_back, depth_test_inverted, depth_draw_never, blend_mix;
// The surfer seen through the lip curtain: the next pass of surfer3d.gdshader, a soft teal-and-aqua figure with a warm
// rim. The inverted depth test draws only the parts that something in the stage is in front of. His own pass writes 1
// to the stencil wherever he is the nearest thing, so the parts he hides behind himself (torso behind an arm) are left
// alone; this pass writes 1 too, so limbs that overlap behind the water are tinted once, not twice. Both work in the
// Compatibility renderer and on WebGL2.
stencil_mode read, write, compare_not_equal, 1;

uniform vec4 surfer_veil_deep : source_color = vec4(0.05, 0.27, 0.31, 1.0);
uniform vec4 surfer_veil_lit : source_color = vec4(0.35, 0.84, 0.76, 1.0);
uniform vec4 wave_rim : source_color = vec4(0.91, 0.82, 0.48, 1.0);

// The same sun as surfer3d.gdshader, so the figure keeps his light and shade bands.
uniform vec3 key_dir = vec3(-0.55, 0.70, 0.45);
// How much of him shows through the water, and through its sunward edge.
uniform float veil_alpha = 0.4;
uniform float rim_alpha = 0.7;
uniform float rim_width = 0.45;

varying vec3 world_normal;

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float l = dot(normalize(world_normal), normalize(key_dir));
	vec3 colour = mix(surfer_veil_deep.rgb, surfer_veil_lit.rgb, smoothstep(-0.2, 0.6, l));
	float edge = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width, 1.0, edge) * smoothstep(-0.2, 0.4, l);
	ALBEDO = mix(colour, wave_rim.rgb, rim);
	ALPHA = mix(veil_alpha, rim_alpha, rim);
}
