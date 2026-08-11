#ifndef RIFE_NORMALIZED_IO_COMP_H
#define RIFE_NORMALIZED_IO_COMP_H

// mpv's GBRPF32 frames already contain normalized RGB values. These shaders
// only pad/crop and convert storage precision; they deliberately avoid the
// legacy 0..255 round trip used by the command-line RIFE implementation.
static const char rife_preproc_normalized_comp_data[] = R"(#version 450

#if NCNN_fp16_storage
#extension GL_EXT_shader_16bit_storage: require
#endif

layout (binding = 0) readonly buffer bottom_blob { float bottom_blob_data[]; };
layout (binding = 1) writeonly buffer top_blob { sfp top_blob_data[]; };

layout (push_constant) uniform parameter
{
int w;
int h;
int cstep;
int outw;
int outh;
int outcstep;
} p;

void main()
{
int gx = int(gl_GlobalInvocationID.x);
int gy = int(gl_GlobalInvocationID.y);
int gz = int(gl_GlobalInvocationID.z);

if (gx >= p.outw || gy >= p.outh || gz >= 3)
return;

int out_offset = gz * p.outcstep + gy * p.outw + gx;
if (gx >= p.w || gy >= p.h)
{
top_blob_data[out_offset] = sfp(0.f);
return;
}

int in_offset = gz * p.cstep + gy * p.w + gx;
top_blob_data[out_offset] = sfp(bottom_blob_data[in_offset]);
}
)";

static const char rife_postproc_normalized_comp_data[] = R"(#version 450

#if NCNN_fp16_storage
#extension GL_EXT_shader_16bit_storage: require
#endif

layout (binding = 0) readonly buffer bottom_blob { sfp bottom_blob_data[]; };
layout (binding = 1) writeonly buffer top_blob { float top_blob_data[]; };

layout (push_constant) uniform parameter
{
int w;
int h;
int cstep;
int outw;
int outh;
int outcstep;
} p;

void main()
{
int gx = int(gl_GlobalInvocationID.x);
int gy = int(gl_GlobalInvocationID.y);
int gz = int(gl_GlobalInvocationID.z);

if (gx >= p.outw || gy >= p.outh || gz >= 3)
return;

int in_offset = gz * p.cstep + gy * p.w + gx;
int out_offset = gz * p.outcstep + gy * p.outw + gx;
top_blob_data[out_offset] = float(bottom_blob_data[in_offset]);
}
)";

#endif  // RIFE_NORMALIZED_IO_COMP_H
