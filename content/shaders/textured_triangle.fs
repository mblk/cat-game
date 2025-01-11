#version 410 core

in vec4 fColor;
in vec2 fTexCoord;
flat in uint fTexId;

uniform sampler2D uTextures[16];

out vec4 FragColor;

void main()
{
    vec4 c = texture(uTextures[fTexId], fTexCoord) * fColor;

    c.r *= 1.1;

    if (c.a < 0.5) {
        discard;
    } else {
        FragColor = c;
    }

    //FragColor = vec4(1,1,1,1);
}
