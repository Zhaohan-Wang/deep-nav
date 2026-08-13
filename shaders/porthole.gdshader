shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float scanline_strength : hint_range(0.0, 1.0) = 0.28;
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.35;
uniform float noise_strength : hint_range(0.0, 0.2) = 0.04;
uniform vec4 tint : source_color = vec4(0.75, 0.92, 1.0, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float scan = sin(UV.y * 78.0 * 3.14159);
	col.rgb *= 1.0 - scanline_strength * (0.5 - 0.5 * scan);
	vec2 centered = UV - vec2(0.5);
	float vig = 1.0 - dot(centered, centered) * vignette_strength;
	col.rgb *= clamp(vig, 0.15, 1.0);
	float n = hash(UV * 240.0 + vec2(TIME * 8.0, TIME * 3.0));
	col.rgb += (n - 0.5) * noise_strength;
	col.rgb *= tint.rgb;
	COLOR = col;
}
