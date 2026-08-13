shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, specular_disabled, cull_disabled;

// 飞船为中心的大气透视 + 薄透镜景深。
// 雾按「像素到飞船」的世界距离，转弯时焦点不会漂。
// 虚化用薄透镜弥散圆：CoC = A * |z - zf| / z
// 近处比远处涨得快，远处有上界；不再用轴向 mip 方框模糊。
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec3 fog_color : source_color = vec3(0.035, 0.042, 0.085);
uniform vec3 ship_world = vec3(0.0);
uniform float fog_start = 20.0;
uniform float fog_end = 88.0;
uniform float fog_strength : hint_range(0.0, 1.0) = 0.58;
uniform float focus_distance = 18.0;
uniform float aperture : hint_range(0.0, 8.0) = 3.2;
uniform float max_coc_px : hint_range(1.0, 12.0) = 5.5;

const float GOLDEN_ANGLE = 2.3999632;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = 1.0 / VIEWPORT_SIZE;
	vec3 sharp = textureLod(screen_texture, uv, 0.0).rgb;

	float raw_depth = texture(depth_texture, uv).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
	view.xyz /= view.w;
	float z = max(-view.z, 0.0);
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;

	bool is_sky = z > 400.0;
	float zf = max(focus_distance, 0.5);
	float safe_z = max(z, 0.12);
	// 天空和远星不做散焦，避免亮点被采样成一闪一闪。
	float coc = is_sky ? 0.0 : min(aperture * abs(safe_z - zf) / safe_z, max_coc_px);

	vec3 blurred = sharp;
	if (coc > 0.45) {
		vec3 acc = sharp;
		float wsum = 1.0;
		for (int i = 0; i < 9; i++) {
			float fi = float(i) + 0.5;
			float radius = sqrt(fi / 9.0) * coc;
			float ang = fi * GOLDEN_ANGLE;
			vec2 suv = uv + vec2(cos(ang), sin(ang)) * radius * texel;
			float sraw = texture(depth_texture, suv).x;
			vec4 sview = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, sraw, 1.0);
			sview.xyz /= sview.w;
			float sz = max(-sview.z, 0.12);
			float scoc = min(aperture * abs(sz - zf) / sz, max_coc_px);
			float sw = smoothstep(coc * 0.35, coc, scoc + 0.4);
			acc += textureLod(screen_texture, suv, 0.0).rgb * sw;
			wsum += sw;
		}
		blurred = acc / max(wsum, 0.001);
	}

	vec3 col = mix(sharp, blurred, smoothstep(0.35, 1.6, coc));

	float dist_ship = length(world_pos - ship_world);
	float fog = is_sky
		? 0.0
		: clamp((dist_ship - fog_start) / max(fog_end - fog_start, 0.001), 0.0, 1.0);
	fog = fog * fog * (3.0 - 2.0 * fog);

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, 1.0 - fog * 0.42);
	col = mix(col, fog_color, fog * fog_strength);
	ALBEDO = col;
}
