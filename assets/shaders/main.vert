#version 450

layout(location = 0) in vec3 position;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec3 normal;

layout(location = 0) out vec2 out_uv;
layout(location = 1) out vec3 out_normal;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
} pc;

void main() {
    gl_Position = pc.mvp * vec4(position, 1.0);
    out_uv = uv;
    out_normal = normal;
}