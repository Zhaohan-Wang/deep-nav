// 视口天空与地图共用的像素星星形状。
// local_px：相对星星中心的像素坐标（已 floor）。
// shape：0 单点 / 1 二乘二块 / 2 十字 / 3 大十字闪光。

int star_pick_shape(float h) {
	if (h > 0.92) {
		return 3;
	}
	if (h > 0.74) {
		return 2;
	}
	if (h > 0.45) {
		return 1;
	}
	return 0;
}

float star_mask(vec2 local_px, int shape) {
	vec2 p = floor(local_px + vec2(0.001));
	float ax = abs(p.x);
	float ay = abs(p.y);
	if (shape == 0) {
		return float(ax < 0.5 && ay < 0.5);
	}
	if (shape == 1) {
		return float(p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0);
	}
	if (shape == 2) {
		return float((ax < 0.5 && ay <= 2.0) || (ay < 0.5 && ax <= 2.0));
	}
	float plus = float((ax < 0.5 && ay <= 3.0) || (ay < 0.5 && ax <= 3.0));
	float core = float(ax <= 1.0 && ay <= 1.0);
	return max(plus, core);
}

vec3 star_tint_from(float h) {
	if (h > 0.85) {
		return vec3(0.95, 0.92, 0.78);
	}
	if (h > 0.55) {
		return vec3(0.72, 0.86, 1.0);
	}
	return vec3(0.62, 0.70, 0.88);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash22(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453);
}
