#version 410 core

in vec2 fTexCoord;

out vec4 FragColor;

uniform sampler2D uTexture;
uniform float uTime;

// -----

const float voronoi_smooth = 0.1; // number between 0 and ~1.2

int octaves = 0;
int quadrant = 0;

float hash(in vec2 p) {
    ivec2 texp = ivec2(
        int(mod(p.x, 256.)),
        int(mod(p.y, 256.))
    );
    // return number between -1 and 1
    return -1.0 + 2.0*texelFetch(uTexture, texp, 0).x;
}

vec2 hash2(in vec2 p)
{
    // return numbers between -1 and 1
    return vec2(hash(p), hash(p + vec2(32., 18.)));
}


// value noise
// Inigo Quilez (MIT License)
// https://www.shadertoy.com/view/lsf3WH
float noise1(in vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
	
	vec2 u = f*f*(3.0 - 2.0*f);

    return mix(mix(hash(i + vec2(0.0, 0.0)), 
                   hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), 
                   hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// gradient noise
// Inigo Quilez (MIT License)
// https://www.shadertoy.com/view/XdXGW8

float noise2(in vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);

    #if 1
    // quintic smoothstep
    vec2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    #else
    // cubic smoothstep
    vec2 u = f*f*(3.0-2.0*f);
    #endif    

    return mix(mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)), 
                   dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)), 
                   dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}


// simplex noise
// Inigo Quilez (MIT License)
// https://www.shadertoy.com/view/Msf3WH
float noise3(in vec2 p)
{
    const float K1 = 0.366025404; // (sqrt(3)-1)/2;
    const float K2 = 0.211324865; // (3-sqrt(3))/6;

	vec2  i = floor(p + (p.x+p.y)*K1);
    vec2  a = p - i + (i.x+i.y)*K2;
    float m = step(a.y,a.x); 
    vec2  o = vec2(m,1.0-m);
    vec2  b = a - o + K2;
	vec2  c = a - 1.0 + 2.0*K2;
    vec3  h = max(0.5-vec3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
	vec3  n = h*h*h*h*vec3(dot(a, hash2(i+0.0)), dot(b, hash2(i+o)), dot(c, hash2(i+1.0)));
    return dot(n, vec3(70.0));
}

// voronoi
// Inigo Quilez (MIT License)
// https://www.shadertoy.com/view/ldB3zc
// The parameter w controls the smoothness
float voronoi(in vec2 x, float w)
{
    vec2 n = floor(x);
    vec2 f = fract(x);

	float dout = 8.0;
    for( int j=-2; j<=2; j++ )
    for( int i=-2; i<=2; i++ )
    {
        vec2 g = vec2(float(i), float(j));
        vec2 o = .5 + .5*hash2(n + g); // o is between 0 and 1
		
        // distance to cell		
		float d = length(g - f + o);
        
        // do the smooth min for distances		
		float h = smoothstep(-1.0, 1.0, (dout - d)/w);
	    dout = mix(dout, d, h ) - h*(1.0 - h)*w/(1.0 + 3.0*w);
    }
	
	return dout;
}

float fbm1(in vec2 p, in int octaves)
{
    // rotation matrix for fbm
    mat2 m = 2.*mat2(4./5., 3./5., -3./5., 4./5.);  
     
    float scale = 0.5;
    float f = scale * noise1(p);
    float norm = scale;
    for (int i = 0; i < octaves; i++) {
        p = m * p;
        scale *= .5;
        norm += scale;
        f += scale * noise1(p);
    }
	return 0.5 + 0.5 * f/norm;
}

float fbm2(in vec2 p, in int octaves)
{
    // rotation matrix for fbm
    mat2 m = 2.*mat2(4./5., 3./5., -3./5., 4./5.);  
     
    float scale = 0.5;
    float f = scale * noise2(p);
    float norm = scale;
    for (int i = 0; i < octaves; i++) {
        p = m * p;
        scale *= .5;
        norm += scale;
        f += scale * noise2(p);
    }
	return 0.5 + 0.5 * f/norm;
}

float fbm3(in vec2 p, in int octaves)
{
    // rotation matrix for fbm
    mat2 m = 2.*mat2(4./5., 3./5., -3./5., 4./5.);  
     
    float scale = 0.5;
    float f = scale * noise3(p);
    float norm = scale;
    for (int i = 0; i < octaves; i++) {
        p = m * p;
        scale *= .5;
        norm += scale;
        f += scale * noise3(p);
    }
	return 0.5 + 0.5 * f/norm;
}

float fbm4(in vec2 p, in int octaves)
{
    // rotation matrix for fbm
    mat2 m = 2.*mat2(4./5., 3./5., -3./5., 4./5.);  
     
    float scale = 0.5;
    float f = 2. * scale * (voronoi(p, voronoi_smooth) - .5);
    float norm = scale;
    for (int i = 0; i < octaves; i++) {
        p = m * p;
        scale *= .5;
        norm += scale;
        f += 2. * scale * (voronoi(p, voronoi_smooth) - .5);
    }
	return 0.5 + 0.5 * f/norm;
}

// color correction
// Taken from Matt Ebb (MIT license): https://www.shadertoy.com/view/fsSfDW
// Originally from: https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/

vec3 s_curve(vec3 x)
{
    const float a = 2.51f;
    const float b = 0.03f;
    const float c = 2.43f;
    const float d = 0.59f;
    const float e = 0.14f;
    x = max(x, 0.0);
    return clamp((x*(a*x+b))/(x*(c*x+d)+e),0.0,1.0);
}

// ----------------------------------------------------

// float fbm(in vec2 p)
// {
//     if (quadrant == 0) return fbm1(p, octaves);
//     if (quadrant == 1) return fbm2(0.7*p, octaves);
//     if (quadrant == 2) return fbm3(0.5*p, octaves);
//     return fbm4(0.5*p, octaves); 
// }

// void main_2()
// {
//     vec2 uv = 2.0 * fTexCoord - vec2(1,1);

//     vec2 p = 2.*vec2(4., 4.)*uv + .1*uTime*vec2(4., 2.);
    
//     float t = 4.*fract(.1*uTime);
//     octaves = int(floor(t));
//     quadrant += uv.x >= 0. ? 1 : 0;
//     quadrant += uv.y >= 0. ? 0 : 2;
    

//     vec3 col = vec3(0);
//     col += fbm(p);
    
//     col *= smoothstep(0.003, 0.005, abs(uv.x));
//     col *= smoothstep(0.0025, 0.0045, abs(uv.y));

//     FragColor = vec4(col,1.0);
// }

// ----------------------------------------------------

// red yellow
vec3 stripescol1(in float f)
{
    return .47 + .4 * sin(1.3*f*f + vec3(2.3) + vec3(0., .55, 1.4));
}

// deep red
vec3 stripescol2(in float f)
{
    return .5 + .4 * sin(1.4*f*f + vec3(2.5) + vec3(0., .6, .9));
}

// light yellow
vec3 stripescol3(in float f)
{
    return .7 + .3 * sin(1.4*f*f + vec3(1.7) + vec3(0., .5, .8));
}

vec3 stripes(in vec2 p)
{
    float f;
    
    // #if WOOD_TYPE == 1
    // f = fbm1(vec2(2.2*p.y, 0), 1);
    // return stripescol3(f);
    // #endif
    
    //#if WOOD_TYPE == 2
    f = fbm2(vec2(4.*p.y, 0), 2);
    return stripescol2(f);
    //#endif
    
    // #if WOOD_TYPE == 3
    // f = fbm3(vec2(4.*p.y, 0), 0);
    // return stripescol3(f);
    // #endif
    
    // f = fbm1(vec2(3.*p.y, 0), 1);
    // return stripescol1(f);    
}

mat2 rotmat(in float theta)
{
    float cc = cos(theta);
    float ss = sin(theta);
    return mat2(cc, ss, -ss, cc);
}

vec3 treerings(in vec2 uv)
{
    vec2 p = vec2(2.5, 10.)*uv + vec2(50., 5.);
    p = rotmat(2.*fbm1(p, 0)/length(p)) * p;
    //p = rotmat(fbm1(.12*p, 2)) * p;
    return stripes(1.*p);
}

vec3 discoloration(in vec2 uv)
{
    vec2 p = .5*vec2(1., 2.)*uv;
    float f = fbm2(p, 2);
    return .6 + .6 * sin(2.3*f + vec3(1.4) + vec3(0., .4, 1.));
}

float finegrain(in vec2 uv)
{
    vec2 p = 3.*vec2(4., 50.)*uv;
    float f = fbm3(0.5*p, 4);
    return 1. - .4*f*(1. - smoothstep(.35, .45, f));
}

vec3 panel_adj(in vec2 uv, in float width, in float height)
{
    float j = floor(uv.y / height);
    float t = fract(uv.y / height);
    float i = floor(uv.x / width + .33*mod(j, 3.));
    float s = fract(uv.x / width + .33*mod(j, 3.));
    
    vec2 off = 100. * hash2(vec2(i, j));
    
    float asp = width/height;
    float gapw = .0017;
    
    float w = smoothstep(.5, .5 - gapw, abs(s - .5)) * smoothstep(.5, .5 - asp*gapw, abs(t - .5));
    float f = fbm3(uv + off, 0);
    w = mix(sqrt(f), 1., w);
    
    return vec3(off, w);
}

void main()
{
    vec2 uv = 2.0 * fTexCoord - vec2(1,1);

    //uv += .1*uTime*vec2(2., 1.);

    vec3 panel = panel_adj(uv, 1.5, .1);
    uv += panel.xy;

    vec3 col = vec3(0);
    col += treerings(uv);
    col *= finegrain(uv);
    col *= discoloration(uv);
    col *= panel.z;

    // tone map
    col = s_curve(col);
    
    FragColor = vec4(col,1.0);
}
