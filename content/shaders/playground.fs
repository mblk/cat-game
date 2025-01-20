#version 410 core

in vec4 fColor;
in vec2 fTexCoord;

out vec4 FragColor;

uniform float uTime;

float circle(vec2 uv, vec2 p, float r, float b)
{
    uv -= p; // translate coord system

    float dist = length(uv);
    float mask = smoothstep(r, r-b, dist);
    
    return mask;
}

float smiley(vec2 uv, vec2 p, float size)
{
    uv -= p; // translate coord system
    uv /= size; // scale coord system

    float mask = 0.0;

    // big circle
    mask += circle(uv, vec2(0.0, 0.0), 0.3, 0.01);
    
    // eyes
    mask -= circle(uv, vec2(-0.1, 0.1), 0.05, 0.01);
    mask -= circle(uv, vec2( 0.1, 0.1), 0.05, 0.01);
    
    // mouth
    float mouth_mask = 0.0;
    mouth_mask += circle(uv, vec2(0.0, 0.0), 0.2, 0.01);
    mouth_mask -= circle(uv, vec2(0.0, 0.05), 0.2, 0.01);
    mouth_mask = clamp(mouth_mask, 0.0, 1.0);
    mask -= mouth_mask;

    return mask;
}

float band(float t, float start, float end, float blur)
{
    float step1 = smoothstep(start - blur, start + blur, t);
    //float step2 = 1.0 - smoothstep(end - blur, end + blur, t);
    float step2 = smoothstep(end + blur, end - blur, t);
    float mask = step1 * step2;
    
    return mask;
}

float rect(vec2 uv, vec2 p, vec2 size, float blur)
{
    vec2 hs = size * 0.5;
    float left = p.x - hs.x;
    float right = p.x + hs.x;
    float bottom = p.y - hs.y;
    float top = p.y + hs.y;
    
    float mask1 = band(uv.x, left, right, blur);
    float mask2 = band(uv.y, bottom, top, blur);
    float mask = mask1 * mask2;
    
    return mask;
}

void main()
{
    vec2 uv = fTexCoord;

    uv -= 0.5;
    uv *= 2;
    // x -1..+1
    // y -1..+1

    // distortion effect
    float x = uv.x;
    float y = uv.y;
    
    x += sin(y * 100.0 + uTime * 5.0) * 0.02;
    y += sin(x * 50.0) * 0.01;
    
    uv = vec2(x, y);

    // content
    vec3 color = vec3(0.0);
    
    color += smiley(uv, vec2(0.3, 0), 1.0);
    color += smiley(uv, vec2(-0.3, -0.2), 0.7);
    color += band(uv.x, -0.7, -0.6, 0.005);
    color += rect(uv, vec2(-0.25, 0.2), vec2(0.3, 0.2), 0.03);
    color += rect(uv, vec2(0.75, 0.2), vec2(0.1, 0.5), 0.001);
    
    color *= vec3(0.5 + uv.x, 0.5 + uv.y, 0.5 - uv.x);
    
    FragColor = vec4(color, 1);    
}