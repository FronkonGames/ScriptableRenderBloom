////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Copyright (c) Martin Bustos @FronkonGames <fronkongames@gmail.com>. All rights reserved.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace FronkonGames.ScriptableRenderBloom
{
  /// <summary> Bloom compatible with custom post-processes. </summary>
  public sealed class ScriptableRenderBloom : ScriptableRendererFeature
  {
    public Settings settings = new();

    private RenderPass renderPass;

    public override void Create() => renderPass = new RenderPass(settings);

    /// <summary> Bloom custom render pass. </summary>
    private sealed class RenderPass : ScriptableRenderPass
    {
      private readonly Settings settings;

      private RenderTargetIdentifier colorBuffer;
      private RenderTextureDescriptor renderTextureDescriptor;

      private readonly Material material;

      private static class ShaderIDs
      {
        internal static readonly int Intensity        = Shader.PropertyToID("_Intensity");
        internal static readonly int Passes           = Shader.PropertyToID("_Passes");
        internal static readonly int Threshold        = Shader.PropertyToID("_Threshold");
        internal static readonly int BloomDownOffset  = Shader.PropertyToID("_BloomDownOffset");
        internal static readonly int BloomUpOffset    = Shader.PropertyToID("_BloomUpOffset");
      }

      private static class Textures
      {
        internal const string PreviousTexture = "_PreTex";
        internal const string BloomTexture    = "_BloomTex";
      }

      /// <summary> Render pass constructor. </summary>
      public RenderPass(Settings settings)
      {
        this.settings = settings;

        string shaderPath = $"Shaders/ScriptableRenderBloom";
        Shader shader = Resources.Load<Shader>(shaderPath);
        if (shader != null)
        {
          if (shader.isSupported == true)
            material = CoreUtils.CreateEngineMaterial(shader);
          else
            Debug.LogWarning($"'{shaderPath}.shader' not supported.");
        }
      }

      /// <inheritdoc/>
      public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
      {
        renderTextureDescriptor = renderingData.cameraData.cameraTargetDescriptor;
        renderTextureDescriptor.msaaSamples = 1;
        renderTextureDescriptor.depthBufferBits = 0;

#if UNITY_2022_1_OR_NEWER
        colorBuffer = renderingData.cameraData.renderer.cameraColorTargetHandle;
#else
        colorBuffer = renderingData.cameraData.renderer.cameraColorTarget;
#endif
      }

      /// <inheritdoc/>
      public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
      {
        if (material == null ||
            renderingData.postProcessingEnabled == false ||
            renderingData.cameraData.isSceneViewCamera == true ||
            settings.intensity <= 0.0f)
          return;

        CommandBuffer cmd = CommandBufferPool.Get("ScriptableRenderBloom");

        RenderTexture renderTextureThreshold = RenderTexture.GetTemporary(Screen.width, Screen.height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        renderTextureThreshold.filterMode = FilterMode.Bilinear;

        RenderTexture renderTextureDest = RenderTexture.GetTemporary(Screen.width, Screen.height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);

        material.shaderKeywords = null;

        material.SetFloat(ShaderIDs.Intensity, settings.intensity);
        material.SetFloat(ShaderIDs.Threshold, settings.threshold);
        material.SetFloat(ShaderIDs.BloomUpOffset, settings.bloomUpOffset);

        Blit(cmd, colorBuffer, renderTextureDest);

        Blit(cmd, colorBuffer, renderTextureThreshold, material, 0);

        RenderTexture[] renderTexturesBloomDown = new RenderTexture[settings.passes];

        int downSize = 2;
        for (int i = 0; i < settings.passes; ++i)
        {
          int width = Screen.width / downSize;
          int height = Screen.height / downSize;

          renderTexturesBloomDown[i] = RenderTexture.GetTemporary(width, height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
          renderTexturesBloomDown[i].filterMode = FilterMode.Bilinear;

          downSize *= 2;
        }

        Blit(cmd, renderTextureThreshold, renderTexturesBloomDown[0]);

        for (int i = 1; i < renderTexturesBloomDown.Length; ++i)
        {
          material.SetFloat(ShaderIDs.BloomDownOffset, i / 2 + settings.bloomDownOffset);

          Blit(cmd, renderTexturesBloomDown[i - 1], renderTexturesBloomDown[i], material, 1);
        }

        RenderTexture[] renderTextureBloomUp = new RenderTexture[settings.passes];
        for (int i = 0; i < settings.passes - 1; ++i)
        {
          int w = renderTexturesBloomDown[settings.passes - 2 - i].width;
          int h = renderTexturesBloomDown[settings.passes - 2 - i].height;
          
          renderTextureBloomUp[i] = RenderTexture.GetTemporary(w, h, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
          renderTextureBloomUp[i].filterMode = FilterMode.Bilinear;
        }

        cmd.SetGlobalTexture(Textures.PreviousTexture, renderTexturesBloomDown[settings.passes - 1]);

        Blit(cmd, renderTexturesBloomDown[settings.passes - 2], renderTextureBloomUp[0], material, 2);

        for (int i = 1; i < settings.passes - 1; ++i)
        {
          RenderTexture previousTexture = renderTextureBloomUp[i - 1];
          RenderTexture currentTexture = renderTexturesBloomDown[settings.passes - 2 - i];

          material.SetFloat(ShaderIDs.BloomUpOffset, i / 2 + settings.bloomUpOffset);

          cmd.SetGlobalTexture(Textures.PreviousTexture, previousTexture);
          Blit(cmd, currentTexture, renderTextureBloomUp[i], material, 2);
        }

        cmd.SetGlobalTexture(Textures.BloomTexture, renderTextureBloomUp[settings.passes - 2]);

        Blit(cmd, renderTextureDest, colorBuffer, material, 3);

        RenderTexture.ReleaseTemporary(renderTextureThreshold);
        RenderTexture.ReleaseTemporary(renderTextureDest);
        for (int i = 0; i < renderTexturesBloomDown.Length; ++i)
        {
          RenderTexture.ReleaseTemporary(renderTexturesBloomDown[i]);
          RenderTexture.ReleaseTemporary(renderTextureBloomUp[i]);
        }

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
      }
    }

#if UNITY_2022_1_OR_NEWER
    // TODO.
    // cmd.Blit(colorBuffer, renderTextureHandle0, material, 0);
    // cmd.Blit(renderTextureHandle0, colorBuffer, material, 1);
#else
    private void Blit(CommandBuffer cmd, RenderTargetIdentifier source, int target, Material material = null, int pass = 0) =>
      Blit(cmd, source, target, material, pass);

    private void Blit(CommandBuffer cmd, int source, int target, Material material = null, int pass = 0) =>
      Blit(cmd, source, target, material, pass);
#endif

    /// <summary> Injects one or multiple ScriptableRenderPass in the renderer. Called every frame once per camera. </summary>
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
      renderPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing - 3;

      renderer.EnqueuePass(renderPass);
    }
  }

  [Serializable]
  public class Settings
  {
    [SerializeField, Range(0.0f, 5.0f)]
    public float intensity = 1.0f;

    [SerializeField, Range(2, 7)]
    public int passes = 3;

    [SerializeField, Range(0.0f, 2.0f)]
    public float threshold = 1.0f;
    
    [SerializeField, Range(0.1f, 2.0f)]
    public float bloomDownOffset = 1.0f;
    
    [SerializeField, Range(0.1f, 2.0f)]
    public float bloomUpOffset = 1.0f;
  }
}
