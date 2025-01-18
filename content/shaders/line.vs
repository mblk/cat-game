#version 410 core

layout (location = 0) in vec3 vPos;
layout (location = 1) in vec4 vColor;

out vec4 fColor;

uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProjection;

void main()
{
    gl_Position = uProjection * uView * uModel * vec4(vPos.xyz, 1.0);
    fColor = vColor;
}
