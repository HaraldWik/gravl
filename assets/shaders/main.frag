#version 450

layout(location = 0) in vec2 in_uv;
layout(location = 1) in vec3 in_normal;

layout(location = 0) out vec4 out_color;

void main() {
    vec3 base = vec3(in_uv, 1.0 - in_uv.x);

    vec3 N = normalize(in_normal);
    vec3 L = normalize(vec3(0.4, 0.8, 0.6));

    float light = 0.7 + 0.3 * max(dot(N, L), 0.0);

    out_color = vec4(base * light, 1.0);
}