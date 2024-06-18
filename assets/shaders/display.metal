using namespace metal;

constexpr constant float PI  = 3.1415926535897932384626433832795;
constexpr constant float PHI = 1.6180339887498948482045868343656;
constexpr sampler textureSampler (mag_filter::linear,
                                  min_filter::linear);
                                  
struct Uniforms {
    float4 cursor;
    float4 toggle_layer;
    float2 screen_size;
};

struct ColoredVertex {
    float4 position [[position]];
};

struct Camera_Data {
    float4x4 look;
};

vertex ColoredVertex vertex_main(constant float4 *position                   [[buffer(0)]],
                                    device const Camera_Data&  camera_data   [[buffer(1)]],
                                    uint vid                                 [[vertex_id]]) {
    ColoredVertex vert;
    vert.position = position[vid];
    
    vert.position.xy = vert.position.xy;

    return vert;
}

//============== FRAGMENT ================

fragment half4 fragment_main(
    ColoredVertex vert                     [[stage_in]], 
    constant Uniforms *uni                 [[buffer(0)]],
    texture2d<half, access::sample> tex    [[texture(1)]],
    texture2d<half, access::sample> shadow [[texture(2)]]
) {
    float2 uv = (vert.position.xy) / uni->screen_size.y;
    float3 color = float3(shadow.sample(textureSampler, uv).rgb);
    //const float UNIT = 1.0 / 1024;
    // float3 color = float3(0.0); 
    // color += float3(tex.sample(textureSampler, uv + float2(-UNIT, -UNIT)).rgb);
    // color += float3(tex.sample(textureSampler, uv + float2( 0.0, -UNIT)).rgb);
    // color += float3(tex.sample(textureSampler, uv + float2( UNIT, -UNIT)).rgb);
    // color += float3(tex.sample(textureSampler, uv + float2(-UNIT,  0.0)).rgb);
    // color += float3(tex.sample(textureSampler, uv + float2( 0.0,  0.0)).rgb) * 3;
    // color += float3(tex.sample(textureSampler, uv + float2( UNIT,  0.0)).rgb);
    // color += float3(tex.sample(textureSampler, uv + float2(-UNIT,  UNIT)).rgb);
    // color += float3(tex.sample(textureSampler, uv + float2( 0.0,  UNIT)).rgb);
    // color += float3(tex.sample(textureSampler, uv + float2( UNIT,  UNIT)).rgb);
    // color = color/ 11.0;

    // gamma and postpro
    // color = pow(color,float3(0.4545));
    // color *= 0.9;
    // color = clamp(color,0.0,1.0);
    //color = color*color*(3.0-2.0*color);

    return half4(half3(color.rgb), 1.0);
}