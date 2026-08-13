shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled, specular_disabled, ambient_light_disabled;

// 远景只做极弱的大块明暗，避免星云纹理抢行星和航道。
uniform vec3 color_void : source_color = vec3(0.008, 0.009, 0.014);
uniform vec3 color_dust : source_color = vec3(0.028, 0.034, 0.052);
uniform float dust_strength : hint_range(0.0, 0.4) = 0.12;
uniform float noise_scale = 0.55;
uniform float layer_offset = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 dir = normalize(world_pos);

	// 两层很大的噪声叠一下，只有缓缓的明暗，没有碎云。
	vec2 uv = dir.xz * noise_scale + vec2(dir.y * 0.18 + layer_offset, layer_offset * 0.3);
	float n = noise2(uv) * 0.72 + noise2(uv * 1.7 + vec2(2.1, 0.8)) * 0.28;
	// 压成三档灰，看起来像淡像素底，而不是贴图。
	float band = floor(n * 3.0 + 0.001) / 2.0;
	float mask = smoothstep(0.22, 0.78, band) * dust_strength;

	vec3 col = mix(color_void, color_dust, mask);
	ALBEDO = col;
}
