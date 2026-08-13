shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D view_tex : source_color, filter_nearest, repeat_disable;
uniform float pitch : hint_range(0.2, 1.0) = 0.88;
uniform float top_scale : hint_range(0.4, 1.0) = 0.90;

void fragment() {
	float y0 = 1.0 - pitch;
	if (UV.y < y0) {
		discard;
	}
	float t = (UV.y - y0) / max(pitch, 0.001);
	float scale = mix(top_scale, 1.0, t);
	float x = (UV.x - 0.5) / max(scale, 0.001) + 0.5;
	if (x < 0.0 || x > 1.0) {
		discard;
	}
	COLOR = texture(view_tex, vec2(x, t));
}
