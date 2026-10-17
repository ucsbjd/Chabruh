shader_type canvas_item;
// The spray that falls behind the surfer (SurferSpray's back layer: the fan's body, its core, the wake, the rail's
// curtain). The 3D stage draws the real-time surfer below all of the 2D spray, so these droplets leave out his
// silhouette (WaveStage.surfer_mask(), drawn alone at half size with the same camera) and he reads in front of the fan,
// as in the gold-standard footage.

uniform sampler2D surfer_mask : filter_linear, hint_default_transparent;
uniform bool masked = false;

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
	if (masked) {
		COLOR.a *= 1.0 - smoothstep(0.3, 0.7, texture(surfer_mask, SCREEN_UV).a);
	}
}
