shader_type canvas_item;

uniform float blur_factor : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    float blur_radius = mix(0.005, 0.01, blur_factor);

    float alpha = 0.0;
    int samples = 0;
    for (float x = -blur_radius; x <= blur_radius; x += blur_radius / 4.0) {
        for (float y = -blur_radius; y <= blur_radius; y += blur_radius / 4.0) {
            alpha += texture(TEXTURE, UV + vec2(x, y)).a;
            samples += 1;
        }
    }
    alpha /= float(samples);

    float shadow_alpha = mix(0.7, 0.4, blur_factor);

    COLOR = vec4(0.0, 0.0, 0.0, alpha * shadow_alpha);
}