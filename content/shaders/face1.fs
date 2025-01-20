#version 410 core

in vec4 fColor;
in vec2 fTexCoord;

out vec4 FragColor;

uniform float uTime;

// ---
const vec4 c_outline_color = vec4(0, 0, 0, 1);

const vec4 c_face_color1 = vec4(160.0 / 255.0, 160.0 / 255.0, 160.0 / 255.0, 1);
const vec4 c_face_color2 = vec4(230.0 / 255.0, 230.0 / 255.0, 230.0 / 255.0, 1);

const vec4 c_eye_color1 = vec4(230.0 / 255.0, 230.0 / 255.0, 230.0 / 255.0, 1);
const vec4 c_eye_color2 = vec4(77.0 / 255.0, 165.0 / 255.0, 88.0 / 255.0, 1);
const vec4 c_eye_color3 = vec4(0, 0, 0, 1);

const vec4 c_nose_color = vec4(127.0 / 255.0, 75.0 / 255.0, 43.0 / 255.0, 1);

const vec4 c_ear_color1 = vec4(160.0 / 255.0, 160.0 / 255.0, 160.0 / 255.0, 1);
const vec4 c_ear_color2 = vec4(240.0 / 255.0, 175.0 / 255.0, 175.0 / 255.0, 1);

const float c_outline_width = 0.05;
const float c_face_radius = 0.75;
const float c_eye_radius = 0.2;
const float c_nose_radius = 0.12;

const float c_ear_radius = 0.25;
// ---

float circle(vec2 uv, vec2 p, float r, float b)
{
    uv -= p; // translate coord system

    float dist = length(uv);
    float mask = smoothstep(r, r-b, dist);
    
    return mask;
}

float ellipse(vec2 uv, vec2 p, float r, vec2 ell, float b)
{
    uv -= p; // translate coord system

    // ell<1: widen
    // ell>1: squeeze
    uv.x *= ell.x;
    uv.y *= ell.y;

    float dist = length(uv);
    float mask = smoothstep(r, r-b, dist);
    
    return mask;
}

float nose_shape(vec2 uv, vec2 p, float r, float b)
{
    uv -= p; // translate coord system

    float y1 = uv.y * 1.5; // top
    float y0 = uv.y + -abs(uv.x + 0.0) * 0.5; // bottom

    float y = mix(y0, y1, clamp( (uv.y + r) / r, 0, 1));
    uv.y = y;

    uv.y *= 1.1;

    float dist = length(uv);
    float mask = smoothstep(r, r-b, dist);
    
    return mask;
}

float ear_shape(vec2 uv, vec2 p, float r, float b, vec2 n)
{
    // n: outside

    uv -= p; // translate coord system

    // express uv in terms of distance from normal and tangent
    vec2 t = vec2(n.y, -n.x);

    float n_dist = dot(n, uv);
    float t_dist = dot(t, uv);

    n_dist += abs(t_dist);

    uv = t * t_dist + n * n_dist;

    // circle
    float dist = length(uv);
    float mask = smoothstep(r, r-b, dist);
    
    return mask;
}

float mouth_lines(vec2 uv, vec2 p, float r, float b)
{
    uv -= p; // translate coord system

    uv.x *= 0.8;

    float s = sign(uv.y); // -1 +1
    s -= 1; // -2 0
    s /= 2; // -1 0
    s *= -1; // 1 0

    float dist = length(uv);
    
    float mask1 = smoothstep(r, r-b, dist);
    float mask2 = smoothstep(r-0.02, r-0.02+b, dist);
    float mask = mask1 * mask2;

    mask *= s;
    
    return mask;
}

vec4 eye(vec2 uv, vec2 p, vec2 n)
{
    // n: outside

    uv -= p;

    vec4 color = vec4(0, 0, 0, 0);

    vec2 ell_outline = vec2(1.1, 1.0);
    vec2 ell_inner = vec2(1.15, 1.0);

    // outline
    color = mix(color, c_outline_color, ellipse(uv, vec2(0.0, 0.03), c_eye_radius, ell_outline, 0.001));

    // outer, middle, inner
    color = mix(color, c_eye_color1, ellipse(uv, vec2(0, 0), c_eye_radius, ell_inner, 0.001));
    color = mix(color, c_eye_color2, ellipse(uv, vec2(0.01, -0.02), c_eye_radius * 0.8, ell_inner, 0.001));
    color = mix(color, c_eye_color3, ellipse(uv, vec2(0.02, -0.04), c_eye_radius * 0.6, ell_inner, 0.001));

    // light reflection
    color = mix(color, vec4(1,1,1,1), circle(uv, vec2(0.07, 0.07), c_eye_radius * 0.2, 0.001));

    return color;
}

vec4 nose(vec2 uv, vec2 p)
{
    uv -= p;

    vec4 color = vec4(0, 0, 0, 0);

    // nose
    color = mix(color, c_outline_color, nose_shape(uv, vec2(0.0, 0.0), c_nose_radius, 0.001));
    color = mix(color, c_nose_color, nose_shape(uv, vec2(0.0, 0.0), c_nose_radius * 0.8, 0.001));

    // mouth
    color = mix(color, c_outline_color,
        mouth_lines(uv, vec2(c_nose_radius * 1.15, -c_nose_radius * 0.8), c_nose_radius, 0.001));
    color = mix(color, c_outline_color,
        mouth_lines(uv, vec2(-c_nose_radius * 1.15, -c_nose_radius * 0.8), c_nose_radius, 0.001));

    return color;
}

vec4 ear(vec2 uv, vec2 p)
{
    uv -= p;

    vec4 color = vec4(0, 0, 0, 0);

    vec2 n_right = normalize(vec2(1, 2));
    vec2 n_left = normalize(vec2(-1, 2));

    color = mix(color, c_outline_color, ear_shape(uv, vec2(0.5, 0.7), c_ear_radius, 0.001, n_right));
    color = mix(color, c_outline_color, ear_shape(uv, vec2(-0.5, 0.7), c_ear_radius, 0.001, n_left));

    color = mix(color, c_ear_color1, ear_shape(uv * 1.1, vec2(0.51, 0.7), c_ear_radius, 0.001, n_right));
    color = mix(color, c_ear_color1, ear_shape(uv * 1.1, vec2(-0.51, 0.7), c_ear_radius, 0.001, n_left));

    color = mix(color, c_ear_color2, ear_shape(uv * 1.22, vec2(0.52, 0.7), c_ear_radius, 0.001, n_right));
    color = mix(color, c_ear_color2, ear_shape(uv * 1.22, vec2(-0.52, 0.7), c_ear_radius, 0.001, n_left));

    //color = mix(color, c_face_color1, ear_shape(uv + n_left * 0.1, vec2(-0.5, 0.7), c_ear_radius, 0.001, n_left));

    return color;
}

vec4 face(vec2 uv, vec2 p, float size)
{
    uv -= p; // translate coord system
    uv /= size; // scale coord system

    vec4 color = vec4(0, 0, 0, 0);

    // head
    float full_mask = circle(uv, vec2(0, 0), c_face_radius, 0.001); // full face incl. outline
    float inner_mask = circle(uv, vec2(0, 0), c_face_radius - c_outline_width, 0.001); // face without outline
    float inner_mask2 = circle(uv, vec2(0, -0.7), c_face_radius * 0.7, 0.001) * inner_mask; // face color2

    color = mix(color, c_outline_color, full_mask);
    color = mix(color, c_face_color1, inner_mask);
    color = mix(color, c_face_color2, inner_mask2);
    
    // eyes
    vec4 temp = eye(uv, vec2(0.35, 0.05), vec2(1, 0));
    color = mix(color, temp, temp.a);

    temp = eye(uv, vec2(-0.35, 0.05), vec2(-1, 0));
    color = mix(color, temp, temp.a);

    // nose and mouth
    temp = nose(uv, vec2(0, -0.2));
    color = mix(color, temp, temp.a);

    // ears
    temp = ear(uv, vec2(0.0, 0.0));
    color = mix(color, temp, temp.a * (1.0 - full_mask));

    

    return color;
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
    // float x = uv.x;
    // float y = uv.y;
    
    // x += sin(y * 100.0 + uTime * 5.0) * 0.02;
    // y += sin(x * 50.0) * 0.01;
    
    // uv = vec2(x, y);

    // content
    //vec3 color = vec3(0.0);
    
    //color += face(uv, vec2(0, 0), 1.0);
    //color += smiley(uv, vec2(-0.3, -0.2), 0.7);
    //color += band(uv.x, -0.7, -0.6, 0.005);
    //color += rect(uv, vec2(-0.25, 0.2), vec2(0.3, 0.2), 0.03);
    //color += rect(uv, vec2(0.75, 0.2), vec2(0.1, 0.5), 0.001);
    
    //color *= vec3(0.5 + uv.x, 0.5 + uv.y, 0.5 - uv.x);
    
    vec4 color = vec4(0, 0, 0, 0);

    color += face(uv, vec2(0, 0), 1.0);

    if (color.a < 0.1) {
        discard;
    }

    FragColor = vec4(color.xyz, 1.0);
}

