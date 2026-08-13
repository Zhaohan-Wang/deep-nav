shader_type canvas_item;
render_mode unshaded, blend_mix;

// 整屏像素合成：量化分辨率 + 色阶 + Bayer 抖动。
// 这是整体像素风的核心，作用在整个 3D 视口上，而不是单个星球。

uniform float pixel_scale : hint_range(1.0, 8.0) = 2.0;
uniform float color_levels : hint_range(4.0, 24.0) = 10.0;
uniform float dither_strength : hint_range(0.0, 0.2) = 0.045;
uniform float contrast : hint_range(0.6, 1.6) = 1.12;
uniform float saturation : hint_range(0.4, 1.4) = 0.92;
uniform vec4 tint : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform float hurt_flash : hint_range(0.0, 1.0) = 0.0;
// 接近危险物的警告：只在屏幕边缘闪橙红，由脚本按距离驱动闪烁。
uniform float warn_pulse : hint_range(0.0, 1.0) = 0.0;
// 受击瞬间舱内灯光过载：整屏短促提亮。
uniform float light_flash : hint_range(0.0, 1.0) = 0.0;
// 船体解体白屏：1.0 时纯白盖满视口（主要靠全窗遮罩，这里兜底副窗模式）。
uniform float death_flash : hint_range(0.0, 1.0) = 0.0;

float bayer4(vec2 pixel) {
	vec2 p = floor(mod(pixel, 4.0));
	float x = p.x;
	float y = p.y;
	float idx = x + y * 4.0;
	float m = 0.0;
	if (idx < 0.5) { m = 0.0; }
	else if (idx < 1.5) { m = 8.0; }
	else if (idx < 2.5) { m = 2.0; }
	else if (idx < 3.5) { m = 10.0; }
	else if (idx < 4.5) { m = 12.0; }
	else if (idx < 5.5) { m = 4.0; }
	else if (idx < 6.5) { m = 14.0; }
	else if (idx < 7.5) { m = 6.0; }
	else if (idx < 8.5) { m = 3.0; }
	else if (idx < 9.5) { m = 11.0; }
	else if (idx < 10.5) { m = 1.0; }
	else if (idx < 11.5) { m = 9.0; }
	else if (idx < 12.5) { m = 15.0; }
	else if (idx < 13.5) { m = 7.0; }
	else if (idx < 14.5) { m = 13.0; }
	else { m = 5.0; }
	return m / 16.0;
}

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec2 screen_px = UV / texel;
	vec2 snapped = (floor(screen_px / pixel_scale) + 0.5) * pixel_scale;
	vec2 uv = snapped * texel;
	vec3 col = texture(TEXTURE, uv).rgb;

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col = (col - vec3(0.5)) * contrast + vec3(0.5);

	float dither = (bayer4(snapped) - 0.5) * dither_strength;
	col = clamp(col + vec3(dither), 0.0, 1.0);
	col = floor(col * color_levels + 0.5) / color_levels;
	col *= tint.rgb;
	float vig = length(UV - vec2(0.5));
	// 受击：中心微红 + 边缘重红。
	vec3 hurt = vec3(0.72, 0.05, 0.08);
	col = mix(col, hurt, hurt_flash * 0.28);
	col = mix(col, hurt, hurt_flash * smoothstep(0.22, 0.78, vig) * 0.72);
	// 接近警告：比受击窄一圈的橙红边缘，中心画面保持干净。
	vec3 warn = vec3(0.86, 0.30, 0.10);
	col = mix(col, warn, warn_pulse * smoothstep(0.30, 0.72, vig) * 0.85);
	// 灯光过载：加法提亮，偏暖。
	col += vec3(0.95, 0.62, 0.42) * light_flash * 0.30;
	// 解体白屏：1.0 时纯白盖满，什么都看不见（曲线由脚本驱动）。
	col = mix(col, vec3(1.0), clamp(death_flash, 0.0, 1.0));

	COLOR = vec4(col, 1.0);
}
