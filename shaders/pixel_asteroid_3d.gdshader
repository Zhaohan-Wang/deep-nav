shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled;

// 3D 像素小行星：不规则球体 + 陨石坑噪声 + 量化光照，自己会转，不跟着相机。
uniform float pixels : hint_range(12.0, 80.0) = 28.0;
uniform float seed = 2.4;
uniform vec3 light_dir = vec3(0.42, 0.62, 0.48);
uniform vec4 col_lit : source_color = vec4(0.64, 0.66, 0.76, 1.0);
uniform vec4 col_mid : source_color = vec4(0.30, 0.41, 0.52, 1.0);
uniform vec4 col_shade : source_color = vec4(0.16, 0.18, 0.28, 1.0);
uniform float lump : hint_range(0.0, 0.4) = 0.16;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise2(p) * a;
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	float n = fbm((VERTEX.xz + VERTEX.y) * vec2(1.7, 1.1) + vec2(seed));
	VERTEX += NORMAL * (n - 0.5) * lump;
}

void fragment() {
	vec3 nrm = normalize(NORMAL);
	vec2 sph = vec2(atan(nrm.z, nrm.x), nrm.y);
	vec2 uv = floor(sph * pixels) / pixels;
	float n = fbm(uv * 5.4 + vec2(seed, seed * 0.37));
	float crater = fbm(uv * 9.2 + vec2(3.1, seed));
	vec3 L = normalize((VIEW_MATRIX * vec4(normalize(light_dir), 0.0)).xyz);
	float ndl = dot(normalize(NORMAL), L);

	vec3 col = col_mid.rgb;
	if (n > 0.58) {
		col = col_lit.rgb;
	}
	if (crater > 0.62) {
		col = col_shade.rgb;
	}

	float band = 0.22;
	if (ndl > 0.28) {
		band = 1.0;
	} else if (ndl > 0.02) {
		band = 0.55;
	}
	ALBEDO = mix(col_shade.rgb, col, band);
}
