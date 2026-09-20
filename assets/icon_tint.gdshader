shader_type canvas_item;
// Перекраска монохромной иконки в любой цвет.
// Яркость пикселя становится прозрачностью, поэтому шейдер одинаково
// работает и с белым по прозрачному, и с белым по чёрному фону —
// не важно, как именно экспортирован исходник.
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float lum = max(max(src.r, src.g), src.b);
	COLOR = vec4(tint.rgb, tint.a * src.a * lum);
}
