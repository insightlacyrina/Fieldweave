#include <metal_stdlib>
using namespace metal;
struct FieldVertex { float4 position; float4 color; float4 meta; };
struct FieldUniforms {
    float2 viewport; float unit; float time;
    float4 width; float4 layers; float4 effects; float4 center;
};
struct RasterData { float4 position [[position]]; float4 color; float pointSize [[point_size]]; float glow; };
float driftHash(float x) { return fract(sin(x*127.1+311.7)*43758.5453); }
float3 driftRandom(float x) { return float3(driftHash(x+1.),driftHash(x+23.),driftHash(x+57.)); }
float3 boundedDrift(float seed,float time,float layer) {
    float t=max(0.,time)*3./(14.+driftHash(seed+17.)*14.);
    float segment=floor(t),f=fract(t),ease=f*f*f*(f*(f*6.-15.)+10.);
    float radius=layer<.5?.020:layer<2.5?.028:layer<4.5?.003:.018;
    return (mix(driftRandom(seed+segment*17.),driftRandom(seed+(segment+1.)*17.),ease)-driftRandom(seed))*radius;
}
vertex RasterData fieldVertex(uint id [[vertex_id]],device const FieldVertex* vertices [[buffer(0)]],constant FieldUniforms &u [[buffer(1)]]) {
    FieldVertex a=vertices[id];float3 p=a.position.xyz;float band=a.meta.y;float intensity=1.;
    bool points=u.center.w>.5;
    if(band<.5){p.x*=.72+.28*u.width.x;intensity=u.layers.x;}
    else if(band<1.5){p.x*=.72+.28*u.width.y;intensity=u.layers.y;}
    else if(band<2.5){p.x*=.72+.28*u.width.z;intensity=u.layers.z;}
    if(points&&band<5.5)p+=boundedDrift(a.meta.z*137.,u.time,band);
    if(band>2.5&&band<3.5){p.x+=u.center.x*.32;p.y+=u.width.w;intensity=u.center.y;}
    p.z*=.7+.3*u.effects.x;
    float perspective=1./(1.+p.z*.12);
    float2 pixel=float2(u.viewport.x*.5+p.x*u.unit*perspective,u.viewport.y*.5-(p.y*.94-p.z*.33)*u.unit*perspective);
    RasterData o;o.position=float4(pixel.x/u.viewport.x*2.-1.,1.-pixel.y/u.viewport.y*2.,0.,1.);
    float scintillation=1.+sin(u.time*.6+a.meta.z)*.11;
    float size=max(1.25,a.meta.x*1.2)*u.effects.w*clamp(u.unit/350.,.85,1.35);
    o.pointSize=u.center.z>.5?size*4.:size;
    float fade=band>2.5&&band<3.5?1.-smoothstep(.29,.38,abs(a.position.x)):1.;
    float gain=band<3.?1.55:1.;if(band>2.5&&band<3.5)gain=1.6;
    if(points&&band<.5)gain*=.95;
    o.color=float4(a.color.rgb*u.effects.y,a.color.a*intensity*scintillation*fade*gain);o.glow=u.center.z;return o;
}
fragment float4 fieldSolid(RasterData in [[stage_in]]) {return in.color;}
fragment float4 fieldParticle(RasterData in [[stage_in]],float2 coord [[point_coord]]) {
    float2 q=coord*2.-1.;float r=length(q);if(r>1.)discard_fragment();
    float alpha=in.color.a;float3 color=in.color.rgb;
    if(in.glow>.5)alpha*=exp(-r*r*5.)*.21;
    else {alpha*=1.-smoothstep(.18,1.,r);color=mix(color,float3(1.),exp(-r*r*15.)*.48);}
    return float4(color,alpha);
}
