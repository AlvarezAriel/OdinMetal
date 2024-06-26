#include <metal_stdlib>
#import "basics.metal"
using namespace metal;

struct Uniforms {
    float4 cursor;
    float4 flags;
};

struct Camera_Data {
    float4x4 look;
};

struct Voxel_Data {
	uint16_t points[16][16];
};

// camera FOV
constant float c_FOVDegrees = 60.0f;
constant float c_exposure = 0.5;

void TestSceneTrace(float3 rayPos, float3 rayDir, thread SRayHitInfo *hitInfo)
{    
    // to move the scene around, since we can't move the camera yet
    float3 sceneTranslation = float3(0.0f, 0.0f, 10.0f);
    float4 sceneTranslation4 = float4(sceneTranslation, 0.0f);
    
    SMaterialInfo basematerial;
    basematerial.emissive = float3(0.0f, 0.0f, 0.0f);
    basematerial.albedo = float3(0.7f, 0.7f, 0.7f);
    basematerial.percentSpecular = 0.0; // 0..1
    basematerial.roughness = 1.0; // 0..1
    basematerial.specularColor = float3(1.0); 
    
   	// back wall
    {
        float3 A = float3(-12.6f, -12.6f, 25.0f) + sceneTranslation;
        float3 B = float3( 12.6f, -12.6f, 25.0f) + sceneTranslation;
        float3 C = float3( 12.6f,  12.6f, 25.0f) + sceneTranslation;
        float3 D = float3(-12.6f,  12.6f, 25.0f) + sceneTranslation;
        if (TestQuadTrace(rayPos, rayDir, hitInfo, A, B, C, D))
        {
            hitInfo->material = basematerial;
        }
	}    
    
    // floor
    {
        float3 A = float3(-12.6f, -12.45f, 25.0f) + sceneTranslation;
        float3 B = float3( 12.6f, -12.45f, 25.0f) + sceneTranslation;
        float3 C = float3( 12.6f, -12.45f, 15.0f) + sceneTranslation;
        float3 D = float3(-12.6f, -12.45f, 15.0f) + sceneTranslation;
        if (TestQuadTrace(rayPos, rayDir, hitInfo, A, B, C, D))
        {
            hitInfo->material = basematerial;
        }        
    }
    
    // cieling
    {
        float3 A = float3(-12.6f, 12.5f, 25.0f) + sceneTranslation;
        float3 B = float3( 12.6f, 12.5f, 25.0f) + sceneTranslation;
        float3 C = float3( 12.6f, 12.5f, 15.0f) + sceneTranslation;
        float3 D = float3(-12.6f, 12.5f, 15.0f) + sceneTranslation;
        if (TestQuadTrace(rayPos, rayDir, hitInfo, A, B, C, D))
        {
            hitInfo->material = basematerial;
        }        
    }    
    
    // left wall
    {
        float3 A = float3(-12.5f, -12.6f, 25.0f) + sceneTranslation;
        float3 B = float3(-12.5f, -12.6f, 15.0f) + sceneTranslation;
        float3 C = float3(-12.5f,  12.6f, 15.0f) + sceneTranslation;
        float3 D = float3(-12.5f,  12.6f, 25.0f) + sceneTranslation;
        if (TestQuadTrace(rayPos, rayDir, hitInfo, A, B, C, D))
        {
            hitInfo->material = basematerial;
            hitInfo->material.albedo = float3(0.7f, 0.1f, 0.1f);
        }        
    }
    
    // right wall 
    {
        float3 A = float3( 12.5f, -12.6f, 25.0f) + sceneTranslation;
        float3 B = float3( 12.5f, -12.6f, 15.0f) + sceneTranslation;
        float3 C = float3( 12.5f,  12.6f, 15.0f) + sceneTranslation;
        float3 D = float3( 12.5f,  12.6f, 25.0f) + sceneTranslation;
        if (TestQuadTrace(rayPos, rayDir, hitInfo, A, B, C, D))
        {
            hitInfo->material = basematerial;
            hitInfo->material.albedo = float3(0.1f, 0.7f, 0.1f);
        }        
    }    
    
    // light
    {
        float3 A = float3(-5.0f, 12.4f,  22.5f) + sceneTranslation;
        float3 B = float3( 5.0f, 12.4f,  22.5f) + sceneTranslation;
        float3 C = float3( 5.0f, 12.4f,  17.5f) + sceneTranslation;
        float3 D = float3(-5.0f, 12.4f,  17.5f) + sceneTranslation;
        if (TestQuadTrace(rayPos, rayDir, hitInfo, A, B, C, D))
        {
            hitInfo->material = basematerial;
            hitInfo->material.albedo = float3(0.0f, 0.0f, 0.0f);
            hitInfo->material.emissive = float3(1.0f, 0.9f, 0.7f) * 20.0f;
        }        
    }
    
	if (TestSphereTrace(rayPos, rayDir, hitInfo, float4(-9.0f, -9.5f, 20.0f, 3.0f)+sceneTranslation4))
    {
        hitInfo->material = basematerial;
        hitInfo->material.albedo = float3(0.9f, 0.9f, 0.5f);
        hitInfo->material.roughness = 0.8; // 0..1
        hitInfo->material.percentSpecular = 0.2;
        hitInfo->material.specularColor = float3(0.9f, 0.9f, 0.5f);  
    } 
    
	if (TestSphereTrace(rayPos, rayDir, hitInfo, float4(0.0f, -9.5f, 20.0f, 3.0f)+sceneTranslation4))
    {
        hitInfo->material = basematerial;
        hitInfo->material.albedo = float3(0.9f, 0.5f, 0.9f);
        hitInfo->material.roughness = 0.5; // 0..1
        hitInfo->material.percentSpecular = 0.5;
        hitInfo->material.specularColor = float3(0.9f, 0.9f, 0.5f);  
    }    
    
	if (TestSphereTrace(rayPos, rayDir, hitInfo, float4(9.0f, -9.5f, 20.0f, 3.0f)+sceneTranslation4))
    {
        hitInfo->material = basematerial;
        hitInfo->material.albedo = float3(0.50f, 0.9f, 0.9f);
        hitInfo->material.roughness = 0.01; // 0..1
        hitInfo->material.percentSpecular = 0.8;
        hitInfo->material.specularColor = float3(0.2, 0.2, 0.9);
    }     

    if (TestSphereTrace(rayPos, rayDir, hitInfo, float4(4.5f, -11.0f, 23.0f, 1.0f)+sceneTranslation4))
    {
        hitInfo->material = basematerial;
        hitInfo->material.albedo = float3(0.50f, 0.9f, 0.9f);
        hitInfo->material.roughness = 0.01; // 0..1
        hitInfo->material.percentSpecular = 0.8;
        hitInfo->material.specularColor = float3(0.2, 0.2, 0.9);
        hitInfo->material.emissive = float3(0.2, 0.2, 0.9) * 4.0;

    }     
    if (TestSphereTrace(rayPos, rayDir, hitInfo, float4(-4.5f, -11.0f, 17.0f, 1.0f)+sceneTranslation4))
    {
        hitInfo->material = basematerial;
        hitInfo->material.albedo = float3(0.50f, 0.9f, 0.9f);
        hitInfo->material.roughness = 0.01; // 0..1
        hitInfo->material.percentSpecular = 0.8;
        hitInfo->material.specularColor = float3(0.2, 0.2, 0.9);
        hitInfo->material.emissive = float3(0.9, 0.9, 0.2) * 3.0;

    }    
}
 
float3 GetColorForRay(float3 startRayPos, float3 startRayDir, thread RgnState *rngState)
{
    // initialize
    float3 ret = float3(0.0f, 0.0f, 0.0f);
    float3 throughput = float3(1.0f, 1.0f, 1.0f);
    float3 rayPos = startRayPos;
    float3 rayDir = startRayDir;
    
    for (int bounceIndex = 0; bounceIndex <= c_numBounces; ++bounceIndex)
    {
        // shoot a ray out into the world
        SRayHitInfo hitInfo;
        hitInfo.dist = c_superFar;
        TestSceneTrace(rayPos, rayDir, &hitInfo);
        
        // if the ray missed, we are done
        if (hitInfo.dist == c_superFar)
        {
            ret += float3(0.3,0.2,0.1) * throughput;
            break;
        }
        
		// update the ray position
        rayPos = (rayPos + rayDir * hitInfo.dist) + hitInfo.normal * c_rayPosNormalNudge;
        
        // calculate whether we are going to do a diffuse or specular reflection ray
        float doSpecular = (RandomFloat01(rngState) < hitInfo.material.percentSpecular) ? 1.0f : 0.0f;
        
        // Calculate a new ray direction.
        // Diffuse uses a normal oriented cosine weighted hemisphere sample.
        // Perfectly smooth specular uses the reflection ray.
        // Rough (glossy) specular lerps from the smooth specular to the rough diffuse by the material roughness squared
        // Squaring the roughness is just a convention to make roughness feel more linear perceptually.
        float3 diffuseRayDir = normalize(hitInfo.normal + RandomUnitVector(rngState));
        float3 specularRayDir = reflect(rayDir, hitInfo.normal);
        specularRayDir = normalize(mix(specularRayDir, diffuseRayDir, hitInfo.material.roughness * hitInfo.material.roughness));
        rayDir = mix(diffuseRayDir, specularRayDir, doSpecular);
        
        // add in emissive lighting
        ret += hitInfo.material.emissive * throughput;
        
        // update the colorMultiplier
        throughput *= mix(hitInfo.material.albedo, hitInfo.material.specularColor, doSpecular);   
    }
 
    // return pixel color
    return ret;
}

 
kernel void line_rasterizer(texture2d<half, access::read_write> tex        [[texture(0)]],
                            texture2d<half, access::read_write> shadow_tex [[texture(1)]],
                            uint2 gid                                      [[thread_position_in_grid]],
                            uint2 grid_size                                [[threads_per_grid]],
                            uint2 threadgroup_position_in_grid             [[threadgroup_position_in_grid ]],
                            uint2 thread_position_in_threadgroup           [[thread_position_in_threadgroup ]],
                            uint2 threads_per_threadgroup                  [[threads_per_threadgroup ]],
                            device const Uniforms *uni                     [[buffer(0)]],
                            device const Camera_Data *camera_data          [[buffer(1)]],
                            device const Voxel_Data *voxel_data            [[buffer(2)]]
                            ) {

    // SHADERTOY TRANSLATION:                            
    float4 iMouse = uni->cursor;
    float2 iResolution = float2(grid_size);
    float2 fragCoord = float2(gid);
    float4 fragColor = float4(0.0, 0.0, 0.0, 1.0);
    float iFrame = uni->flags[0]; // TODO: fix alignment
    //===========================================================
    RgnState rngState;
    rngState.seed = uint(uint(fragCoord.x) * uint(1973) + uint(fragCoord.y) * uint(9277) + uint(iFrame) * uint(26699)) | uint(1);

    float3 rayPosition = float3(0.0f, 0.0f, 0.0f);
    float cameraDistance = 1.0f / tan(c_FOVDegrees * 0.5f * c_pi / 180.0f);


    // calculate subpixel camera jitter for anti aliasing
    float2 jitter = float2(RandomFloat01(&rngState), RandomFloat01(&rngState)) - 0.5f;
    
    // calculate coordinates of the ray target on the imaginary pixel plane.
    // -1 to +1 on x,y axis. 1 unit away on the z axis
    float3 rayTarget = float3(((fragCoord+jitter)/iResolution.xy) * 2.0f - 1.0f, cameraDistance);

    float aspectRatio = iResolution.x / iResolution.y;
    rayTarget.y /= -aspectRatio;

    // calculate a normalized vector for the ray direction.
    // it's pointing from the ray position to the ray target.
    float3 rayDir = normalize(rayTarget - rayPosition);

    // raytrace for this pixel
    float3 color = float3(0.0f, 0.0f, 0.0f);
    for (int index = 0; index < c_numRendersPerFrame; ++index) {
    	color += GetColorForRay(rayPosition, rayDir, &rngState);
    }
    color = color / float(c_numRendersPerFrame);
 
     // average the frames together
    float3 lastFrameColor = float3(tex.read(gid).rgb);
    color = mix(lastFrameColor, color, 1.0f / float(iFrame+1));

    fragColor = float4(color, 1.0f);

    //===========================================================
    tex.write(half4(fragColor), gid);

    // apply exposure (how long the shutter is open)
    color *= c_exposure;
    // convert unbounded HDR color range to SDR color range
    color = ACESFilm(color);
    // convert from linear to sRGB for display
    fragColor = float4(LinearToSRGB(color), 1.0f);
    shadow_tex.write(half4(fragColor), gid);
}

// TODO: 
// distance from line to point
// Make Camera and Grid
// Make raycast from mouse