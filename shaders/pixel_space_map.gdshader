shader_type canvas_item;
render_mode unshaded, blend_mix;
#include "res://shaders/star_lib.gdshaderinc"

// 扇区全图的暗太空：星云 + 与视口相同的像素星星形状（只是更大）。
uniform vec3 color_base : source_color = vec3(0.018, 0.022, 0.042);
uniform vec3 nebula_cool : source_color = vec3(0.07, 0.11, 0.20);
uniform vec3 nebula_warm : source_color = vec3(0.12, 0.04, 0.10);
uniform float darken : hint_range(0.0, 1.0) = 0.52;
uniform float star_cell : hint_range(6.0, 40.0) = 12.0;
uniform float star_pixel : hint_range(1.0, 8.0) = 2.2;
uniform vec4 grid_color : source_color = vec4(0.16, 0.42, 0.46, 0.12);
uniform float cells = 10.0;
uniform float line_width = 0.007;

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
		p *= 2.04;
		a *= 0.5;
	}
	return v;
}

float collect_stars(vec2 sph, float threshold, float pixel_size) {
	vec2 cell = floor(sph);
	float acc = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 ncell = cell + vec2(float(x), float(y));
			float h = hash21(ncell + vec2(28.0, 17.0));
			if (h < threshold) {
				continue;
			}
			int shape = star_pick_shape(hash22(ncell));
			vec2 center = ncell + vec2(0.5);
			vec2 local_px = (sph - center) * pixel_size;
			float m = star_mask(local_px, shape);
			float bright = 0.55 + hash22(ncell.yx) * 0.45;
			acc = max(acc, m * bright);
		}
	}
	return acc;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = color_base;
	float cloud_a = fbm(uv * 3.0);
	float cloud_b = fbm(uv * 4.8 + vec2(2.4, 0.8));
	col += nebula_cool * smoothstep(0.46, 0.74, cloud_a) * 0.11;
	col += nebula_warm * smoothstep(0.52, 0.80, cloud_b) * 0.08;
	col *= 1.0 - darken;

	vec2 sph_far = uv * vec2(star_cell * 1.7, star_cell);
	vec2 sph_mid = uv * vec2(star_cell * 0.9, star_cell * 0.58);
	vec2 sph_near = uv * vec2(star_cell * 0.42, star_cell * 0.28);
	float far_s = collect_stars(sph_far, 0.955, star_pixel * 1.15);
	float mid_s = collect_stars(sph_mid, 0.974, star_pixel);
	float near_s = collect_stars(sph_near, 0.990, star_pixel * 0.72);
	vec3 far_t = star_tint_from(hash22(floor(sph_far)));
	vec3 mid_t = star_tint_from(hash21(floor(sph_mid)));
	vec3 near_t = star_tint_from(hash22(floor(sph_near) + 3.0));
	col += far_t * far_s * 0.65;
	col += mid_t * mid_s * 0.95;
	col += near_t * near_s * 1.15;

	vec2 grid = abs(fract(uv * cells) - 0.5);
	float line = 1.0 - step(line_width, min(grid.x, grid.y));
	col = mix(col, grid_color.rgb, line * grid_color.a);

	COLOR = vec4(col, 1.0);
}
