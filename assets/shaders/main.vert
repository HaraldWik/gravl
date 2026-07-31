#version 450

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;

layout(location = 0) out vec3 out_color;

layout(push_constant) uniform PushConstants {
    vec3 offset;
} pc;

void main() {
    gl_Position = vec4(position + pc.offset, 1.0);
    out_color = color;
}