#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 line;
    float4 flags;
};
struct Camera_Data {
    float2 translation;
};
struct Instance_Data {
    float4 pos;
};

// https://iquilezles.org/articles/smin
// float smin( float a, float b, float k )
// {
//     k *= 1.0;
//     float r = exp2(-a/k) + exp2(-b/k);
//     return -k*log2(r);
// }

half sigmoidsmin( half a, half b, half k )
{
    k *= log(2.0h);
    half x = (b-a)/k;
    half g = x/(1.0h-exp2(-x));
    return b - k * g;
}
float circularsmin( float a, float b, float k )
{
    k *= 1.0/(1.0-sqrt(0.5));
    float h = max( k-abs(a-b), 0.0 )/k;
    return min(a,b) - k*0.5*(1.0+h-sqrt(1.0-h*(h-2.0)));
}

half halfsmin( half a, half b, half k )
{
    k *= 1.0h;
    half r = exp2(-a/k) + exp2(-b/k);
    return -k*log2(r);
}

float sdSegment(float2 p, float2 a, float2 b, float r)
{
    float2 pa = p-a, ba = b-a;
    float h = clamp(dot(pa,ba)/dot(ba,ba), 0.0, 1.0);
    return length( pa - ba*h ) - r;
}

float sdOrientedBox(float2 p, float2 a, float2 b, float th )
{
    float l = length(b-a);
    float2  d = (b-a)/l;
    float2  q = (p-(a+b)*0.5);
          q = float2x2(d.x,-d.y,d.y,d.x)*q;
          q = abs(q)-float2(l,th)*0.9;
    return length(max(q,0.0)) + min(max(q.x,q.y),0.0);    
}

half smin( half a, half b, half k )
{
    k *= 16.0/3.0;
    half x = (b-a)/k;
    half g = (x> 1.0) ? x :
              (x<-1.0) ? 0.0 :
              (x+1.0)*(x+1.0)*(3.0-x*(x-2.0))/16.0;
    return b - k * g;
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
 
    if(uni->flags.x > 0.0) {
        tex.write(half4(1.0h, 1.0h, 1.0h, 1.0h), gid);
    } else {
        float brush_size = 6.0;
        float2 current_pos = float2(gid);  
        half subline = smoothstep(-10.h, 10.h, half(sdSegment(current_pos, uni->line.xy, uni->line.zw, 3.0)));
        half d = smoothstep(-16.h, 16.h, half(sdSegment(current_pos, uni->line.xy, uni->line.zw, brush_size)));
        float distance_to_start = smoothstep(-brush_size, +brush_size, distance(current_pos, uni->line.xy));

        half4 prev_color = tex.read(gid);
        half m;

        d = sqrt(d);

        m = prev_color.r * d; 
        half commit = min(prev_color.g, prev_color.r);

        tex.write(half4(commit, m, min(prev_color.b, subline), 1.h), gid);
        
        // if(distance_to_start > brush_size/2) {
        //     tex.write(half4(half3(color, 0.0, 0.0h), 1.h), gid);
        // }

        // float2 size = float2(grid_size);
        // float2 current_pos = float2(gid);    
        // float2 st = float2(gid) / size;    
        // st *= zoom;
        // float4 line = float4(uni->line.xy/ size, uni->line.zw/ size);
        // line *= zoom;

        // float d = 1. - clamp(sdOrientedBox(st * 0.5, line.xy * 0.5, line.zw * 0.5, 0.00001), 0., 1.);
        // half heatline = (1. - clamp(sdOrientedBox(st * 0.4, line.xy * 0.4, line.zw * 0.4, 0.00001), 0., 1.));
        // half4 prev_color = tex.read(gid);

        // half display = prev_color.r; 

        // half heat = smoothstep(0.1h, 1.0h, max(prev_color.b, heatline) * 0.9h);
        // half shadow = max(prev_color.g, half(d));
        // half field = prev_color.a;

        // if(heat < 0.01) {
        //     display = min(prev_color.r + shadow, 0.5h);
        //     //field = clamp(half(prev_color.a+dShadow), 0.0h, 1.0h);
        //     shadow = 0.h;
        // } else {
        //     // if(display > 0.h && shadow > 0.h) {
        //     //     shadow = display + shadow;
        //     //     //shadow = display;
        //     // }
        // }

        // tex.write(half4(display, shadow, heat, field), gid);
    }

}




// GAUSSIAN KERNEL 5x5
            // half acc; 
            // acc += tex.read(gid  - uint2(-2, -2)).g;
            // acc += tex.read(gid  - uint2(-1, -2)).g *  4;
            // acc += tex.read(gid  - uint2( 0, -2)).g *  7;
            // acc += tex.read(gid  - uint2( 1, -2)).g *  4;
            // acc += tex.read(gid  - uint2( 2, -2)).g;

            // acc += tex.read(gid  - uint2(-2, -1)).g *  4;
            // acc += tex.read(gid  - uint2(-1, -1)).g * 16;
            // acc += tex.read(gid  - uint2( 0, -1)).g * 26;
            // acc += tex.read(gid  - uint2( 1, -1)).g * 16;
            // acc += tex.read(gid  - uint2( 2, -1)).g *  4;

            // acc += tex.read(gid  - uint2(-2,  0)).g *  7;
            // acc += tex.read(gid  - uint2(-1,  0)).g * 26;
            // acc += field                            * 41;
            // acc += tex.read(gid  - uint2( 1,  0)).g * 26;
            // acc += tex.read(gid  - uint2( 2,  0)).g *  7;

            // acc += tex.read(gid  - uint2(-2,  1)).g *  4;
            // acc += tex.read(gid  - uint2(-1,  1)).g * 16;
            // acc += tex.read(gid  - uint2( 0,  1)).g * 26;
            // acc += tex.read(gid  - uint2( 1,  1)).g * 16;
            // acc += tex.read(gid  - uint2( 2,  1)).g *  4;

            // acc += tex.read(gid  - uint2(-2,  2)).g;
            // acc += tex.read(gid  - uint2(-1,  2)).g *  4;
            // acc += tex.read(gid  - uint2( 0,  2)).g *  7;
            // acc += tex.read(gid  - uint2( 1,  2)).g *  4;
            // acc += tex.read(gid  - uint2( 2,  2)).g;

            // float gaussian = float(acc) / 273.0;
            // field = half(gaussian);