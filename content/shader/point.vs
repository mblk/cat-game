#version 410 core

layout (location = 0) in vec2 vPos;
layout (location = 1) in vec4 vColor;
layout (location = 2) in float vSize;
layout (location = 3) in float vScale;

out vec4 fColor;

uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProjection;

uniform vec2 uViewportSize;

void main()
{
    gl_Position = uProjection * uView * uModel * vec4(vPos.xy, -1.0, 1.0);
    
    float pixelSize = vSize;
    float worldSize = uViewportSize.y * uProjection[1][1] * vSize;

    // Interpolate between the two sizes
    // scale=0 -> use pixelSize
    // scale=1 -> use worldSize
    gl_PointSize = mix(pixelSize, worldSize, vScale);
    
    fColor = vColor;
}
