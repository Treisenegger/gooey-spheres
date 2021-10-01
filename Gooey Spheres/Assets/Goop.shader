Shader "Unlit/Goop"
{
    Properties
    {
        // _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1, 0.5, 0.5, 1)
        _Gloss ("Gloss", Range(0, 1)) = 0.5
    }
    SubShader
    {
        Tags { 
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        Pass
        {
            ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha

            CGPROGRAM
            // Upgrade NOTE: excluded shader from OpenGL ES 2.0 because it uses non-square matrices
            #pragma exclude_renderers gles
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            #define MAX_MARCH_STEPS 100
            #define MIN_MARCH_DIST 0.0001
            #define MAX_MARCH_DIST 2
            #define TAU 6.28318530718

            struct MeshData
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct Interpolators
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : TEXCOORD1;
                float3 wPos : TEXCOORD2;
                float3 lPos : TEXCOORD3;
            };

            // sampler2D _MainTex;
            // float4 _MainTex_ST;
            float4 _Color;
            float _Gloss;

            Interpolators vert (MeshData v)
            {
                Interpolators o;
                o.vertex = UnityObjectToClipPos( v.vertex );
                o.uv = v.uv;
                o.normal = v.normal;
                o.wPos = mul( UNITY_MATRIX_M, v.vertex );
                o.lPos = v.vertex.xyz;
                return o;
            }

            // Blend between spheres
            float BlendShapes( float d1, float d2 ) {
                float k = 0.5;
                float h = saturate( 0.5 + 0.5 * ( d1 - d2 ) / k );
                return lerp( d1, d2, h ) - k * h * ( 1 - h );
            }

            // Create SDF
            float SDF( float3 pos) {
                float3 h = float3( 0, 0, 0 );
                float3 sphere1 = float3( 0, sin( _Time.y * TAU / 3 ), 0) * 0.3 + h;
                float radius1 = 0.1;
                float3 sphere2 = float3( sin( _Time.y * TAU / 3 ), 0, cos( _Time.y * TAU / 3 ) ) * 0.3 + h;
                float radius2 = 0.1;
                float3 sphere3 = float3( 0, cos( _Time.y * TAU / 3 ), sin( _Time.y * TAU / 3 ) ) * 0.3 + h;
                float radius3 = 0.1;

                float distance1 = distance( pos, sphere1 ) - radius1;
                float distance2 = distance( pos, sphere2 ) - radius2;
                float distance3 = distance( pos, sphere3 ) - radius3;

                return BlendShapes( distance1, BlendShapes( distance2, distance3 ) );
            }

            // Calculate normal aproximation through sdf gradient
            float3 SDFNormal( float3 pos, float aproxDist ) {
                float2 h = float2( aproxDist, 0 );
                return normalize( float3( 
                    SDF( pos + h.xyy ) - SDF( pos - h.xyy ),
                    SDF( pos + h.yxy ) - SDF( pos - h.yxy ),
                    SDF( pos + h.yyx ) - SDF( pos - h.yyx )
                ) );
            }

            // Perform ray marching
            float3 RayMarching( float3 startPos, float3 step, float maxSteps, float minDist, float maxDist ) {
                float3 currentPos = startPos;
                float sdf;

                for ( int index = 0; index < maxSteps; index++ ) {
                    sdf = SDF( currentPos );

                    if ( sdf < minDist )
                        return SDFNormal( currentPos, MIN_MARCH_DIST );
                    
                    if ( sdf > maxDist )
                        return float3( 0, 0, 0 );

                    currentPos += step * sdf;
                }

                return float3( 0, 0, 0 );
            }

            // Lambertian diffused lighting
            float LambDif( float3 N, float3 L ) {
                return dot( N, L );
            }

            // Blinn-Phong specular lighting
            float BPhong( float3 N, float3 L, float3 V, float lamb ) {
                float3 H = normalize( V + L );
                float specLight = saturate( dot( N, H ) * ( lamb > 0 ) );
                float specExp = exp2( _Gloss * 11 ) + 1;
                return pow( specLight, specExp );
            }

            float4 frag (Interpolators i) : SV_Target
            {
                float3 startPos = i.lPos;
                float3 V = normalize( _WorldSpaceCameraPos - i.wPos );
                float3 step = - normalize( UnityWorldToObjectDir( V ) );

                float3 normal = RayMarching( startPos, step, MAX_MARCH_STEPS, MIN_MARCH_DIST, MAX_MARCH_DIST );

                if ( length( normal ) == 0 )
                    return 0;

                float3 N = UnityObjectToWorldNormal( normal );
                float3 L = _WorldSpaceLightPos0.xyz;

                float lambDif = LambDif( N, L );
                float bPhong = BPhong( N, L, V, lambDif );

                float3 difLight = lambDif * _LightColor0.xyz;
                float3 specLight = bPhong * _LightColor0.xyz;

                return float4( difLight * _Color + specLight, 1 );
            }
            ENDCG
        }
    }
}
