/*
 * ReKazumi fixed 3x RIFE-NCNN video filter for mpv.
 *
 * This file is compiled into the pinned Android libmpv build. Neural network
 * inference lives in libkazumi_rife.so so the player and model runtime can be
 * upgraded independently.
 */

#include <dlfcn.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <libavutil/pixfmt.h>

#include "common/common.h"
#include "common/msg.h"
#include "filters/f_autoconvert.h"
#include "filters/filter.h"
#include "filters/filter_internal.h"
#include "filters/frame.h"
#include "filters/user_filters.h"
#include "options/m_option.h"
#include "video/fmt-conversion.h"
#include "video/mp_image.h"

#define KAZUMI_RIFE_ABI_VERSION 1
#define KAZUMI_RIFE_OUTPUTS_PER_PAIR 3
#define KAZUMI_RIFE_ERROR_CAPACITY 256

typedef void *kazumi_rife_handle;
typedef int (*rife_abi_version_fn)(void);
typedef kazumi_rife_handle (*rife_create_fn)(
    const char *, int, char *, size_t);
typedef int (*rife_process_fn)(
    kazumi_rife_handle,
    const float *, const float *, const float *,
    const float *, const float *, const float *,
    float *, float *, float *,
    int, int, ptrdiff_t, float, char *, size_t);
typedef int (*rife_process_pair_fn)(
    kazumi_rife_handle,
    const float *, const float *, const float *,
    const float *, const float *, const float *,
    float *, float *, float *,
    float *, float *, float *,
    int, int, ptrdiff_t, char *, size_t);
typedef void (*rife_destroy_fn)(kazumi_rife_handle);

struct rife_opts {
    char *model_path;
    int gpu_id;
    double duplicate_threshold;
    double scene_threshold;
    int sample_step;
};

struct priv {
    struct rife_opts *opts;
    struct mp_autoconvert *conv;

    void *library;
    kazumi_rife_handle rife;
    rife_process_fn process;
    rife_process_pair_fn process_pair;
    rife_destroy_fn destroy;

    struct mp_image *previous;
    struct mp_frame pending[KAZUMI_RIFE_OUTPUTS_PER_PAIR];
    int pending_index;
    int pending_count;
    bool inference_warning_shown;
    double last_frame_delta;
};

static void clear_pending(struct priv *p)
{
    for (int i = p->pending_index; i < p->pending_count; ++i)
        mp_frame_unref(&p->pending[i]);
    memset(p->pending, 0, sizeof(p->pending));
    p->pending_index = 0;
    p->pending_count = 0;
}

static void reset_state(struct mp_filter *f)
{
    struct priv *p = f->priv;
    mp_image_unrefp(&p->previous);
    clear_pending(p);
    p->last_frame_delta = 0.0;
}

static void set_interpolated_timing(struct mp_image *image, double delta)
{
    image->pkt_duration = delta / 3.0;
    if (image->nominal_fps > 0.0)
        image->nominal_fps *= 3.0;
}

static void destroy_filter(struct mp_filter *f)
{
    struct priv *p = f->priv;
    reset_state(f);
    if (p->rife && p->destroy)
        p->destroy(p->rife);
    p->rife = NULL;
    if (p->library)
        dlclose(p->library);
    p->library = NULL;
}

static bool queue_image(struct priv *p, struct mp_image *image)
{
    if (!image || p->pending_count >= KAZUMI_RIFE_OUTPUTS_PER_PAIR) {
        mp_image_unrefp(&image);
        return false;
    }
    p->pending[p->pending_count++] = MAKE_FRAME(MP_FRAME_VIDEO, image);
    return true;
}

static bool emit_pending(struct mp_filter *f)
{
    struct priv *p = f->priv;
    if (p->pending_index >= p->pending_count)
        return false;
    if (!mp_pin_in_needs_data(f->ppins[1]))
        return true;

    struct mp_frame frame = p->pending[p->pending_index];
    p->pending[p->pending_index] = MP_NO_FRAME;
    ++p->pending_index;
    mp_pin_in_write(f->ppins[1], frame);

    if (p->pending_index >= p->pending_count)
        clear_pending(p);
    else
        mp_filter_internal_mark_progress(f);
    return true;
}

static double sampled_rgb_difference(
    const struct mp_image *first,
    const struct mp_image *second,
    int sample_step)
{
    if (!first || !second || first->w != second->w || first->h != second->h)
        return INFINITY;

    const int step = MPMAX(sample_step, 1);
    double total = 0.0;
    int samples = 0;

    for (int y = step / 2; y < first->h; y += step) {
        const float *first_g = (const float *)(first->planes[0] + y * first->stride[0]);
        const float *first_b = (const float *)(first->planes[1] + y * first->stride[1]);
        const float *first_r = (const float *)(first->planes[2] + y * first->stride[2]);
        const float *second_g = (const float *)(second->planes[0] + y * second->stride[0]);
        const float *second_b = (const float *)(second->planes[1] + y * second->stride[1]);
        const float *second_r = (const float *)(second->planes[2] + y * second->stride[2]);

        for (int x = step / 2; x < first->w; x += step) {
            const double dr = fabs((double)first_r[x] - second_r[x]);
            const double dg = fabs((double)first_g[x] - second_g[x]);
            const double db = fabs((double)first_b[x] - second_b[x]);
            const double difference = dr * 0.2126 + dg * 0.7152 + db * 0.0722;
            if (isfinite(difference)) {
                total += MPMIN(difference, 1.0);
                ++samples;
            }
        }
    }

    return samples > 0 ? total / samples : INFINITY;
}

static bool compatible_float_planes(
    const struct mp_image *first,
    const struct mp_image *second,
    const struct mp_image *output)
{
    if (!first || !second || !output)
        return false;
    if (first->w != second->w || first->h != second->h ||
        first->w != output->w || first->h != output->h)
        return false;

    const int stride = first->stride[0];
    if (stride <= 0 || stride % (int)sizeof(float) != 0)
        return false;
    for (int plane = 0; plane < 3; ++plane) {
        if (first->stride[plane] != stride ||
            second->stride[plane] != stride ||
            output->stride[plane] != stride)
            return false;
    }
    return true;
}

static struct mp_image *make_hold_frame(struct mp_image *source, double pts)
{
    struct mp_image *copy = mp_image_new_copy(source);
    if (copy)
        copy->pts = pts;
    return copy;
}

static struct mp_image *make_interpolated_frame(
    struct mp_filter *f,
    struct mp_image *first,
    struct mp_image *second,
    double pts,
    float timestep)
{
    struct priv *p = f->priv;
    struct mp_image *output = mp_image_alloc(first->imgfmt, first->w, first->h);
    if (!output)
        return NULL;
    mp_image_copy_attributes(output, first);
    output->pts = pts;

    if (!compatible_float_planes(first, second, output)) {
        MP_WARN(f, "RIFE frame layout is not compatible; holding source frame.\n");
        mp_image_unrefp(&output);
        return make_hold_frame(first, pts);
    }

    char error[KAZUMI_RIFE_ERROR_CAPACITY] = {0};
    const ptrdiff_t stride = first->stride[0] / (ptrdiff_t)sizeof(float);
    const int result = p->process(
        p->rife,
        (const float *)first->planes[2],
        (const float *)first->planes[0],
        (const float *)first->planes[1],
        (const float *)second->planes[2],
        (const float *)second->planes[0],
        (const float *)second->planes[1],
        (float *)output->planes[2],
        (float *)output->planes[0],
        (float *)output->planes[1],
        first->w,
        first->h,
        stride,
        timestep,
        error,
        sizeof(error));

    if (result == 0)
        return output;

    if (!p->inference_warning_shown) {
        MP_WARN(f, "RIFE inference failed (%d): %s; falling back to hold frames.\n",
                result, error[0] ? error : "unknown error");
        p->inference_warning_shown = true;
    }
    mp_image_unrefp(&output);
    return make_hold_frame(first, pts);
}

static bool make_interpolated_pair(
    struct mp_filter *f,
    struct mp_image *first,
    struct mp_image *second,
    double first_pts,
    double second_pts,
    struct mp_image **first_output,
    struct mp_image **second_output)
{
    struct priv *p = f->priv;
    *first_output = mp_image_alloc(first->imgfmt, first->w, first->h);
    *second_output = mp_image_alloc(first->imgfmt, first->w, first->h);
    if (!*first_output || !*second_output)
        goto fail;

    mp_image_copy_attributes(*first_output, first);
    mp_image_copy_attributes(*second_output, first);
    (*first_output)->pts = first_pts;
    (*second_output)->pts = second_pts;

    if (!compatible_float_planes(first, second, *first_output) ||
        !compatible_float_planes(first, second, *second_output)) {
        MP_WARN(f, "RIFE paired frame layout is not compatible.\n");
        goto fail;
    }

    char error[KAZUMI_RIFE_ERROR_CAPACITY] = {0};
    const ptrdiff_t stride = first->stride[0] / (ptrdiff_t)sizeof(float);
    const int result = p->process_pair(
        p->rife,
        (const float *)first->planes[2],
        (const float *)first->planes[0],
        (const float *)first->planes[1],
        (const float *)second->planes[2],
        (const float *)second->planes[0],
        (const float *)second->planes[1],
        (float *)(*first_output)->planes[2],
        (float *)(*first_output)->planes[0],
        (float *)(*first_output)->planes[1],
        (float *)(*second_output)->planes[2],
        (float *)(*second_output)->planes[0],
        (float *)(*second_output)->planes[1],
        first->w,
        first->h,
        stride,
        error,
        sizeof(error));

    if (result == 0)
        return true;

    if (!p->inference_warning_shown) {
        MP_WARN(f, "Paired RIFE inference failed (%d): %s.\n",
                result, error[0] ? error : "unknown error");
        p->inference_warning_shown = true;
    }

fail:
    mp_image_unrefp(first_output);
    mp_image_unrefp(second_output);
    return false;
}

static void build_pair_output(
    struct mp_filter *f,
    struct mp_image *current)
{
    struct priv *p = f->priv;
    struct mp_image *first = p->previous;
    p->previous = current;

    if (!first)
        return;

    const double delta = current->pts - first->pts;
    queue_image(p, first);

    if (first->pts == MP_NOPTS_VALUE || current->pts == MP_NOPTS_VALUE ||
        !isfinite(delta) || delta <= 0.0) {
        return;
    }

    p->last_frame_delta = delta;
    set_interpolated_timing(first, delta);

    const double first_pts = first->pts + delta / 3.0;
    const double second_pts = first->pts + delta * 2.0 / 3.0;
    const double difference = sampled_rgb_difference(
        first, current, p->opts->sample_step);
    const bool hold = difference <= p->opts->duplicate_threshold ||
                      difference >= p->opts->scene_threshold;

    if (hold) {
        queue_image(p, make_hold_frame(first, first_pts));
        queue_image(p, make_hold_frame(first, second_pts));
        return;
    }

    if (p->process_pair) {
        struct mp_image *first_output = NULL;
        struct mp_image *second_output = NULL;
        if (make_interpolated_pair(
                f,
                first,
                current,
                first_pts,
                second_pts,
                &first_output,
                &second_output)) {
            queue_image(p, first_output);
            queue_image(p, second_output);
            return;
        }

        queue_image(p, make_hold_frame(first, first_pts));
        queue_image(p, make_hold_frame(first, second_pts));
        return;
    }

    queue_image(p, make_interpolated_frame(
        f, first, current, first_pts, 1.0F / 3.0F));
    queue_image(p, make_interpolated_frame(
        f, first, current, second_pts, 2.0F / 3.0F));
}

static void process_filter(struct mp_filter *f)
{
    struct priv *p = f->priv;

    if (emit_pending(f))
        return;
    if (!mp_pin_in_needs_data(f->ppins[1]))
        return;

    if (mp_pin_can_transfer_data(p->conv->f->pins[0], f->ppins[0])) {
        struct mp_frame input = mp_pin_out_read(f->ppins[0]);
        mp_pin_in_write(p->conv->f->pins[0], input);
    }

    if (!mp_pin_out_request_data(p->conv->f->pins[1]))
        return;

    struct mp_frame frame = mp_pin_out_read(p->conv->f->pins[1]);
    if (frame.type == MP_FRAME_EOF) {
        if (p->previous) {
            if (p->last_frame_delta > 0.0)
                set_interpolated_timing(p->previous, p->last_frame_delta);
            queue_image(p, p->previous);
            p->previous = NULL;
            mp_pin_out_repeat_eof(p->conv->f->pins[1]);
            emit_pending(f);
        } else {
            mp_pin_in_write(f->ppins[1], frame);
        }
        return;
    }

    if (frame.type != MP_FRAME_VIDEO) {
        MP_ERR(f, "RIFE received unsupported frame type.\n");
        mp_frame_unref(&frame);
        mp_filter_internal_mark_failed(f);
        return;
    }

    struct mp_image *current = frame.data;
    if (!p->previous) {
        p->previous = current;
        mp_filter_internal_mark_progress(f);
        return;
    }

    build_pair_output(f, current);
    emit_pending(f);
}

static const struct mp_filter_info filter_info = {
    .name = "rife-ncnn",
    .priv_size = sizeof(struct priv),
    .destroy = destroy_filter,
    .process = process_filter,
    .reset = reset_state,
};

static bool load_runtime(struct mp_filter *f)
{
    struct priv *p = f->priv;
    char error[KAZUMI_RIFE_ERROR_CAPACITY] = {0};

    p->library = dlopen("libkazumi_rife.so", RTLD_NOW | RTLD_LOCAL);
    if (!p->library) {
        MP_ERR(f, "Unable to load libkazumi_rife.so: %s\n", dlerror());
        return false;
    }

    rife_abi_version_fn abi_version = dlsym(p->library, "kazumi_rife_abi_version");
    rife_create_fn create = dlsym(p->library, "kazumi_rife_create");
    p->process = dlsym(p->library, "kazumi_rife_process");
    p->process_pair = dlsym(p->library, "kazumi_rife_process_pair");
    p->destroy = dlsym(p->library, "kazumi_rife_destroy");
    if (!abi_version || !create || !p->process || !p->destroy) {
        MP_ERR(f, "libkazumi_rife.so has an incomplete API.\n");
        return false;
    }
    if (abi_version() != KAZUMI_RIFE_ABI_VERSION) {
        MP_ERR(f, "libkazumi_rife.so ABI mismatch.\n");
        return false;
    }

    p->rife = create(
        p->opts->model_path,
        p->opts->gpu_id,
        error,
        sizeof(error));
    if (!p->rife) {
        MP_ERR(f, "Unable to initialize RIFE: %s\n",
               error[0] ? error : "unknown error");
        return false;
    }
    return true;
}

static struct mp_filter *create_filter(struct mp_filter *parent, void *options)
{
    struct mp_filter *f = mp_filter_create(parent, &filter_info);
    if (!f) {
        talloc_free(options);
        return NULL;
    }

    struct priv *p = f->priv;
    p->opts = talloc_steal(p, options);
    if (!p->opts->model_path || !p->opts->model_path[0]) {
        MP_ERR(f, "rife-ncnn requires model-path.\n");
        talloc_free(f);
        return NULL;
    }

    mp_filter_add_pin(f, MP_PIN_IN, "in");
    mp_filter_add_pin(f, MP_PIN_OUT, "out");

    p->conv = mp_autoconvert_create(f);
    if (!p->conv) {
        talloc_free(f);
        return NULL;
    }
    mp_autoconvert_add_imgfmt(
        p->conv,
        pixfmt2imgfmt(AV_PIX_FMT_GBRPF32),
        0);

    if (!load_runtime(f)) {
        talloc_free(f);
        return NULL;
    }

    MP_INFO(f, "RIFE-NCNN fixed 3x interpolation enabled (%s path).\n",
            p->process_pair ? "paired" : "legacy");
    return f;
}

#define OPT_BASE_STRUCT struct rife_opts
static const m_option_t options[] = {
    {"model-path", OPT_STRING(model_path)},
    {"gpu-id", OPT_INT(gpu_id)},
    {"duplicate-threshold", OPT_DOUBLE(duplicate_threshold), M_RANGE(0.0, 1.0)},
    {"scene-threshold", OPT_DOUBLE(scene_threshold), M_RANGE(0.0, 1.0)},
    {"sample-step", OPT_INT(sample_step), M_RANGE(1, 128)},
    {0}
};

const struct mp_user_filter_entry vf_rife_ncnn = {
    .desc = {
        .description = "fixed 3x RIFE-NCNN Vulkan interpolation",
        .name = "rife-ncnn",
        .priv_size = sizeof(OPT_BASE_STRUCT),
        .priv_defaults = &(const OPT_BASE_STRUCT){
            .gpu_id = -1,
            .duplicate_threshold = 0.0015,
            .scene_threshold = 0.22,
            .sample_step = 16,
        },
        .options = options,
    },
    .create = create_filter,
};
