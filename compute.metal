#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 cursor;
    float2 screen_size;
};
struct Camera_Data {
    float2 translation;
};

float circle(float2 _st, float _radius){
    float2 dist = _st - float2(0.5);
    float blur = 0.4;
    return 1.-smoothstep(_radius-(_radius*blur),  _radius+(_radius*blur), dot(dist,dist)*4.0);
}

kernel void line_rasterizer(texture2d<half, access::read_write> tex  [[texture(0)]],
                            uint2 gid                                [[thread_position_in_grid]],
                            uint2 grid_size                          [[threads_per_grid]],
                            constant Uniforms *uni                   [[ buffer(0) ]],
                            device const Camera_Data& camera_data    [[buffer(1)]]) {

    uint2 centered_pos = (gid.xy - grid_size/2 );
    uint2 pos = uint2(uni->cursor.zw) + centered_pos;
    float color = circle(float2(gid.xy)/float2(grid_size), 0.5);
    float previous = tex.read(pos, 0).r;
    tex.write(half4(color + previous, 0.0, 0.0, 1.0), pos, 0);

}