using namespace metal;

struct Uniforms {
    float4 cursor;
    float4 toggle_layer;
    float2 screen_size;
};

struct ColoredVertex {
    float4 position [[position]];
};

struct Camera_Data {
    float2 translation;
};

vertex ColoredVertex vertex_main(constant float4 *position                   [[buffer(0)]],
                                    device const Camera_Data&  camera_data   [[buffer(1)]],
                                    uint vid                                 [[vertex_id]]) {
    ColoredVertex vert;
    vert.position = position[vid];
    
    vert.position.xy = vert.position.xy + camera_data.translation;

    return vert;
}

constexpr constant int MAX_MARCHING_STEPS = 255;
constexpr constant float MIN_DIST = 0.0;
constexpr constant float MAX_DIST = 100.0;
constexpr constant float PRECISION = 0.001;
constexpr constant float PI  = 3.1415926535897932384626433832795;
constexpr constant float PHI = 1.6180339887498948482045868343656;
constexpr constant int AA = 2;

float2 smin( float a, float b, float k ) {
    k *= 6.0;
    float h = max( k-abs(a-b), 0.0 )/k;
    float m = h*h*h*0.5;
    float s = m*k*(1.0/3.0); 
    return (a<b) ? float2(a-s,m) : float2(b-s,1.0-m);
}

float hash1( float n ) {
    return fract(sin(n)*43758.5453123);
}

float3 forwardSF( float i, float n) {
    float phi = 2.0*PI*fract(i/PHI);
    float zi = 1.0 - (2.0*i+1.0)/n;
    float sinTheta = sqrt( 1.0 - zi*zi);
    return float3( cos(phi)*sinTheta, sin(phi)*sinTheta, zi);
}

float2 map( float3 q, float iTime ) {
    // plane
    float2 res = float2( q.y, 2.0 );

    // sphere
    float d = length(q-float3(0.0,0.1+0.05*sin(iTime),0.0))-0.1;
    
    // smooth union    
    return smin(res.x,d,0.05);
}

float2 intersect(float3 ro, float3 rd, float iTime) {
	const float maxd = 10.0;

    float2 res = float2(0.0);
    float t = 0.0;
    for( int i=0; i<512; i++ )
    {
	    float2 h = map( ro+rd*t, iTime );
        if( (h.x<0.0) || (t>maxd) ) break;
        t += h.x;
        res = float2( t, h.y );
    }

    if( t>maxd ) res=float2(-1.0);
	return res;
}

// https://iquilezles.org/articles/normalsSDF
float3 calcNormal(float3 pos, float iTime ) {
    float2 e = float2(1.0,-1.0)*0.5773*0.005;
    return normalize( e.xyy*map( pos + e.xyy, iTime ).x + 
					  e.yyx*map( pos + e.yyx, iTime ).x + 
					  e.yxy*map( pos + e.yxy, iTime ).x + 
					  e.xxx*map( pos + e.xxx, iTime ).x );
}

// https://iquilezles.org/articles/nvscene2008/rwwtt.pdf
float calcAO(float3 pos, float3 nor, float ran, float iTime ) {
	float ao = 0.0;
    const int num = 32;
    for( int i=0; i<num; i++ ) {
        float3 ap = forwardSF( float(i)+ran, float(num) );
		ap *= sign( dot(ap,nor) ) * hash1(float(i));
        ao += clamp( map( pos + nor*0.01 + ap*0.2, iTime ).x*20.0, 0.0, 1.0 );
    }
	ao /= float(num);
	
    return clamp( ao, 0.0, 1.0 );
}

float3 render(float2 p, float4 ran, float iTime ) {
    //-----------------------------------------------------
    // camera
    //-----------------------------------------------------
	float an = 0.1*iTime;
	float3 ro = float3(0.4*sin(an),0.15,0.4*cos(an));
    float3 ta = float3(0.0,0.05,0.0);
    // camera matrix
    float3 ww = normalize( ta - ro );
    float3 uu = normalize( cross(ww,float3(0.0,-1.0,0.0) ) );
    float3 vv = normalize( cross(uu,ww));
	// create view ray
	float3 rd = normalize( p.x*uu + p.y*vv + 1.7*ww );

    //-----------------------------------------------------
	// render
    //-----------------------------------------------------
    
	float3 col = float3(1.0);

	// raymarch
    float3 uvw;
    float2 res = intersect(ro,rd, iTime);
    float t = res.x;
    if( t>0.0 ) {
        float3 pos = ro + t*rd;
        float3 nor = calcNormal(pos, iTime);
		float3 ref = reflect( rd, nor );
        float fre = clamp( 1.0 + dot(nor,rd), 0.0, 1.0 );
        float occ = calcAO( pos, nor, ran.y, iTime ); occ = occ*occ;

        // blend materials        
        col = mix( float3(0.0,0.05,1.0),
                   float3(1.0,0.0,0.0),
                   res.y );
        
        col = col*0.72 + 0.2*fre*float3(1.0,0.8,0.2);
        float3 lin  = 4.0*float3(0.7,0.8,1.0)*(0.5+0.5*nor.y)*occ;
             lin += 0.8*float3(1.0,1.0,1.0)*fre            *(0.6+0.4*occ);
        col = col * lin;
        col += 2.0*float3(0.8,0.9,1.00)*smoothstep(0.0,0.4,ref.y)*(0.06+0.94*pow(fre,5.0))*occ;
        col = mix( col, float3(1.0), 1.0-exp2(-0.04*t*t) );
    }

    // gamma and postpro
    col = pow(col,float3(0.4545));
    col *= 0.9;
    col = clamp(col,0.0,1.0);
    col = col*col*(3.0-2.0*col);
    
    // dithering
    col += (ran.x-0.5)/255.0;
    
	return col;
}

fragment float4 fragment_main(
    ColoredVertex vert                     [[stage_in]], 
    constant Uniforms *uni                 [[buffer(0)]],
    texture2d<half, access::sample> tex    [[texture(1)]],
    texture2d<half, access::sample> shadow [[texture(2)]]
) {
  //float2 uv = (vert.position.xy - .5 * uni->screen_size.x) / uni->screen_size.y;
    float iTime = uni->toggle_layer.x;
    float3 col = float3(0.0);
    for( int m=0; m<AA; m++ ) {
        for( int n=0; n<AA; n++ ) {
            float2 px = vert.position.xy + float2(float(m),float(n))/float(AA);
            //float4 ran = texelFetch( iChannel0, ifloat2(px*float(AA))&1023,0);

            float2 p = (2.0*px-uni->screen_size.xy)/uni->screen_size.y;
            col += render( p, float4(1.0), iTime );    
        }
    }

    col /= float(AA*AA);

    return float4(col, 1.0);
}