#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 line;
};
struct Camera_Data {
    float2 translation;
};
struct Instance_Data {
    float4 pos;
};

// https://iquilezles.org/articles/smin
float2 smin(float a, float b, float k )
{
    float f1 = exp2( -k*a );
    float f2 = exp2( -k*b );
    return float2(-log2(f1+f2)/k,f2);
}

float sdSegment(float2 p, float2 a, float2 b )
{
    float2 pa = p-a, ba = b-a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h );
}

float sdOrientedBox(float2 p, float2 a, float2 b, float th )
{
    float l = length(b-a);
    float2  d = (b-a)/l;
    float2  q = (p-(a+b)*0.5);
          q = float2x2(d.x,-d.y,d.y,d.x)*q;
          q = abs(q)-float2(l,th)*0.5;
    return length(max(q,0.0)) + min(max(q.x,q.y),0.0);    
}

kernel void line_rasterizer(texture2d<half, access::read_write> tex        [[texture(0)]],
                            texture2d<half, access::read_write> shadow_tex [[texture(1)]],
                            uint2 gid                                      [[thread_position_in_grid]],
                            uint2 grid_size                                [[threads_per_grid]],
                            uint2 threadgroup_position_in_grid             [[threadgroup_position_in_grid ]],
                            uint2 thread_position_in_threadgroup           [[thread_position_in_threadgroup ]],
                            uint2 threads_per_threadgroup                  [[threads_per_threadgroup ]],
                            constant Uniforms *uni                         [[buffer(0) ]],
                            device const Camera_Data& camera_data          [[buffer(1)]],
                            device const Instance_Data* instance_data      [[buffer(2)]]
                            ) {
 
    float zoom = 50.0;                            
    float2 size = float2(grid_size);
    float2 current_pos = float2(gid);    
    float2 st = float2(gid) / size;    
    st *= zoom;
    float4 line = float4(uni->line.xy/ size, uni->line.zw/ size);
    line *= zoom;

    float d = 1. - sdOrientedBox(st, line.xy, line.zw, 0.00001);

    if(d > 0) {
        half4 prev_color = tex.read(gid, 0.0);
        tex.write(half4(prev_color.rgb + half3(d), 1.0), gid, 0);
    }
}