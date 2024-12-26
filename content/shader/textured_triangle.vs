#version 410 core

layout (location = 0) in vec2 vPos;
layout (location = 1) in vec4 vColor;
layout (location = 2) in vec2 vTexCoord;
layout (location = 3) in uint vTexId;

out vec4 fColor;
out vec2 fTexCoord;
flat out uint fTexId;

uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProjection;

void main()
{
    gl_Position = uProjection * uView * uModel * vec4(vPos.xy, -1.0, 1.0);
    fColor = vColor;
    fTexCoord = vTexCoord;
    fTexId = vTexId;
}
