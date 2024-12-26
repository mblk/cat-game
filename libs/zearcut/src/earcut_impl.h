#pragma once

#ifdef __cplusplus
#include <cstddef>
#include <cstdint>
extern "C"
{
#else
#include <stddef.h>
#include <stdint.h>
#endif

typedef void*(*EarcutAllocFnType)(size_t);
typedef void(*EarcutFreeFnType)(void*);

typedef struct {
    float x;
    float y;
} vec2_t;

typedef struct {
    size_t num_indices;
    uint32_t *indices;
} earcut_result_t;

void earcut_set_allocator(EarcutAllocFnType alloc_fn, EarcutFreeFnType free_fn);

void earcut_create(size_t num_points, const vec2_t *points, earcut_result_t *result);
void earcut_free(earcut_result_t *result);

#ifdef __cplusplus
}
#endif