#version 450

layout(location = 0) out vec3 out_color;

vec3 colors[] = vec3[](
    vec3(1.0, 0.5, 0.0), // orange
    vec3(0.5, 0.0, 1.0), // purple
    vec3(0.0, 1.0, 0.5)  // teal / turquoise
);

vec3 vertices[] = vec3[](
    vec3(-0.75, 0.75, 0.0),
    vec3(0.75, 0.75, 0.0),
    vec3(0.0, -0.75, 0.0)
);

void main() {
    gl_Position = vec4(vertices[gl_VertexIndex], 1.0);
    out_color = colors[gl_VertexIndex];
}