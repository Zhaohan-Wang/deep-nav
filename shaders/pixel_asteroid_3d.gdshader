shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled;

// 3D 像素小行星：MultiMesh 每实例携带种子、像素度、起伏与转速；
// 一整批碎石只需一次 draw call，旋转也不再占用逐节点 CPU 脚本。
uniform vec3 light_dir = vec3(0.42, 0.62, 0.48);
uniform vec4 col_lit : source_color = vec4(0.64, 0.66, 0.76, 1.0);
uniform vec4 col_mid : source_color = vec4(0.30, 0.41, 0.52, 1.0);
uniform vec4 col_shade : source_color = vec4(0.16, 0.18, 0.28, 1.0);
varying vec4 rock_data;

float hash21(vec2 p, float rock_seed) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + rock_seed) * 43758.5453);
}

float noise2(vec2 p, float rock_seed) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i, rock_seed);
	float b = hash21(i + vec2(1.0, 0.0), rock_seed);
	float c = hash21(i + vec2(0.0, 1.0), rock_seed);
	float d = hash21(i + vec2(1.0, 1.0), rock_seed);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, float rock_seed) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise2(p, rock_seed) * a;
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

mat3 axis_rotation(vec3 axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	float t = 1.0 - c;
	return mat3(
		vec3(t * axis.x * axis.x + c, t * axis.x * axis.y + s * axis.z, t * axis.x * axis.z - s * axis.y),
		vec3(t * axis.x * axis.y - s * axis.z, t * axis.y * axis.y + c, t * axis.y * axis.z + s * axis.x),
		vec3(t * axis.x * axis.z + s * axis.y, t * axis.y * axis.z - s * axis.x, t * axis.z * axis.z + c)
	);
}

void vertex() {
	rock_data = INSTANCE_CUSTOM;
	float rock_seed = mix(1.1, 8.8, rock_data.r);
	float lump = mix(0.13, 0.27, rock_data.b);
	float spin = mix(-0.85, 0.85, rock_data.a);
	vec3 axis = normalize(vec3(sin(rock_seed * 1.7), cos(rock_seed * 0.91), sin(rock_seed * 0.43 + 1.2)));
	mat3 tumble = axis_rotation(axis, TIME * spin + rock_seed * 0.37);
	VERTEX = tumble * VERTEX;
	NORMAL = normalize(tumble * NORMAL);
	float n = fbm((VERTEX.xz + VERTEX.y) * vec2(1.7, 1.1) + vec2(rock_seed), rock_seed);
	VERTEX += NORMAL * (n - 0.5) * lump;
}

void fragment() {
	float seed = mix(1.1, 8.8, rock_data.r);
	float pixels = mix(12.0, 28.0, rock_data.g);
	vec3 nrm = normalize(NORMAL);
	vec2 sph = vec2(atan(nrm.z, nrm.x), nrm.y);
	vec2 uv = floor(sph * pixels) / pixels;
	float n = fbm(uv * 5.4 + vec2(seed, seed * 0.37), seed);
	float crater = fbm(uv * 9.2 + vec2(3.1, seed), seed);
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
