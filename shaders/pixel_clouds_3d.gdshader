shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, blend_mix, shadows_disabled, specular_disabled;

uniform float pixels : hint_range(16.0, 160.0) = 72.0;
uniform float seed = 3.1;
uniform float cover : hint_range(0.0, 1.0) = 0.46;
uniform float time_speed = 0.04;
uniform vec4 cloud_col : source_color = vec4(0.86, 0.90, 0.94, 0.85);
uniform vec4 cloud_shadow : source_color = vec4(0.45, 0.52, 0.62, 0.7);
uniform vec3 light_dir = vec3(0.42, 0.62, 0.48);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise(p) * a;
		p *= 2.05;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = floor(UV * pixels) / pixels;
	uv.x += TIME * time_speed;
	float n = fbm(uv * vec2(6.0, 3.0));
	float mask = step(cover, n);
	if (mask < 0.5) {
		discard;
	}
	vec3 L = normalize((VIEW_MATRIX * vec4(normalize(light_dir), 0.0)).xyz);
	float ndl = dot(normalize(NORMAL), L);
	vec3 col = mix(cloud_shadow.rgb, cloud_col.rgb, smoothstep(0.0, 0.5, ndl));
	ALBEDO = col;
	ALPHA = cloud_col.a * mask;
}
