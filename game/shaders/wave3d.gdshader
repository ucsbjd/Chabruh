shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// The wave's body, flat-shaded in the style of the key frames (kling-04 and kling-05). The mesh
// is a real 3D shape, so perspective, the curl of the lip and the barrel's window all come from
// the geometry. This shader turns the geometry into a few flat emerald bands with the sun glowing
// through the thin top, a pale cell-edge network, a warm rim line, speckled cream-and-violet foam,
// and a dark glowing hollow. It also moves everything:
//  - the lip lifts, throws and falls (a vertex morph between three baked shapes, travelling along
//    the crest, so the mesh never needs rebuilding),
//  - the whitewater boils,
//  - the veins, streaks and foam lace on the face flow up toward the lip.
//
// Vertex colour: r = height up the wave, g = foam, b = depth inside the barrel, a = how thin
// (translucent) the water is. UV = (meters along the outline from the lip's tip, meters along the
// crest). UV2 = (how much lip there is here, how much whitewater). CUSTOM0 = (y, z) of the lifted
// shape, then (y, z) of the landed shape.

uniform sampler2D noise_cells : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_warp : filter_linear_mipmap, repeat_enable;
uniform float time = 0.0;
uniform vec3 sun_dir = vec3(-0.62, 0.20, -0.76);   // toward the sun: ahead, a little up, offshore

// Motion. Each of these is a feel dial.
uniform float lip_period = 5.5;      // seconds from one lip lifting to the next
uniform float lip_spacing = 15.0;    // meters along the crest between lips in the same state
uniform float flow_speed = 1.1;      // meters per second the face's pattern climbs
uniform float slide_speed = 2.6;     // meters per second the pattern slides along the crest
uniform float boil_height = 1.5;     // meters the whitewater heaves

uniform vec4 wave_shadow : source_color;
uniform vec4 wave_deep : source_color;
uniform vec4 wave_mid : source_color;
uniform vec4 wave_light : source_color;
uniform vec4 wave_glint : source_color;
uniform vec4 wave_sunlit : source_color;
uniform vec4 wave_rim : source_color;
uniform vec4 hollow_dark : source_color;
uniform vec4 hollow_glow : source_color;
uniform vec4 foam_lit : source_color;
uniform vec4 foam_shade : source_color;
uniform vec4 sea_horizon : source_color;

// The reef (SectionDirector): two sections as (centre d, half width, height gain, kind), where kind is 0 wall,
// 1 channel, 2 racecourse, 3 bowl; and the swell, the whole wave's height as a factor (near 0 in a lull).
// WaveModel.section_key does the same sums for the rider, so keep them together.
uniform vec4 reef_a = vec4(1000.0, 0.001, 0.0, 0.0);
uniform vec4 reef_b = vec4(1000.0, 0.001, 0.0, 0.0);
uniform float swell = 1.0;

float reef_weight(vec4 r, float d) {
	return 1.0 - smoothstep(0.0, 1.0, abs(d - r.x) / r.y);
}

// How much of the wave's height the reef and the swell give it at d.
float reef_scale(float d) {
	return swell * (1.0 + reef_weight(reef_a, d) * reef_a.z + reef_weight(reef_b, d) * reef_b.z);
}

// How much bowl (kind 3) or of the kinds from `kind` up (2: racecourse and bowl) there is at d, 0 to 1.
float reef_kind(float d, float kind) {
	return min(reef_weight(reef_a, d) * step(kind - 0.5, reef_a.w) + reef_weight(reef_b, d) * step(kind - 0.5, reef_b.w), 1.0);
}

// Over a bowl the foot of the face is drawn in toward the wave (WaveModel.SUCK_OUT and SUCK_TOP).
const float SUCK_OUT = 0.22;
const float SUCK_TOP = 0.45;

varying vec3 wpos;
varying float crash;
varying float whitewater_here;
varying float bowl_here;

void vertex() {
	float lip_here = UV2.x;
	float d = -VERTEX.x;

	// One cycle: lifted (the lip stands up and pitches), thrown (out over the trough), landed (it has
	// fallen into the foam), then lifted again. The phase slides along the crest, so at any moment
	// the lips along the wave are at different points in the cycle. WaveStage.lip_morph() repeats the lift and fall for
	// things that sit on the face (the carve trail), so change them together.
	float phase = fract(time / lip_period + d / lip_spacing);
	float lift = (smoothstep(0.86, 1.0, phase) + 1.0 - smoothstep(0.0, 0.28, phase)) * lip_here;
	float fall = smoothstep(0.50, 0.66, phase) * (1.0 - smoothstep(0.74, 0.92, phase)) * lip_here;
	vec2 thrown = VERTEX.yz;
	VERTEX.yz = thrown + (CUSTOM0.xy - thrown) * lift + (CUSTOM0.zw - thrown) * fall;
	crash = fall;

	// The reef: the wall stands taller or lower where a section is, and over a bowl the trough drains in toward it.
	bowl_here = reef_kind(d, 3.0);
	VERTEX.yz *= reef_scale(d);
	VERTEX.z *= 1.0 - SUCK_OUT * bowl_here * (1.0 - smoothstep(0.0, SUCK_TOP, COLOR.r));

	// The whitewater heaves and rolls toward the beach. The foot of it stays on the water.
	float whitewater = UV2.y;
	whitewater_here = whitewater;
	float heave = textureLod(noise_warp, vec2(VERTEX.x * 0.11 + time * 0.03, VERTEX.z * 0.2 - time * 0.12), 0.0).r - 0.5;
	// A second, faster and smaller chop on top, so the whitewater is lumpy and never smooth.
	float chop = textureLod(noise_warp, vec2(VERTEX.x * 0.4 - time * 0.2, VERTEX.z * 0.55 + time * 0.35), 0.0).r - 0.5;
	float rough = whitewater * COLOR.g * (0.35 + COLOR.r) * swell;
	VERTEX.y += (heave * boil_height + chop * 0.7) * rough;
	VERTEX.z += (heave * 0.9 + chop * 0.5) * rough;

	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// A flat step with a softly blended edge: the posterised look of the key frames.
float band(float x, float edge, float soft) {
	return smoothstep(edge - soft, edge + soft, x);
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - wpos;
	float dist = length(to_cam);
	vec3 v = to_cam / dist;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	float h = COLOR.r;
	float cav = COLOR.b;
	float thin = COLOR.a;
	// A lip that has just fallen leaves foam high on the face.
	float foam = clamp(COLOR.g + crash * 0.6 * smoothstep(0.3, 1.0, h), 0.0, 1.0);

	// Where the pattern is now: it climbs the face toward the lip's tip (UV.x counts from the tip,
	// positive down the face, negative over the back) and slides along the crest.
	vec2 flow_uv = vec2(UV.x + time * flow_speed * (UV.x > 0.0 ? 1.0 : -1.0), UV.y - time * slide_speed);

	// Whitewater is cut into a ragged, streaky edge: notches hang from its top like drips.
	float streaks = texture(noise_warp, vec2(flow_uv.x * 0.03, flow_uv.y * 0.55)).r;
	float notch = foam * smoothstep(0.72, 1.0, h) * (0.30 + streaks * 1.2);
	if (notch > 0.62) {
		discard;
	}

	// Backlit: faces that look at the camera are in shade, and thin water glows with light
	// shining through it.
	float lit = dot(n, normalize(sun_dir)) * 0.5 + 0.5;
	float warp = texture(noise_warp, UV * vec2(0.035, 0.03)).r - 0.5;
	float blot = texture(noise_warp, flow_uv * vec2(0.09, 0.07)).r - 0.5;
	float tone = clamp(0.06 + h * 0.80 + (lit - 0.5) * 0.18 + thin * 0.28 - cav * 0.30 + warp * 0.12 + blot * 0.10, 0.0, 1.0);
	vec3 col = wave_shadow.rgb;
	col = mix(col, wave_deep.rgb, band(tone, 0.14, 0.07));
	col = mix(col, wave_mid.rgb, band(tone, 0.40, 0.09));
	col = mix(col, wave_light.rgb, band(tone, 0.64, 0.10));
	col = mix(col, wave_glint.rgb, band(tone, 0.86, 0.06));

	// The sun shining through the top of the wave: where the water is high and thin, it glows
	// yellow-green, like the key frame's crest.
	float through = smoothstep(0.55, 1.0, h) * (0.35 + 0.65 * thin) * (1.0 - cav);
	col = mix(col, mix(wave_glint.rgb, wave_sunlit.rgb, 0.5), band(through, 0.30, 0.16));
	col = mix(col, wave_sunlit.rgb, band(through, 0.62, 0.12));

	// Fine dark streaks hanging from the crest, and the pale cell-edge network over the face.
	float drip = step(0.80, texture(noise_warp, vec2(flow_uv.y * 0.55, 0.37)).r) * smoothstep(0.55, 0.95, h) * (1.0 - cav);
	col = mix(col, wave_shadow.rgb, drip * 0.45);
	// Thin crisp lines: the cell texture is a smooth distance field, so a narrow threshold with
	// a one-pixel edge stays sharp however close the camera is.
	float cell = texture(noise_cells, flow_uv * vec2(0.095, 0.065)).r;
	float vein = (1.0 - smoothstep(0.022, 0.022 + fwidth(cell) * 1.0, cell)) * (1.0 - smoothstep(0.62, 0.92, h)) * clamp(1.0 - cav * 1.6, 0.0, 1.0);
	col = mix(col, mix(foam_shade.rgb, foam_lit.rgb, 0.6), vein * 0.65);

	// Over a bowl the drained foot of the face is darker: the reef is right under it.
	col = mix(col, wave_shadow.rgb, bowl_here * 0.4 * (1.0 - smoothstep(0.0, 0.3, h)));

	// Inside the barrel: dark violet-navy, glowing where light shines through the thin lip.
	col = mix(col, hollow_dark.rgb, cav * 0.80);
	// The tube glows where the wall is thin and up under the lip, and stays dark low down, so the
	// hollow has depth: a bright mouth, a dark throat.
	float glow = clamp(smoothstep(0.05, 0.6, thin) + smoothstep(0.50, 0.95, h) * 0.7, 0.0, 1.0);
	col = mix(col, hollow_glow.rgb, cav * glow * 0.9);

	// Foam: cream clumps shaded violet, sprinkled with white speckle like the key frame's spray.
	// Where foam begins the edge hangs down the face in vertical drips, like the crashing lip in fan A.
	float drips = texture(noise_warp, vec2(flow_uv.x * 0.02, flow_uv.y * 0.5)).r - 0.5;
	float blotch = texture(noise_warp, flow_uv * 0.09).r - 0.5;
	float foam_mask = smoothstep(0.5 - 0.015, 0.5 + 0.015, foam + drips * 0.9 * (1.0 - h * 0.4) + blotch * 0.25);
	float shade = clamp(texture(noise_warp, flow_uv * 0.05).r * 0.9 + (1.0 - h) * 0.45 + smoothstep(0.55, 0.75, texture(noise_warp, flow_uv * 0.03).r) * 0.3 + whitewater_here * 0.4 - 0.15, 0.0, 1.0);
	vec3 foam_col = mix(foam_lit.rgb, foam_shade.rgb, shade);
	float speckle = step(0.56, texture(noise_cells, flow_uv * 0.9).r);
	foam_col = mix(foam_col, foam_lit.rgb, speckle * shade * 0.85);
	col = mix(col, foam_col, foam_mask);

	// The warm rim line along steep silhouettes, and a bright line along the top of the crest.
	float fresnel = 1.0 - clamp(dot(n, v), 0.0, 1.0);
	float steep = 1.0 - smoothstep(0.55, 0.85, n.y);
	float rim = smoothstep(0.76, 0.88, fresnel) * steep * smoothstep(0.15, 0.4, h);
	float crest_line = smoothstep(0.45, 0.8, n.y) * smoothstep(0.86, 0.98, h);
	float no_foam = 1.0 - smoothstep(0.05, 0.4, foam);
	col = mix(col, wave_rim.rgb, max(rim, crest_line) * no_foam);

	// Far parts fade into the haze.
	col = mix(col, sea_horizon.rgb, smoothstep(45.0, 240.0, dist) * 0.85);

	ALBEDO = col;
}
