#version 450

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;

layout(location = 0) out vec3 out_color;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
} pc;

void main() {
    gl_Position = pc.mvp * vec4(position, 1.0);
    out_color = 1.0 - color;
}