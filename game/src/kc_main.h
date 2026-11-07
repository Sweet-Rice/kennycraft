#ifndef KC_MAIN_H
#define KC_MAIN_H
#include <stdint.h>
void kc_init(void);
void kc_frame(void);
void kc_set_resolution(int32_t width);   // 160 or 320
void kc_set_max_steps(int32_t steps);
void kc_draw_world(void);                // ray tracer or tile rasterizer
extern int32_t kc_use_raster;
#endif
