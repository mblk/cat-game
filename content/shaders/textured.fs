#version 410 core

in vec4 fColor;
in vec2 fTexCoord;

uniform sampler2D uTexture;

out vec4 FragColor;

void main()
{
    vec4 c = texture(uTexture, fTexCoord) * fColor;

    //c.r *= 1.1;

    if (c.a < 0.5) {
        discard;
    } else {
        FragColor = c;
    }
}
