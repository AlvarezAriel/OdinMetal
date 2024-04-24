#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 cursor;
    float2 screen_size;
};
struct Camera_Data {
    float2 translation;
};

kernel void line_rasterizer(texture2d<half, access::read_write> tex  [[texture(0)]],
                            uint2 gid                                [[thread_position_in_grid]],
                            uint2 grid_size                          [[threads_per_grid]],
                            constant Uniforms *uni                   [[ buffer(0) ]],
                            device const Camera_Data& camera_data    [[buffer(1)]]) {

    if((gid.x >= tex.get_width()) || (gid.y >= tex.get_height()))
    {
        return;
    }

    float dist = distance(half2(gid.xy), half2(uni->cursor.zw));
    if(dist < 4) {
        float color = smoothstep(4,0, dist);
        float pre = tex.read(gid, 0).r;
        
        tex.write(half4(pre + color, 0.0, 0.0, 1.0), gid, 0);  
    }                  
}