shader_type canvas_item;
// Flat silhouette colour for ridges and palms, fading toward the haze colour near the horizon.
// Colour lives in uniforms, not in vertex colours, so a mood fade never redraws the polygons.
// (Redrawing a Polygon2D every frame floods the web console with WebGL buffer warnings.)

uniform vec4 ridge_color : source_color;
uniform vec4 haze : source_color;
uniform float haze_amount = 0.0;
uniform float horizon = 0.40;
uniform float fade_height = 0.06;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	float fade = smoothstep(horizon - fade_height, horizon, local_y) * haze_amount;
	COLOR = vec4(mix(ridge_color.rgb, haze.rgb, fade), 1.0);
}
