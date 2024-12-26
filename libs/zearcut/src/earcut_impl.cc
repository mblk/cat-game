#include <new>

#include <array>
#include <vector>
#include <cstring>

#include <cassert>
#include <cstddef>
#include <cstdint>

#include <mapbox/earcut.hpp>

#include "earcut_impl.h"

static EarcutAllocFnType g_alloc_fn = NULL;
static EarcutFreeFnType g_free_fn = NULL;

void* operator new(std::size_t n) noexcept(false) {
    assert(g_alloc_fn);
    assert(g_free_fn);
    assert(n);

    return g_alloc_fn(n);
}

void operator delete(void* p) throw() {
    assert(g_alloc_fn);
    assert(g_free_fn);
    assert(p);

    g_free_fn(p);
}

extern "C" {

void earcut_set_allocator(EarcutAllocFnType alloc_fn, EarcutFreeFnType free_fn) {
    g_alloc_fn = alloc_fn;
    g_free_fn = free_fn;
}

void earcut_create(size_t num_points, const vec2_t *points, earcut_result_t *result) {
    assert(num_points >= 3);
    assert(points);
    assert(result);

    using Coord = double;
    using N = uint32_t;
    using Point = std::array<Coord, 2>;

    // Fill polygon structure with actual data. Any winding order works.
    // The first polyline defines the main polygon.
    // Following polylines define holes.
    std::vector<std::vector<Point>> polygon;

    std::vector<Point> vertices;
    for (size_t i = 0; i < num_points; i++) {
        vertices.push_back({ points[i].x, points[i].y });
    }

    polygon.push_back(vertices);

    // Run tessellation
    // Returns array of indices that refer to the vertices of the input polygon.
    // Three subsequent indices form a triangle. Output triangles are clockwise.
    std::vector<N> indices = mapbox::earcut<N>(polygon);

    // Fill result structure
    result->num_indices = indices.size();
    result->indices = new uint32_t[result->num_indices];
    memcpy(result->indices, indices.data(), sizeof(uint32_t) * result->num_indices);
}

void earcut_free(earcut_result_t *result) {
    assert(result);
    assert(result->num_indices);
    assert(result->indices);

    delete[] result->indices;
}

}