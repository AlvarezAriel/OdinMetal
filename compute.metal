#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 cursor;
    float2 screen_size;
};
struct Camera_Data {
    float2 translation;
};
struct Instance_Data {
    float4 pos;
};

float circle(float2 _st, float _radius){
    float2 dist = _st - float2(0.5);
    float blur = 0.4;
    return 1.-smoothstep(_radius-(_radius*blur),  _radius+(_radius*blur), dot(dist,dist)*4.0);
}

kernel void line_rasterizer(texture2d<half, access::write> tex   [[texture(0)]],
                            uint2 gid                                 [[thread_position_in_grid]],
                            uint2 grid_size                           [[threads_per_grid]],
                            uint2 threadgroup_position_in_grid        [[threadgroup_position_in_grid ]],
                            uint2 thread_position_in_threadgroup      [[thread_position_in_threadgroup ]],
                            uint2 threads_per_threadgroup             [[threads_per_threadgroup ]],
                            constant Uniforms *uni                    [[buffer(0) ]],
                            device const Camera_Data& camera_data     [[buffer(1)]],
                            device const Instance_Data* instance_data [[buffer(2)]]
                            ) {
    uint2 center = threads_per_threadgroup.xy/2;
    uint2 current_pos = thread_position_in_threadgroup.xy;
    float dist = distance(float2(current_pos), float2(center));
    if(dist < 4) {
        {
            float2 brush_pos = instance_data[threadgroup_position_in_grid.y].pos.xy;
            uint2 pos = uint2(brush_pos) + current_pos;
            tex.write(half4(1.0, 1.0, 1.0, 1.0), pos - center, 0);
        }
        {
            float2 brush_pos = instance_data[threadgroup_position_in_grid.y].pos.zw;
            uint2 pos = uint2(brush_pos) + current_pos;
            tex.write(half4(1.0, 1.0, 1.0, 1.0), pos - center, 0);
        }
    }
}