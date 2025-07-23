shader_type canvas_item;

// Основные параметры тумана
uniform float fog_intensity : hint_range(0.0, 1.0) = 0.8;
uniform vec4 fog_color : source_color = vec4(0.2, 0.2, 0.25, 1.0);
uniform float fog_edge_softness : hint_range(0.0, 200.0) = 50.0;

// Параметры анимации тумана
uniform float fog_animation_speed : hint_range(0.0, 2.0) = 0.3;
uniform float fog_noise_scale : hint_range(0.1, 10.0) = 2.0;
uniform float fog_noise_strength : hint_range(0.0, 0.5) = 0.1;

// Массивы данных о юнитах (максимум 64 юнита для оптимизации)
const int MAX_UNITS = 64;
uniform int unit_count : hint_range(0, 64) = 0;
uniform vec2 unit_positions[MAX_UNITS]; // Позиции юнитов в координатах вьюпорта
uniform float unit_visibility_radii[MAX_UNITS]; // Радиусы видимости юнитов (уже масштабированные)

// Вспомогательные функции для шума
float simple_noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float smooth_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = simple_noise(i);
    float b = simple_noise(i + vec2(1.0, 0.0));
    float c = simple_noise(i + vec2(0.0, 1.0));
    float d = simple_noise(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Вычисление видимости в координатах вьюпорта
float calculate_visibility(vec2 screen_pos) {
    float total_visibility = 0.0;

    for (int i = 0; i < min(unit_count, MAX_UNITS); i++) {
        vec2 unit_screen_pos = unit_positions[i];
        float radius = unit_visibility_radii[i];

        // Быстрая проверка расстояния без sqrt
        vec2 diff = screen_pos - unit_screen_pos;
        float distance_squared = dot(diff, diff);
        float radius_squared = radius * radius;

        if (distance_squared <= radius_squared) {
            float distance = sqrt(distance_squared);
            float edge_distance = radius - distance;
            float visibility = smoothstep(0.0, fog_edge_softness, edge_distance);
            total_visibility = max(total_visibility, visibility);
        }
    }

    return clamp(total_visibility, 0.0, 1.0);
}

void fragment() {
    // Получаем позицию в пикселях вьюпорта
    vec2 screen_pos = FRAGCOORD.xy;

    // Вычисляем базовую видимость
    float visibility = calculate_visibility(screen_pos);

    // Добавляем анимированный шум для живого тумана
    vec2 noise_uv = screen_pos * fog_noise_scale * 0.001;
    noise_uv += vec2(TIME * fog_animation_speed * 0.2, TIME * fog_animation_speed * 0.15);

    float noise = smooth_noise(noise_uv);
    noise = (noise - 0.5) * fog_noise_strength;

    // Применяем шум только к областям тумана
    float fog_alpha = (1.0 - visibility) * fog_intensity;
    fog_alpha += noise * fog_alpha;
    fog_alpha = clamp(fog_alpha, 0.0, 1.0);

    // Устанавливаем финальный цвет
    COLOR = vec4(fog_color.rgb, fog_alpha);
}