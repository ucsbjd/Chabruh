shader_type canvas_item;
// Film grain: black and white speckle that re-rolls about 12 times a second. Its cell size is
// a fraction of the screen, so it looks the same on a phone and on a desktop.

uniform float aspect = 1.7778;
uniform float time = 0.0;
uniform float grain_strength = 0.05;

const float CELLS_HIGH = 360.0;
const float FRAMES_PER_SECOND = 12.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV * vec2(aspect, 1.0) * CELLS_HIGH);
	float frame = mod(floor(time * FRAMES_PER_SECOND), 64.0);
	float n = hash21(cell + vec2(frame * 17.0, frame * 31.0)) - 0.5;
	COLOR = vec4(vec3(step(0.0, n)), abs(n) * 2.0 * grain_strength);
}
