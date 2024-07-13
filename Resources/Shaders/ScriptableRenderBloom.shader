////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Copyright (c) Martin Bustos @FronkonGames <fronkongames@gmail.com>. All rights reserved.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
Shader "Hidden/Fronkon Games/Scriptable Render Bloom"
{
  Properties
  {
    _MainTex("Main Texture", 2D) = "white" {}
  }

  SubShader
  {
    Tags
    {
      "RenderType" = "Opaque"
      "RenderPipeline" = "UniversalPipeline"
    }
    LOD 100
    ZTest Always ZWrite Off Cull Off

    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

    TEXTURE2D(_MainTex);
    SAMPLER(sampler_MainTex);

    float4 _MainTex_TexelSize;

    struct VertexInput
    {
      float4 vertex : POSITION;
      float2 uv     : TEXCOORD0;
      UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct VertexOutput
    {
      float4 vertex : SV_POSITION;
      float2 uv     : TEXCOORD0;
      UNITY_VERTEX_OUTPUT_STEREO
    };

    VertexOutput Vert(VertexInput input)
    {
      VertexOutput output;
      UNITY_SETUP_INSTANCE_ID(input);
      UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

      output.vertex = TransformObjectToHClip(input.vertex.xyz);
      output.uv = UnityStereoTransformScreenSpaceTex(input.uv);

      return output;
    }

    half3 KawaseBlur(Texture2D tex, SamplerState sampler_name, float2 uv, float2 texelSize, half pexelOffset)
    {
      half3 o = 0;
      o += SAMPLE_TEXTURE2D(tex, sampler_name, uv + float2(pexelOffset +0.5, pexelOffset +0.5) * texelSize).rgb;
      o += SAMPLE_TEXTURE2D(tex, sampler_name, uv + float2(-pexelOffset -0.5, pexelOffset +0.5) * texelSize).rgb;
      o += SAMPLE_TEXTURE2D(tex, sampler_name, uv + float2(-pexelOffset -0.5, -pexelOffset -0.5) * texelSize).rgb;
      o += SAMPLE_TEXTURE2D(tex, sampler_name, uv + float2(pexelOffset +0.5, -pexelOffset -0.5) * texelSize).rgb;

      return o * 0.25;
    }
    ENDHLSL

    Pass
    {
      Name "Fronkon Games Bloom Pass 0"

      HLSLPROGRAM
		  #pragma vertex Vert
		  #pragma fragment Frag

      float _Threshold;

      half4 Frag(const VertexOutput i) : SV_Target
      {
        float4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
        float lum = dot(float3(0.2126, 0.7152, 0.0722), col.rgb);

        UNITY_BRANCH
        if (lum > _Threshold)
          return col;

        return float4(0,0,0,1);
      }     
      ENDHLSL
    }

    Pass
    {
      Name "Fronkon Games Bloom Pass 1"

      HLSLPROGRAM
		  #pragma vertex Vert
		  #pragma fragment Frag

      float _BloomDownOffset;

      half4 Frag(const VertexOutput i) : SV_Target
      {
        float4 color = float4(0,0,0,1);
        float2 uv = i.uv;
        float2 stride = _MainTex_TexelSize.xy;

        color.rgb = KawaseBlur(_MainTex, sampler_MainTex, uv, _MainTex_TexelSize, _BloomDownOffset);

        return color;
      }
      ENDHLSL
    }

    Pass
    {
      Name "Fronkon Games Bloom Pass 2"

      HLSLPROGRAM
		  #pragma vertex Vert
		  #pragma fragment Frag

      TEXTURE2D(_PreTex);
      SAMPLER(sampler_PreTex);

      half _BloomUpOffset;

      half4 Frag(const VertexOutput i) : SV_Target
      {
        float4 color = float4(0, 0, 0, 1);
        float2 uv = i.uv;

        float2 prev_stride = 0.5 * _MainTex_TexelSize.xy;
        float2 curr_stride = 1.0 * _MainTex_TexelSize.xy;

        float3 pre_tex = KawaseBlur(_MainTex, sampler_MainTex, uv, prev_stride, _BloomUpOffset);
        float3 curr_tex = KawaseBlur(_PreTex, sampler_PreTex, uv, curr_stride, _BloomUpOffset);

        color.rgb =  curr_tex + pre_tex;

        return color;
      }
      ENDHLSL
    }

    Pass
    {
      Name "Fronkon Games Bloom Pass 3"

      HLSLPROGRAM
		  #pragma vertex Vert
		  #pragma fragment Frag

      TEXTURE2D(_BloomTex);
      SAMPLER(sampler_BloomTex);
      
      float _Intensity;
      
      float3 ACESToneMapping(float3 color, float adapted_lum)
      {
        const float A = 2.51;
        const float B = 0.03;
        const float C = 2.43;
        const float D = 0.59;
        const float E = 0.14;

        color *= adapted_lum;

        return (color * (A * color + B)) / (color * (C * color + D) + E);
      }

      half4 Frag(const VertexOutput i) : SV_Target
      {
        half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
        float3 bloom = SAMPLE_TEXTURE2D(_BloomTex, sampler_BloomTex, i.uv).rgb * _Intensity;

        bloom = ACESToneMapping(bloom, 1);

        float g = 1.0 / 2.2;
        bloom = saturate(pow(abs(bloom), float3(g, g, g)));

        color.rgb += bloom;

        return color;
      }
      ENDHLSL
    }
  }
  
  FallBack "Diffuse"
}
