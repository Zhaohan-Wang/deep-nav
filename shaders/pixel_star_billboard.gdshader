shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled, specular_disabled, ambient_light_disabled, depth_draw_opaque;

// 面向相机的像素星星。INSTANCE_CUSTOM：x=形状, y=闪烁相位, z=像素倍率。
#include "res://shaders/star_lib.gdshaderinc"

varying vec3 inst_rgb;
varying float v_shape;
varying float v_phase;
varying float v_pix;

void vertex() {
	vec3 scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * scale.x, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * scale.y, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * scale.z, 0.0),
		MODEL_MATRIX[3]
	);
	inst_rgb = COLOR.rgb;
	v_shape = INSTANCE_CUSTOM.x;
	v_phase = INSTANCE_CUSTOM.y;
	v_pix = INSTANCE_CUSTOM.z;
}

void fragment() {
	int shape = int(v_shape + 0.1);
	float pixel_size = mix(6.0, 12.0, v_pix);
	vec2 local_px = (UV - vec2(0.5)) * pixel_size;
	float m = star_mask(local_px, shape);
	if (m < 0.5) {
		discard;
	}
	float twinkle = 0.82 + 0.18 * sin(TIME * (1.4 + v_phase * 3.0) + v_phase * 14.0);
	vec3 tint = star_tint_from(v_phase);
	ALBEDO = tint * inst_rgb * twinkle;
}
