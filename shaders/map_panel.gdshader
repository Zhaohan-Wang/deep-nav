shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 grid_color : source_color = vec4(0.24, 0.62, 0.64, 0.16);
uniform vec2 canvas_size = vec2(1920.0, 1080.0);
uniform vec2 grid_origin_px = vec2(960.0, 540.0);
uniform float grid_size_px = 64.0;
uniform float line_width_px = 1.0;

void fragment() {
	vec2 pixel = UV * canvas_size;
	vec2 grid = abs(fract((pixel - grid_origin_px) / max(grid_size_px, 1.0) + 0.5) - 0.5) * grid_size_px;
	float line = 1.0 - smoothstep(line_width_px, line_width_px + 0.9, min(grid.x, grid.y));
	vec2 edge_distance = min(pixel, canvas_size - pixel);
	float border = 1.0 - smoothstep(1.0, 2.0, min(edge_distance.x, edge_distance.y));
	float alpha = max(line * 0.55, border);
	COLOR = vec4(grid_color.rgb, grid_color.a * alpha);
}
