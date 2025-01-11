#version 410 core

in vec4 fColor;

out vec4 FragColor;

void main()
{
    vec2 coord = gl_PointCoord - vec2(0.5);  //from [0,1] to [-0.5,0.5]
    
    float c = sqrt(1.0 - length(coord)*2);

    if (length(coord) > 0.5) {
        discard;
    } else {
        FragColor = fColor * vec4(c, c, c, 1.0);
    }
}