// ReSharper disable All
#ifndef VOLUME_CLOUD
#define VOLUME_CLOUD

#include "Common.hlsl"
#include "UnityCG.cginc"

sampler2D _MainTex;
float4 _MainTex_TexelSize;
half4 _MainTex_ST;
uniform int _iFrame;

sampler2D _PerlinWorleyNoise;
float4x4 _FrustumCornorsRay;
sampler2D _LastFrameRT;

const float3 noiseKernel[6] = 
{
    float3( 0.38051305,  0.92453449, -0.02111345),
    float3(-0.50625799, -0.03590792, -0.86163418),
    float3(-0.32509218, -0.94557439,  0.01428793),
    float3( 0.09026238, -0.27376545,  0.95755165),
    float3( 0.28128598,  0.42443639, -0.86065785),
    float3(-0.16852403,  0.14748697,  0.97460106)
};

//-------------------------------------------------------------------------------------
// Clouds modeling
//-------------------------------------------------------------------------------------

float raySphereIntersect(Ray ray, float radius)
{
    // note to future me: don't need "a" bcuz rd is normalized and dot(rd, rd) = 1
    float b = 2. * dot(ray.origin, ray.direction);
    float c = dot(ray.origin, ray.origin) - radius * radius;
    float d = sqrt(b * b - 4. * c);
    return (-b + d) * .5;
}


float cloudGradient(float h)
{
    return smoothstep(0., .05, h) * smoothstep(1.25, .5, h);
}

float cloudHeightFract(float p)
{
    return (p - EARTH_RADIUS - CLOUD_BOTTOM) / (CLOUD_TOP - CLOUD_BOTTOM);
}

float cloudBase(float3 p, float y)
{
    float3 noise = tex2Dlod(_PerlinWorleyNoise, float4((p.xz - WIND_DIR.xz * _Time.y * WIND_SPEED) * CLOUD_BASE_FREQ, 0.0, 0.0)).rgb;
    float n = y * y * noise.b + pow(1.0 - y, 12.0);
    float cloud = remap01(noise.r - n, noise.g - 1., 1.0);
    return cloud;
}

float cloudDetail(float3 p, float c, float y)
{
    p -= WIND_DIR * 3.0 * _Time.y * WIND_SPEED;
    // this is super expensive :(
    float hf = worleyFbm(p, CLOUD_DETAIL_FREQ, false) * 0.625 +
               worleyFbm(p, CLOUD_DETAIL_FREQ * 2.0, false) * 0.25 +
               worleyFbm(p, CLOUD_DETAIL_FREQ * 4.0, false) * 0.125;
    hf = lerp(hf, 1.0 - hf, y * 4.0);
    return remap01(c, hf * 0.5, 1.0);
}

float getCloudDensity(float3 p, float y, bool detail)
{
    p.xz -= WIND_DIR.xz * y * CLOUD_TOP_OFFSET;
    float d = cloudBase(p, y);
    d = remap01(d, CLOUD_COVERAGE, 1.) * (CLOUD_COVERAGE);
    d *= cloudGradient(y);
    bool cloudDetailTest = (d > 0.0 && d < 0.3) && detail; 
    return ((cloudDetailTest) ? cloudDetail(p, d, y) : d);
}


//-------------------------------------------------------------------------------------
// Clouds lighting
//-------------------------------------------------------------------------------------

float henyeyGreenstein( float sunDot, float g) {
    float g2 = g * g;
    return (.25 / PI) * ((1. - g2) / pow( 1. + g2 - 2. * g * sunDot, 1.5));
}

float marchToLight(float3 p, float3 sunDir, float sunDot, float scatterHeight)
{
    float lightRayStepSize = 11.;
    float3 lightRayDir = sunDir * lightRayStepSize;
    float3 lightRayDist = lightRayDir * .5;
    float coneSpread = length(lightRayDir);
    float totalDensity = 0.;
    for(int i = 0; i < CLOUD_LIGHT_STEPS; ++i)
    {
        // cone sampling as explained in GPU Pro 7 article
        float3 cp = p + lightRayDist + coneSpread * noiseKernel[i] * float(i);
        float y = cloudHeightFract(length(p));
        if (y > .95 || totalDensity > .95) break; // early exit
        totalDensity += getCloudDensity(cp, y, false) * lightRayStepSize;
        lightRayDist += lightRayDir;
    }
    
    return 32. * exp(-totalDensity * lerp(CLOUD_ABSORPTION_BOTTOM,
                CLOUD_ABSORPTION_TOP, scatterHeight)) * (1. - exp(-totalDensity * 2.));
}

//-------------------------------------------------------------------------------------

struct Input
{
    float4 vertex : POSITION;
    float2 uv : TEXCOORD0;
};

struct v2f {
    float4 vertex : SV_POSITION;
    float2 texcoord : TEXCOORD0;
    float2 uv_depth : TEXCOORD1;
    float4 interpolatedRay : TEXCOORD2;
    float4 srcPos : TEXCOORD3;
};

v2f vertDefault(appdata_img v)
{
    v2f o;
    o.vertex = UnityObjectToClipPos(v.vertex);
    o.texcoord = v.texcoord.xy;
    o.uv_depth.xy = v.texcoord.xy;
    
    #if UNITY_UV_STARTS_AT_TOP
    if (_MainTex_TexelSize.y < 0){
        o.texcoord.y = 1 - o.texcoord.y;  
    }
    #endif

    int index = 0;
    //直接安排四个顶点对应的相机近裁面向量
    if (v.texcoord.x<0.5 && v.texcoord.y<0.5)
    {
        index = 0;
    }
    else if (v.texcoord.x>0.5 && v.texcoord.y<0.5) {
        index = 1;
    }
    else if (v.texcoord.x>0.5 && v.texcoord.y>0.5) {
        index = 2;
    }
    else {
        index = 3;
    }
    o.interpolatedRay = _FrustumCornorsRay[index];

    o.srcPos = ComputeScreenPos(o.vertex);
    
    return o;
}

half4 fragFinal(v2f input) : SV_Target
{
    float2 fragCoord = (input.srcPos.xy / input.srcPos.w) * _ScreenParams.xy;
   
    float2 uv = input.texcoord.xy;
    float4 prevCol = tex2D(_LastFrameRT, uv);
    float4 col = 0;

    //TODO 看看这里怎么改
    //bool updatePixel = writeToPixel(input.srcPos, _iFrame);
    
    //if (updatePixel) // only draw 1/16th resolution per frame
    {
        Ray ray = createRay(_WorldSpaceCameraPos,normalize(input.interpolatedRay.xyz));
        
        //float3 sun = getSun(mouse, iTime);
        float3 sun = float3(0.3, 0.7, 0.7);
        // clouds don't get blindingly bright with sun at zenith
        sun.z = clamp(sun.z, 0.0, 0.8);
        float3 sunDir = normalize(float3(sun.x, sun.z, -1.));
        float sunDot = max(0., dot(ray.direction, sunDir));
        //float sunHeight = smoothstep(.01, .1, sun.z + .025);
        float sunHeight = 0.6;
        
        //TODO 通过深度图判断
        //if (terrainDist > CAMERA_FAR)
        {
            // clouds
            ray.origin.y = EARTH_RADIUS;
            float start = raySphereIntersect(ray, EARTH_RADIUS + CLOUD_BOTTOM);
            float end = raySphereIntersect(ray, EARTH_RADIUS + CLOUD_TOP);
            float cameraRayDist = start;
            float cameraRayStepSize = (end - start) / float(CLOUD_STEPS);
            
            // blue noise offset
            cameraRayDist += cameraRayStepSize;
            //cameraRayDist += cameraRayStepSize * texelFetch(iChannel3, (ivec2(fragCoord) + _iFrame * float2(113, 127)) & 1023, 0).r;

            float3 skyCol = atmosphericScattering(float2(0.15, 0.05),
                                float2(0.5, sun.y * 0.5 + 0.25), false);
            skyCol.r *= 1.1;
			skyCol = SAT(pow(skyCol * 2.1, 4.2));
            float sunScatterHeight = smoothstep(0.15, 0.4, sun.z);
            float hgPhase = lerp(henyeyGreenstein(sunDot, 0.4), henyeyGreenstein(sunDot, -0.1), 0.5);
            // sunrise/sunset hack
            hgPhase = max(hgPhase, 1.6 * henyeyGreenstein(sqrt(sunDot), SAT(.8 - sunScatterHeight)));
            // shitty night time hack
            //hgPhase = lerp(pow(sunDot, 0.25), hgPhase, sunHeight);
            
            float4 intScatterTrans = float4(0., 0., 0., 1.);
            float3 ambient = 0;
            for (int i = 0; i < CLOUD_STEPS; ++i)
            {
                float3 p = ray.origin + cameraRayDist * ray.direction;
                float heightFract = cloudHeightFract(length(p));
                float density = getCloudDensity(p, heightFract, true);
                if (density > 0.)
                {
                    ambient = lerp(CLOUDS_AMBIENT_BOTTOM, CLOUDS_AMBIENT_TOP, 
                                  	heightFract);
					
                    // cloud illumination
                    float3 luminance = (ambient * SAT(pow(sun.z + .04, 1.4))
						+ skyCol * 0.125 + (sunHeight * skyCol + float3(.0075, .015, .03))
						* SUN_COLOR * hgPhase
						* marchToLight(p, sunDir, sunDot, sunScatterHeight)) * density;

                    // improved scatter integral by Sébastien Hillaire
                    float transmittance = exp(-density * cameraRayStepSize);
                    float3 integScatter = (luminance - luminance * transmittance) * (1. / density);
                    intScatterTrans.rgb += intScatterTrans.a * integScatter; 
                    intScatterTrans.a *= transmittance;

                }

                if (intScatterTrans.a < 0.05)
                    break;
                cameraRayDist += cameraRayStepSize;
            }

            // blend clouds with sky at a distance near the horizon (again super hacky)
            float fogMask = 1. - exp(-smoothstep(.15, 0., ray.direction.y) * 2.);
            float3 fogCol = atmosphericScattering(uv * .5 + .2, sun.xy * .5 + .2, false);
            intScatterTrans.rgb = lerp(intScatterTrans.rgb,
                                      fogCol * sunHeight, fogMask);
            intScatterTrans.a = lerp(intScatterTrans.a, 0., fogMask);

            col = float4(max(float3(intScatterTrans.rgb), 0.0), intScatterTrans.a);
            
            //temporal reprojection
    		col = lerp(prevCol, col, 0.5);
        }
    }
  //   else
  //   {
		// col = prevCol;
  //   }
    
    return col;

}

#endif