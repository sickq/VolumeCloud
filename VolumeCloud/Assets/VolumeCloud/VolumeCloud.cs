using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
// ReSharper disable All

public class VolumeCloud : MonoBehaviour
{
    public Shader shader;
    private Material mat;
    private Material Mat
    {
        get
        {
            if (mat == null)
            {
                mat = new Material(shader);
            }
            return mat;
        }
    }

    private RenderTexture tempTexture;
    RenderTexture TempTexture
    {
        get
        {
            if (tempTexture == null)
            {
                tempTexture = new RenderTexture(4, 4, 0, RenderTextureFormat.ARGB32)
                {
                    name = "Temp Texture",
                };
            }
            return tempTexture;
        }
    }
    
    public RenderTexture perlinWorleyNoiseTexture;
    RenderTexture PerlinWorleyNoiseTexture
    {
        get
        {
            if (perlinWorleyNoiseTexture == null)
            {
                perlinWorleyNoiseTexture = new RenderTexture(1024, 1024, 0, RenderTextureFormat.ARGB32)
                {
                    name = "Perlin-Worley Noise Texture",
                    filterMode = FilterMode.Point,
                };
            }
            return perlinWorleyNoiseTexture;
        }
        set
        {
            perlinWorleyNoiseTexture = value;
        }
    }
    
    public RenderTexture volumeCloudRT1;
    RenderTexture VolumeCloudRT1
    {
        get
        {
            if (volumeCloudRT1 == null)
            {
                volumeCloudRT1 = new RenderTexture(Screen.width, Screen.height, 0, GetRTFormat())
                {
                    name = "VolumeCloudRT1",
                };
            }
            return volumeCloudRT1;
        }
        set
        {
            volumeCloudRT1 = value;
        }
    }
    
    public RenderTexture volumeCloudRT2;
    RenderTexture VolumeCloudRT2
    {
        get
        {
            if (volumeCloudRT2 == null)
            {
                volumeCloudRT2 = new RenderTexture(Screen.width, Screen.height, 0, GetRTFormat())
                {
                    name = "VolumeCloudRT2",
                };
            }
            return volumeCloudRT2;
        }
        set
        {
            volumeCloudRT2 = value;
        }
    }

    private int lastScreenWidth;
    private int lastScreenHeight;

    private Camera _camera;
    private Camera Camera {
        get {
            if (_camera == null) {
                _camera = GetComponent<Camera>();
            }
            return _camera;
        }
    }
	
    private Camera MyCamera {
        get
        {
            if (Camera.current != null)
            {
                return Camera.current;
            }
			
            return Camera;
        }
    }

    private Transform CameraTransform {
        get { return MyCamera.transform; }
    }

    private CommandBuffer volumeCloudCB;
    private CommandBuffer VolumeCloudCB
    {
        get
        {
            if (volumeCloudCB == null)
            {
                volumeCloudCB = new CommandBuffer()
                {
                    name = "VolumeCB"
                };
            }
            return volumeCloudCB;
        }
    }

    private int currentFrame;

    private void OnPreRender()
    {
        currentFrame++;
        //Prepare Perlin-Worley Noise
        if (Screen.width != lastScreenWidth || Screen.height != lastScreenHeight)
        {
            lastScreenWidth = Screen.width;
            lastScreenHeight = Screen.height;
            
            Graphics.Blit(TempTexture, PerlinWorleyNoiseTexture, Mat, 1);
            Shader.SetGlobalTexture(CustomShaderID._PerlinWorleyNoise, PerlinWorleyNoiseTexture);
        }

        var events = MyCamera.GetCommandBuffers(CameraEvent.BeforeImageEffects);
        if (events.Length <= 0)
        {
            MyCamera.AddCommandBuffer(CameraEvent.BeforeImageEffects, VolumeCloudCB);
        }

        VolumeCloudCB.Clear();
        var frustumCorners = Utils.GetFrustumCorners(MyCamera, CameraTransform);
        VolumeCloudCB.SetGlobalMatrix(CustomShaderID._FrustumCornorsRay, frustumCorners);
        VolumeCloudCB.SetGlobalInt(CustomShaderID._iFrame, currentFrame);

        var lastVCRT = VolumeCloudRT1;
        var currentVCRT = VolumeCloudRT2;

        Shader.SetGlobalTexture(CustomShaderID._LastFrameRT, lastVCRT);
        Shader.SetGlobalTexture(CustomShaderID._VolumeCloudTexture, currentVCRT);
        VolumeCloudCB.Blit(BuiltinRenderTextureType.CameraTarget, currentVCRT, Mat, 0);
        VolumeCloudCB.Blit(currentVCRT, BuiltinRenderTextureType.CameraTarget, Mat, 2);
        VolumeCloudCB.Blit(currentVCRT, lastVCRT);
    }

    private void ReleaseAllRT()
    {
        PerlinWorleyNoiseTexture.Release();
        PerlinWorleyNoiseTexture = null;
        
        VolumeCloudRT1.Release();
        VolumeCloudRT1 = null;
        
        VolumeCloudRT2.Release();
        VolumeCloudRT2 = null;
    }
    public RenderTextureFormat GetRTFormat()
    {
        if (MyCamera.allowHDR)
        {
            return RenderTextureFormat.DefaultHDR;
        }
        else
        {
            return RenderTextureFormat.ARGB32;
        }
    }

    [ContextMenu("SaveNoise")]
    public void SaveNoise()
    {
        Texture2D lut = new Texture2D(PerlinWorleyNoiseTexture.width, PerlinWorleyNoiseTexture.height, TextureFormat.RGB24, false, true);
        RenderTexture.active = PerlinWorleyNoiseTexture;
        lut.ReadPixels(new Rect(0f, 0f, lut.width, lut.height), 0, 0);
        RenderTexture.active = null;
        
        var pixels = lut.GetPixels();

        for (int i = 0; i < pixels.Length; i++)
            pixels[i] = pixels[i];

        lut.SetPixels(pixels);
        lut.Apply();

        string path = UnityEditor.EditorUtility.SaveFilePanelInProject("Export LUT as PNG", "LUT.png", "png", "Please enter a file name to save the LUT texture to");

        
        byte[] bytes = lut.EncodeToPNG();
        System.IO.File.WriteAllBytes(path, bytes);
        DestroyImmediate(lut);

        UnityEditor.AssetDatabase.Refresh();
    }
}

public static class Utils
{
    public static Matrix4x4 GetFrustumCorners(Camera myCamera, Transform cameraTransform)
    {
        Matrix4x4 frustumCorners = Matrix4x4.identity;

        //field of view
        float fov = myCamera.fieldOfView;
        //近裁面距离
        float near = myCamera.nearClipPlane;
        //横纵比
        float aspect = myCamera.aspect;
        //近裁面一半的高度
        float halfHeight = near * Mathf.Tan(fov * 0.5f * Mathf.Deg2Rad);
        //向上和向右的向量
        Vector3 toRight = myCamera.transform.right * halfHeight * aspect;
        Vector3 toTop = myCamera.transform.up * halfHeight;

        //分别得到相机到近裁面四个角的向量
        //depth/dist=near/|topLeft|
        //dist=depth*(|TL|/near)
        //scale=|TL|/near
        Vector3 topLeft = cameraTransform.forward * near + toTop - toRight;
        float scale = topLeft.magnitude / near;

        topLeft.Normalize();
        topLeft *= scale;

        Vector3 topRight = cameraTransform.forward * near + toTop + toRight;
        topRight.Normalize();
        topRight *= scale;

        Vector3 bottomLeft = cameraTransform.forward * near - toTop - toRight;
        bottomLeft.Normalize();
        bottomLeft *= scale;

        Vector3 bottomRight = cameraTransform.forward * near - toTop + toRight;
        bottomRight.Normalize();
        bottomRight *= scale;

        //给矩阵赋值
        frustumCorners.SetRow(0, bottomLeft);
        frustumCorners.SetRow(1, bottomRight);
        frustumCorners.SetRow(2, topRight);
        frustumCorners.SetRow(3, topLeft);
        
        return frustumCorners;
    }
}

public static class CustomShaderID
{
    public static readonly int _PerlinWorleyNoise = Shader.PropertyToID("_PerlinWorleyNoise");
    public static readonly int _FrustumCornorsRay = Shader.PropertyToID("_FrustumCornorsRay");
    public static readonly int _iFrame = Shader.PropertyToID("_iFrame");
    public static readonly int _LastFrameRT = Shader.PropertyToID("_LastFrameRT");
    public static readonly int _VolumeCloudTexture = Shader.PropertyToID("_VolumeCloudTexture");

}
