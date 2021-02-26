#ifndef VOLUME_COMMON
#define VOLUME_COMMON

/**
  Common tab contains all the control values for the terrain, clouds, sky etc, along
  with all the helper functions used in multiple buffers. 
*/

#define PI 3.1415926535

#define SAT(x) clamp(x, 0., 1.)

#define TERRAIN_FREQ 0.1
#define TERRAIN_HEIGHT 3.0
#define HQ_OCTAVES 12
#define MQ_OCTAVES 7

#define CAMERA_NEAR 0.001
#define CAMERA_FAR 200.0
#define CAMERA_FOV 75.0
#define CAMERA_HEIGHT 1.6
#define CAMERA_PITCH 0.15
#define CAMERA_ZOOM -2.0
#define CAMERA_DEPTH -1125.0

#define FOG_B 0.3
#define FOG_C 0.1

#define SUN_INTENSITY 6.66
#define SUN_COLOR float3(1.2, 1.0, 0.6)
#define SKY_COLOR float3(0.25, 0.5, 1.75)
#define SUN_SPEED 0.04

#define EARTH_RADIUS 6378100.0 
#define CLOUD_BOTTOM 2500.0
#define CLOUD_TOP 4200.0
#define CLOUD_COVERAGE 0.555 // lower means more cloud coverage, and vice versa
#define CLOUD_BASE_FREQ 0.00006
#define CLOUD_DETAIL_FREQ 0.0018
#define CLOUD_STEPS 18
#define CLOUD_LIGHT_STEPS 6
#define CLOUD_TOP_OFFSET 250.0
#define CLOUD_ABSORPTION_TOP 1.8
#define CLOUD_ABSORPTION_BOTTOM 3.6

#define WIND_DIR float3(0.4, 0.1, 1.0)
#define WIND_SPEED 75.0

#define CLOUDS_AMBIENT_TOP float3(1.0, 1.2, 1.6)
#define CLOUDS_AMBIENT_BOTTOM float3(0.6, 0.4, 0.8)

#define BAYER_LIMIT 16
#define BAYER_LIMIT_H 4

#define iResolution _ScreenParams

// 4 x 4 Bayer matrix
const int bayerFilter[BAYER_LIMIT] = 
{
	0,  8,  2, 10,
   12,  4, 14,  6,
    3, 11,  1,  9,
   15,  7, 13,  5
};

struct Ray
{
	float3 origin;
	float3 direction;   
};

struct RayHit
{
	float4 position;
	float3 normal;
	float3 color;
};

Ray createRay(float3 origin,float3 direction)
{
	Ray ray;
	ray.origin=origin;
	ray.direction=direction;
	return ray;
}

RayHit CreateRayHit()
{
	RayHit hit;
	hit.position = float4(0.0f, 0.0f, 0.0f,0.0f);
	hit.normal = float3(0.0f, 0.0f, 0.0f);
	hit.color = float3(0.0f, 0.0f, 0.0f);
	return hit;
}

//-------------------------------------------------------------------------------------
//  Helper functions
//-------------------------------------------------------------------------------------
    
float remap(float x, float a, float b, float c, float d)
{
    return (((x - a) / (b - a)) * (d - c)) + c;
}

float remap01(float x, float a, float b)
{
	return ((x - a) / (b - a));   
}

bool writeToPixel(float2 fragCoord, int iFrame)
{
    float2 iFragCoord = float2(fragCoord);
    int index = iFrame % BAYER_LIMIT;
    return (iFragCoord.x + BAYER_LIMIT_H * iFragCoord.y) % BAYER_LIMIT == bayerFilter[index];
		
}

//-------------------------------------------------------------------------------------
//  Camera stuff
//-------------------------------------------------------------------------------------

float3x3 getCameraMatrix(float3 origin, float3 target)
{
    float3 lookAt = normalize(target - origin);
    float3 right = normalize(cross(lookAt, float3(0.0, 1.0, 0.0)));
    float3 up = normalize(cross(right, lookAt));
    return float3x3(right, up, -lookAt);
}

Ray getCameraRay(float2 uv, float t)
{
	Ray ray = (Ray)0;
    uv *= (CAMERA_FOV / 360.) * PI; // fov
    float3 origin = float3(0., CAMERA_HEIGHT, CAMERA_DEPTH);
    float3 target = float3(0., origin.y + CAMERA_PITCH,  CAMERA_DEPTH - 1.2);
    float3x3 camera = getCameraMatrix(origin, target);
	float3 direction = mul(camera, float3(uv, CAMERA_ZOOM));
	ray.origin = origin;
	ray.direction = direction;
    return ray;
}

float3 getSun(float2 mouse, float iTime)
{
    float2 sunPos = mouse;
    
    if (mouse.y < -0.95)
    {
        sunPos = float2(cos(fmod(iTime * SUN_SPEED, PI)) * .7, 0.);
    	sunPos.y = 1. - 3.05 * sunPos.x * sunPos.x;
    }
    
    float sunHeight = (max(0., sunPos.y * .75 + .25));
    
    return float3(sunPos, sunHeight);
}

//-------------------------------------------------------------------------------------
//  Atmospheric Scattering
//-------------------------------------------------------------------------------------

/** Slightly modified version of robobo1221's fake atmospheric scattering
 	(https://www.shadertoy.com/view/4tVSRt)
*/

float3 miePhase(float dist, float3 sunL)
{
    return max(exp(-pow(dist, 0.3)) * sunL - 0.4, 0.0);
}

float3 atmosphericScattering(float2 uv, float2 sunPos, bool isSun)
{
    
    float sunDistance = distance(uv, sunPos);
	float scatterMult = SAT(sunDistance);
	float dist = uv.y;
	dist = (.5 * lerp(scatterMult, 1., dist)) / dist;
    float3 mieScatter = miePhase(sunDistance, 0) * SUN_COLOR;
	float3 color = dist * SKY_COLOR;
    color = max(color, 0.);
    float3 sun = .0002 / pow(length(uv-sunPos), 1.7) * SUN_COLOR;
    
	color = max(lerp(pow(color, .8 - color),
	color / (2. * color + .5 - color * 1.3),
	SAT(sunPos.y * 2.5)), 0.)
	+ (isSun ? (sun + mieScatter) : 0);
    
	color *=  (pow(1. - scatterMult, 5.) * 10. * SAT(.666 - sunPos.y)) + 1.5;
	float underscatter = distance(sunPos.y, 1.);
	color = lerp(color, 0, SAT(underscatter));
	
	return color;	
}

//-------------------------------------------------------------------------------------
//  Hash Functions
//-------------------------------------------------------------------------------------
    
// Hash functions by Dave_Hoskins
// TODO

float3 hash33( float3 p )
{
	p = float3( dot(p, float3(127.1, 311.7, 74.7)),
                dot(p, float3(269.5, 183.3, 246.1)),
                dot(p, float3(113.5, 271.9, 124.6)));

	return frac(sin(p) * 43758.5453123);
}

float hash13(float3 p)
{
	float h = dot(p,float3(127.1,311.7, 74.7));
    
	return -1.0 + 2.0 * frac(sin(h) * 43758.5453123);
}

float2 hash22(float2 value)
{
	float2 pos = float2(dot(value, float2(127.1, 337.1)), dot(value, float2(269.5, 183.3)));
	pos = frac(sin(pos) * 43758.5453123);
	return pos;
}

float hash12(float2 p)
{
	return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

//-------------------------------------------------------------------------------------
// Noise generation
//-------------------------------------------------------------------------------------

float valueNoise(float3 x, float freq)
{
	float3 i = floor(x);
	float3 f = frac(x);
	f = f * f * (3.0 - 2.0 * f);
	
	return lerp(lerp(lerp(hash13(fmod(i + float3(0, 0, 0), freq)),  
                       hash13(fmod(i + float3(1, 0, 0), freq)), f.x),
                   lerp(hash13(fmod(i + float3(0, 1, 0), freq)),  
                       hash13(fmod(i + float3(1, 1, 0), freq)), f.x), f.y),
               lerp(lerp(hash13(fmod(i + float3(0, 0, 1), freq)),  
                       hash13(fmod(i + float3(1, 0, 1), freq)), f.x),
                   lerp(hash13(fmod(i + float3(0, 1, 1), freq)),  
                       hash13(fmod(i + float3(1, 1, 1), freq)), f.x), f.y), f.z);
}

// Tileable 3D worley noise
float worleyNoise(float3 uv, float freq, bool tileable)
{    
	float2 index = floor(uv);
	float2 pos = frac(uv);
	float d = 1.5;
	for(int i = -1; i < 2; i++)
	for (int j = -1; j < 2; j++)
	{
		float2 p = hash22(index + float2(i, j));
		float dist = length(p + float2(i, j) - pos);
		d = min(dist, d);
	}
    
    // inverted worley noise
    return 1.0 - d;
}

// Fbm for Perlin noise based on iq's blog
float perlinFbm(float3 p, float freq, int octaves)
{
    float G = exp2(-0.85);
    float amp = 1.0;
    float noise = 0.0;
    for (int i = 0; i < octaves; ++i)
    {
        noise += amp * valueNoise(p * freq, freq);
        freq *= 2.0;
        amp *= G;
    }
    
    return noise;
}

// Tileable Worley fbm inspired by Andrew Schneider's Real-Time Volumetric Cloudscapes
// chapter in GPU Pro 7.
float worleyFbm(float3 p, float freq, bool tileable)
{
    float fbm = worleyNoise(p * freq, freq, tileable) * 0.625 +
        	 	worleyNoise(p * freq * 2.0, freq * 2.0, tileable) * 0.25 +
        	 	worleyNoise(p * freq * 4.0, freq * 4.0, tileable) * 0.125;
    return max(0.0, fbm * 1.1 - 0.1);
}


#endif