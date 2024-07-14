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
      half3 output = 0;
      output += SAMPLE_TEXTURE2D(tex, sampler_name, uv + float2(pexelOffset  + 0.5,  pexelOffset + 0.5) * texelSize).rgb;
      output += SAMPLE_TEXTURE2D(tex, sampler_name, uv + float2(-pexelOffset - 0.5,  pexelOffset + 0.5) * texelSize).rgb;
      output += SAMPLE_TEXTURE2D(tex, sampler_name, uv + float2(-pexelOffset - 0.5, -pexelOffset - 0.5) * texelSize).rgb;
      output += SAMPLE_TEXTURE2D(tex, sampler_name, uv + float2(pexelOffset  + 0.5, -pexelOffset - 0.5) * texelSize).rgb;

      return output * 0.25;
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
        half3 pixel = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb;
        float luminance = dot(float3(0.2126, 0.7152, 0.0722), pixel);

        UNITY_BRANCH
        if (luminance <= _Threshold)
          pixel = 0.0;

        return half4(pixel, 1.0);
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
        half3 pixel = 0.0;
        float2 uv = i.uv;
        float2 stride = _MainTex_TexelSize.xy;

        pixel = KawaseBlur(_MainTex, sampler_MainTex, uv, _MainTex_TexelSize.xy, _BloomDownOffset);

        return half4(pixel, 1.0);
      }
      ENDHLSL
    }

    Pass
    {
      Name "Fronkon Games Bloom Pass 2"

      HLSLPROGRAM
		  #pragma vertex Vert
		  #pragma fragment Frag

      TEXTURE2D(_PreFilterTex);
      SAMPLER(sampler_PreFilterTex);

      half _BloomUpOffset;

      half4 Frag(const VertexOutput i) : SV_Target
      {
        float3 pixel = 0.0;
        float2 uv = i.uv;

        float2 prevFilterStride = 0.5 * _MainTex_TexelSize.xy;
        float2 currentStride = 1.0 * _MainTex_TexelSize.xy;

        float3 preFilterTexure = KawaseBlur(_MainTex, sampler_MainTex, uv, prevFilterStride, _BloomUpOffset);
        float3 currentTex = KawaseBlur(_PreFilterTex, sampler_PreFilterTex, uv, currentStride, _BloomUpOffset);

        pixel = currentTex + preFilterTexure;

        return half4(pixel, 1.0);
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
      
      half3 ACESToneMapping(half3 pixel, float adaptedLuminance)
      {
        const float A = 2.51;
        const float B = 0.03;
        const float C = 2.43;
        const float D = 0.59;
        const float E = 0.14;

        pixel *= adaptedLuminance;

        return (pixel * (A * pixel + B)) / (pixel * (C * pixel + D) + E);
      }

      half4 Frag(const VertexOutput i) : SV_Target
      {
        half3 pixel = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb;
        half3 bloom = SAMPLE_TEXTURE2D(_BloomTex, sampler_BloomTex, i.uv).rgb * _Intensity;

        bloom = ACESToneMapping(bloom, 1.0);

        const float g = 1.0 / 2.2;
        bloom = saturate(pow(abs(bloom), float3(g, g, g)));

        pixel += bloom;

        return half4(pixel, 1.0);
      }
      ENDHLSL
    }
  }
  
  FallBack "Diffuse"
}
