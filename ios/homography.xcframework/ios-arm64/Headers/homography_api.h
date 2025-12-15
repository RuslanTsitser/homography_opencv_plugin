#ifndef HOMOGRAPHY_API_H
#define HOMOGRAPHY_API_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

    /**
     * Result of homography detection
     */
    typedef struct
    {
        // Position of anchor center on scene (pixels)
        float center_x;
        float center_y;

        // Rotation angle (radians, clockwise)
        float rotation;

        // Scale factor (1.0 = same size as anchor)
        float scale;

        // 3x3 homography matrix (row-major order)
        // Transforms points from anchor to scene coordinates
        double homography[9];

        // Four corners of the detected anchor on scene (clockwise from top-left)
        float corners[8]; // [x0,y0, x1,y1, x2,y2, x3,y3]

        // Number of good matches found
        int num_matches;

        // Status code:
        //   1 = success (anchor found)
        //   0 = anchor not found (not enough matches or bad homography)
        //  -1 = error (invalid input)
        //  -2 = error (failed to decode anchor image)
        //  -3 = error (failed to decode scene image)
        int status;
    } HomographyResult;

    /**
     * Find anchor image on scene image and compute homography
     *
     * @param anchor_bytes  Encoded image bytes of anchor (JPEG/PNG)
     * @param anchor_size   Size of anchor_bytes in bytes
     * @param scene_bytes   Encoded image bytes of scene (JPEG/PNG)
     * @param scene_size    Size of scene_bytes in bytes
     * @return HomographyResult with detection results
     *
     * Note: Both images should be encoded as JPEG or PNG.
     * The function will decode them internally.
     */
    FFI_PLUGIN_EXPORT HomographyResult hg_find_homography(
        const uint8_t *anchor_bytes, size_t anchor_size,
        const uint8_t *scene_bytes, size_t scene_size);

    /**
     * Find anchor image on scene image (raw pixel data version)
     *
     * @param anchor_data     Raw pixel data of anchor (RGB or RGBA)
     * @param anchor_width    Width of anchor image
     * @param anchor_height   Height of anchor image
     * @param anchor_channels Number of channels (3 for RGB, 4 for RGBA)
     * @param scene_data      Raw pixel data of scene
     * @param scene_width     Width of scene image
     * @param scene_height    Height of scene image
     * @param scene_channels  Number of channels (3 for RGB, 4 for RGBA)
     * @return HomographyResult with detection results
     */
    FFI_PLUGIN_EXPORT HomographyResult hg_find_homography_raw(
        const uint8_t *anchor_data, int anchor_width, int anchor_height, int anchor_channels,
        const uint8_t *scene_data, int scene_width, int scene_height, int scene_channels);

    /**
     * Compute homography from matched point pairs (from external matcher like LightGlue)
     *
     * @param pts0_x       Array of X coordinates for anchor points
     * @param pts0_y       Array of Y coordinates for anchor points
     * @param pts1_x       Array of X coordinates for scene points
     * @param pts1_y       Array of Y coordinates for scene points
     * @param num_points   Number of point pairs
     * @param anchor_width  Width of anchor image (for corner calculation)
     * @param anchor_height Height of anchor image (for corner calculation)
     * @return HomographyResult with detection results
     *
     * Note: Requires at least 4 point pairs. Uses RANSAC for robust estimation.
     */
    FFI_PLUGIN_EXPORT HomographyResult hg_find_homography_from_points(
        const float *pts0_x, const float *pts0_y,
        const float *pts1_x, const float *pts1_y,
        int num_points,
        int anchor_width, int anchor_height);

    /**
     * Get library version string
     * @return Version string (e.g., "1.0.0")
     */
    FFI_PLUGIN_EXPORT const char *hg_lib_version(void);

    // ============================================================================
    // Paper Detection API (Contour-based detection -> Homography -> Pose)
    // ============================================================================

    /**
     * Result of paper/document detection
     */
    typedef struct
    {
        // Four corners of the detected paper in image coordinates (clockwise from top-left)
        float corners[8]; // [x0,y0, x1,y1, x2,y2, x3,y3]

        // Center of the detected paper
        float center_x;
        float center_y;

        // 3x3 homography matrix (row-major order)
        // Transforms points from canonical paper coordinates to image coordinates
        double homography[9];

        // Camera pose: rotation vector (Rodrigues)
        double rvec[3];

        // Camera pose: translation vector
        double tvec[3];

        // Contour area in pixels
        float area;

        // Contour perimeter in pixels
        float perimeter;

        // Aspect ratio of the detected rectangle (width/height)
        float aspect_ratio;

        // Status code:
        //   1 = success (paper found)
        //   0 = paper not found (no valid quadrilateral detected)
        //  -1 = error (invalid input)
        int status;
    } PaperDetectionResult;

    /**
     * Configuration for paper detection
     */
    typedef struct
    {
        // Canny edge detection thresholds
        int canny_threshold1; // default: 50
        int canny_threshold2; // default: 150

        // Gaussian blur kernel size (must be odd, 0 to disable)
        int blur_kernel_size; // default: 5

        // Minimum area ratio (detected area / image area)
        float min_area_ratio; // default: 0.05 (5% of image)

        // Maximum area ratio
        float max_area_ratio; // default: 0.95 (95% of image)

        // Expected aspect ratio of the paper (width/height, e.g., A4 = 210/297 ≈ 0.707)
        float expected_aspect_ratio; // default: 0.707 (A4)

        // Tolerance for aspect ratio matching
        float aspect_ratio_tolerance; // default: 0.3 (30% deviation allowed)

        // Paper physical dimensions in mm (for pose estimation)
        float paper_width_mm;  // default: 210 (A4)
        float paper_height_mm; // default: 297 (A4)

        // Camera intrinsic parameters (for pose estimation)
        // If focal_length <= 0, pose estimation is skipped
        float focal_length; // focal length in pixels
        float cx;           // principal point x
        float cy;           // principal point y
    } PaperDetectionConfig;

    /**
     * Detect paper/document in image using contour detection
     *
     * @param image_data      Raw pixel data (grayscale, RGB, or RGBA)
     * @param image_width     Width of image
     * @param image_height    Height of image
     * @param image_channels  Number of channels (1, 3, or 4)
     * @param config          Detection configuration (can be NULL for defaults)
     * @return PaperDetectionResult with detection results
     *
     * Note: This function detects rectangular paper-like objects in the image
     * using edge detection and contour analysis. It returns the four corners
     * of the detected paper, a homography matrix, and optionally camera pose.
     */
    FFI_PLUGIN_EXPORT PaperDetectionResult hg_detect_paper(
        const uint8_t *image_data, int image_width, int image_height, int image_channels,
        const PaperDetectionConfig *config);

    /**
     * Detect paper/document in encoded image (JPEG/PNG)
     *
     * @param image_bytes     Encoded image bytes
     * @param image_size      Size of image_bytes
     * @param config          Detection configuration (can be NULL for defaults)
     * @return PaperDetectionResult with detection results
     */
    FFI_PLUGIN_EXPORT PaperDetectionResult hg_detect_paper_encoded(
        const uint8_t *image_bytes, size_t image_size,
        const PaperDetectionConfig *config);

    /**
     * Initialize default paper detection configuration
     *
     * @return Default configuration for A4 paper detection
     */
    FFI_PLUGIN_EXPORT PaperDetectionConfig hg_default_paper_config(void);

#ifdef __cplusplus
}
#endif

#endif // HOMOGRAPHY_API_H
