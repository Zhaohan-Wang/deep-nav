shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, specular_disabled, shadows_disabled;

uniform float pixels : hint_range(16.0, 160.0) = 80.0;
uniform float seed = 2.4;
uniform float land_cutoff : hint_range(0.0, 1.0) = 0.52;
uniform vec3 light_dir = vec3(0.42, 0.62, 0.48);
uniform vec4 ocean_col : source_color = vec4(0.12, 0.28, 0.48, 1.0);
uniform vec4 land_col : source_color = vec4(0.38, 0.62, 0.30, 1.0);
uniform vec4 land_dark : source_color = vec4(0.16, 0.30, 0.20, 1.0);
uniform vec4 shade_col : source_color = vec4(0.03, 0.035, 0.07, 1.0);
uniform int surface_mode = 0;
uniform bool dither = true;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += noise(p) * a;
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = floor(UV * pixels) / pixels;
	float n = fbm(uv * vec2(5.0, 2.6) + vec2(seed, seed * 0.37));
	vec3 L = normalize((VIEW_MATRIX * vec4(normalize(light_dir), 0.0)).xyz);
	float ndl = dot(normalize(NORMAL), L);

	float band = 0.08;
	if (ndl > 0.42) {
		band = 1.0;
	} else if (ndl > 0.14) {
		band = 0.62;
	} else if (ndl > -0.02) {
		band = 0.28;
	}

	vec3 albedo = ocean_col.rgb;
	if (surface_mode == 1) {
		float bands = sin(uv.y * 22.0 + n * 4.0);
		albedo = mix(ocean_col.rgb, land_col.rgb, smoothstep(-0.2, 0.55, bands));
		albedo = mix(albedo, land_dark.rgb, step(0.72, n));
	} else if (surface_mode == 2) {
		albedo = mix(land_dark.rgb, land_col.rgb, smoothstep(0.35, 0.7, n));
		if (n > 0.78) {
			albedo = ocean_col.rgb;
		}
	} else if (surface_mode == 3) {
		albedo = mix(land_dark.rgb, land_col.rgb, n);
		band = 1.0;
	} else {
		if (n > land_cutoff) {
			albedo = mix(land_dark.rgb, land_col.rgb, smoothstep(land_cutoff, land_cutoff + 0.18, n));
		}
	}

	vec3 col = mix(shade_col.rgb, albedo, band);
	if (dither && ndl < 0.22 && ndl > -0.05) {
		float checker = mod(floor(uv.x * pixels) + floor(uv.y * pixels), 2.0);
		if (checker < 0.5) {
			col = mix(col, albedo, 0.22);
		}
	}
	ALBEDO = col;
	EMISSION = surface_mode == 3 ? col * 0.45 : vec3(0.0);
}
