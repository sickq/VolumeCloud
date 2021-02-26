Shader "Hidden/VolumeCloudMain"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    
    HLSLINCLUDE

    
    ENDHLSL
    
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always
        
        //Pass 0 Final Pass
        Pass
        {
            HLSLPROGRAM
            
            #pragma vertex vertDefault
            #pragma fragment fragFinal

            #include "VolumeCloud.hlsl"
            
            ENDHLSL
        }
        
        //Pass 1 Generate Perlin-Worley Noise
        Pass
        {
            HLSLPROGRAM
            #include "VolumeCloud.hlsl"
            
            #pragma vertex vert_img
            #pragma fragment frag_base_noise_gen

            half4 frag_base_noise_gen(v2f_img i) : SV_Target
            {
                float2 uv = i.uv.xy;
                float4 col = 0;
                col.r += perlinFbm(float3(uv, 0.4), 4.0, 15) * 0.5;
                col.r = abs(col.r * 2.0 - 1.0);
                //col.r = remap(col.r,  worleyFbm(float3(uv, 0.2), 4.0, true) - 1.0, 1.0, 0.0, 1.0);
                col.g += worleyFbm(float3(uv, .5), 8., true) * 0.625 + 
            	         worleyFbm(float3(uv, .5), 16., true) * 0.25  +
            	         worleyFbm(float3(uv, .5), 32., true) * 0.125;
                col.b = 1.0 - col.g;
                col.a = 1;
                return col;
            }
            
            ENDHLSL
        }
        
        //Pass 2 Combine Pass
        Pass
        {
            HLSLPROGRAM
            
            #pragma vertex vertDefault
            #pragma fragment fragCombine

            #include "VolumeCloud.hlsl"
            
            sampler2D _VolumeCloudTexture;
            
            half4 fragCombine(v2f input) : SV_Target
            {
                float2 uv = input.texcoord.xy;
                half4 col = tex2D(_VolumeCloudTexture, uv);
                return col;
            }
            
            ENDHLSL
        }
    }
}
