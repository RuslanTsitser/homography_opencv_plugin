// This file ensures the homography library symbols are included in the final binary
// when using static linking with FFI

#import <Foundation/Foundation.h>

// Forward declare the struct
typedef struct {
    float center_x;
    float center_y;
    float rotation;
    float scale;
    double homography[9];
    float corners[8];
    int num_matches;
    int status;
} HomographyResult;

// Declare ALL external C functions from the static library
extern HomographyResult hg_find_homography_from_points(
    const float *pts0_x, const float *pts0_y,
    const float *pts1_x, const float *pts1_y,
    int num_points,
    int anchor_width, int anchor_height);
extern HomographyResult hg_find_homography(
    const void *anchor_bytes, size_t anchor_size,
    const void *scene_bytes, size_t scene_size);
extern const char* hg_lib_version(void);

// Store function pointers to prevent dead code stripping
static void* _homography_symbols[] __attribute__((used)) = {
    (void*)&hg_find_homography_from_points,
    (void*)&hg_find_homography,
    (void*)&hg_lib_version,
};

// Force the linker to include the library symbols
__attribute__((constructor))
static void HomographyPluginInit(void) {
    // Touch the symbols to prevent stripping
    NSLog(@"HomographyPlugin: symbols loaded, version: %s", hg_lib_version());
}

@interface HomographyPlugin : NSObject
@end

@implementation HomographyPlugin
+ (void)registerWithRegistrar:(NSObject*)registrar {
    // Symbols are used via FFI
    // Force reference to prevent dead code elimination
    (void)_homography_symbols;
}
@end

