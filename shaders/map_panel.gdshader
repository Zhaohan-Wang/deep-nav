shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 grid_color : source_color = vec4(0.18, 0.55, 0.58, 0.28);
uniform float cells = 12.0;
uniform float line_width = 0.012;

void fragment() {
	vec2 uv = UV;
	vec2 grid = abs(fract(uv * cells) - 0.5);
	float line = 1.0 - step(line_width, min(grid.x, grid.y));
	float border = 1.0 - step(0.012, min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y)));
	float alpha = max(line * 0.7, border);
	COLOR = vec4(grid_color.rgb, grid_color.a * alpha);
}
