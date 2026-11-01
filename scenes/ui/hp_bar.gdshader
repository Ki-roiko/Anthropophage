shader_type canvas_item;

uniform float progress: hint_range(0.0, 1.0) = 1.0;
uniform float progress_tail: hint_range(0.0, 1.0, 0.1) = 1.0;
uniform vec3 tail_color: source_color = vec3(1.0);

void fragment() {
	COLOR.a = UV.x > progress_tail ? 0.0 : COLOR.a;
	COLOR.rgb = UV.x > progress && UV.x < progress_tail ? tail_color: COLOR.rgb;
}
