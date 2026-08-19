shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled, specular_disabled, ambient_light_disabled;

// 与星图同色的世界空间天幕；飞船位移通过 travel_offset 驱动缓慢视差。
uniform vec3 color_void : source_color = vec3(0.004, 0.012, 0.028);
uniform vec3 color_dust : source_color = vec3(0.022, 0.092, 0.155);
uniform vec3 color_filament : source_color = vec3(0.022, 0.145, 0.165);
uniform float dust_strength : hint_range(0.0, 0.4) = 0.24;
uniform float noise_scale = 0.55;
uniform float layer_offset = 0.0;
uniform vec2 travel_offset = vec2(0.0);

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
	// 先量化方向再算纹理，远景也保留像素阶梯，而不是滑润的 3D 噪声。
	dir = floor(dir * 260.0 + 0.5) / 260.0;

	vec2 uv = dir.xz * noise_scale + vec2(dir.y * 0.26 + layer_offset, layer_offset * 0.3) + travel_offset * 0.22;
	float n = noise2(uv) * 0.64 + noise2(uv * 1.83 + vec2(2.1, 0.8)) * 0.25 + noise2(uv * 3.1 - vec2(1.7, 2.4)) * 0.11;
	float ridge = 1.0 - abs(noise2(uv * 1.28 + vec2(5.2, -3.1)) * 2.0 - 1.0);
	float band = floor(n * 5.0 + 0.001) / 4.0;
	float mask = 0.07 + smoothstep(0.25, 0.76, band) * dust_strength;
	float filament = smoothstep(0.71, 0.92, ridge) * 0.075;

	vec3 col = color_void + color_dust * mask + color_filament * filament;
	ALBEDO = col;
}
