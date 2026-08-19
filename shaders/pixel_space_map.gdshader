shader_type canvas_item;
render_mode unshaded, blend_mix;

// 体积折叠思路参考 Star Nest (Pablo Roman Andrioli, MIT, Shadertoy XlfGRj)。
// 这里重写为世界坐标的低成本、低饱和像素背景，不复制原作的屏幕中心漩涡。
uniform vec2 canvas_size = vec2(1920.0, 1080.0);
uniform vec2 focus_world = vec2(0.0);
uniform float pixels_per_unit = 5.0;
uniform float pixel_block : hint_range(1.0, 6.0) = 3.0;
uniform vec3 color_void : source_color = vec3(0.004, 0.012, 0.028);
uniform vec3 color_blue : source_color = vec3(0.022, 0.092, 0.155);
uniform vec3 color_cyan : source_color = vec3(0.022, 0.145, 0.165);
uniform vec3 color_amber : source_color = vec3(0.105, 0.067, 0.032);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash22(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453123);
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
	float sum = 0.0;
	float amp = 0.52;
	for (int i = 0; i < 4; i++) {
		sum += noise2(p) * amp;
		p = mat2(vec2(0.82, 0.57), vec2(-0.57, 0.82)) * p * 2.03 + vec2(1.7, -0.8);
		amp *= 0.48;
	}
	return sum;
}

float folded_filament(vec2 p) {
	vec3 q = vec3(p * 0.32, 0.73);
	float previous = 0.0;
	float activity = 0.0;
	for (int i = 0; i < 6; i++) {
		q = abs(q) / max(dot(q, q), 0.18) - 0.53;
		float current = length(q);
		activity += abs(current - previous);
		previous = current;
	}
	return smoothstep(4.5, 7.8, activity);
}

float pixel_star(vec2 world, float cell_size, float threshold) {
	vec2 cell = floor(world / cell_size);
	float seed = hash21(cell + vec2(19.0, 43.0));
	if (seed < threshold) {
		return 0.0;
	}
	vec2 center = (hash22(cell) * 0.62 + 0.19);
	// 星核始终只占一个像素采样块；不能随星格间距一起膨胀成十字路障。
	vec2 local_blocks = (fract(world / cell_size) - center) * cell_size * pixels_per_unit / max(pixel_block, 1.0);
	float core = 1.0 - step(0.58, max(abs(local_blocks.x), abs(local_blocks.y)));
	float cross_h = (1.0 - step(0.48, abs(local_blocks.y))) * (1.0 - step(2.15, abs(local_blocks.x)));
	float cross_v = (1.0 - step(0.48, abs(local_blocks.x))) * (1.0 - step(2.15, abs(local_blocks.y)));
	return max(core, max(cross_h, cross_v) * step(0.985, seed));
}

void fragment() {
	vec2 sampled_pixel = (floor(UV * canvas_size / pixel_block) + 0.5) * pixel_block;
	vec2 screen_world = (sampled_pixel - canvas_size * 0.5) / max(pixels_per_unit, 0.01);
	vec2 world = focus_world + screen_world;

	// 三个层次分别只跟随 16% / 34% / 100% 的世界位移，自然产生视差。
	vec2 far_world = screen_world + focus_world * 0.16;
	vec2 mid_world = screen_world + focus_world * 0.34;
	vec2 domain = far_world * 0.0062;
	vec2 warp = vec2(fbm(domain + vec2(4.1, 1.3)), fbm(domain + vec2(-2.7, 6.4))) - 0.5;
	float cloud = fbm(domain + warp * 1.45);
	float cloud_detail = fbm(mid_world * 0.0105 + warp * 0.82 + vec2(7.2, -3.1));
	float filament = folded_filament(mid_world * 0.0038 + warp * 0.4);

	float broad_cloud = fbm(far_world * 0.0031 + vec2(-8.4, 3.7));
	vec3 col = color_void + color_blue * (0.10 + smoothstep(0.27, 0.68, cloud) * 0.58);
	col += color_cyan * smoothstep(0.40, 0.74, cloud_detail) * 0.25;
	col += color_blue * smoothstep(0.36, 0.72, broad_cloud) * 0.18;
	col += color_amber * smoothstep(0.58, 0.84, cloud + cloud_detail * 0.25) * 0.10;
	col += mix(color_blue, color_cyan, cloud_detail) * filament * 0.055;

	float stars_far = pixel_star(far_world, 16.0, 0.77);
	float stars_mid = pixel_star(mid_world + vec2(240.0, -170.0), 28.0, 0.88);
	float stars_near = pixel_star(world + vec2(-410.0, 90.0), 52.0, 0.955);
	col += vec3(0.42, 0.58, 0.68) * stars_far * 0.42;
	col += vec3(0.56, 0.78, 0.82) * stars_mid * 0.68;
	col += vec3(0.92, 0.76, 0.52) * stars_near * 0.82;

	COLOR = vec4(col, 1.0);
}
