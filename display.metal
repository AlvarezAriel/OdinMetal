using namespace metal;
struct Uniforms {
    float4 cursor;
    float2 screen_size;
};
struct ColoredVertex {
    float4 position [[position]];
    float4 color;
};
struct Camera_Data {
    float2 translation;
};

vertex ColoredVertex vertex_main(constant float4 *position                [[buffer(0)]],
                                    constant float4 *color                   [[buffer(1)]],
                                    device const Camera_Data&  camera_data   [[buffer(2)]],
                                    uint vid                                 [[vertex_id]]) {
    ColoredVertex vert;
    vert.position = position[vid];
    vert.color    = color[vid];
    
    vert.position.xy = vert.position.xy + camera_data.translation;

    return vert;
}

float circle(float2 _st, float _radius){
    float2 dist = _st;
    return 1.-smoothstep(_radius-(_radius*0.01),
                            _radius+(_radius*0.01),
                            dot(dist,dist)*4.0);
}

fragment float4 fragment_main(
    ColoredVertex vert [[stage_in]], 
    constant Uniforms *uni [[ buffer(0) ]],
    texture2d<half, access::sample> tex [[texture(1)]]
) {
    float2 size = uni->screen_size.xy;
    float2 st = (vert.position.xy / size);
    float2 cur = uni->cursor.xy;

    sampler simpleSampler;
    float4 colorSample = float4(tex.sample(simpleSampler, st));
    float4 debugColor = float4(st, 0.0, 1.0);
    return colorSample + float4(float3(circle(st - cur, 0.0005)) ,1.0);
}