#include "homography_api.h"
#include <vector>
#include <cmath>
#include <algorithm>

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/features2d.hpp>
#include <opencv2/calib3d.hpp>

#define HOMOGRAPHY_LIB_VERSION "1.0.0"

// Minimum number of matches required to compute homography
static const int MIN_MATCHES = 10;

// Lowe's ratio test threshold
static const float RATIO_THRESH = 0.75f;

// RANSAC reprojection threshold
static const double RANSAC_THRESH = 5.0;

/**
 * Internal function to compute homography from two grayscale images
 */
static HomographyResult compute_homography_internal(
    const cv::Mat &anchor_gray,
    const cv::Mat &scene_gray)
{
    HomographyResult result = {};

    // Create ORB detector (fast, free, works well on mobile)
    auto detector = cv::ORB::create(
        1000, // nfeatures - max number of features
        1.2f, // scaleFactor
        8,    // nlevels
        31,   // edgeThreshold
        0,    // firstLevel
        2,    // WTA_K
        cv::ORB::HARRIS_SCORE,
        31, // patchSize
        20  // fastThreshold
    );

    // Detect keypoints and compute descriptors
    std::vector<cv::KeyPoint> kp_anchor, kp_scene;
    cv::Mat desc_anchor, desc_scene;

    detector->detectAndCompute(anchor_gray, cv::noArray(), kp_anchor, desc_anchor);
    detector->detectAndCompute(scene_gray, cv::noArray(), kp_scene, desc_scene);

    // Check if we have enough keypoints
    if (kp_anchor.size() < 4 || kp_scene.size() < 4)
    {
        result.status = 0;
        return result;
    }

    if (desc_anchor.empty() || desc_scene.empty())
    {
        result.status = 0;
        return result;
    }

    // Match descriptors using BFMatcher with Hamming distance (for ORB)
    cv::BFMatcher matcher(cv::NORM_HAMMING);
    std::vector<std::vector<cv::DMatch>> knn_matches;
    matcher.knnMatch(desc_anchor, desc_scene, knn_matches, 2);

    // Apply Lowe's ratio test
    std::vector<cv::DMatch> good_matches;
    for (const auto &m : knn_matches)
    {
        if (m.size() == 2 && m[0].distance < RATIO_THRESH * m[1].distance)
        {
            good_matches.push_back(m[0]);
        }
    }

    result.num_matches = static_cast<int>(good_matches.size());

    // Check if we have enough good matches
    if (good_matches.size() < MIN_MATCHES)
    {
        result.status = 0;
        return result;
    }

    // Extract matched points
    std::vector<cv::Point2f> pts_anchor, pts_scene;
    for (const auto &m : good_matches)
    {
        pts_anchor.push_back(kp_anchor[m.queryIdx].pt);
        pts_scene.push_back(kp_scene[m.trainIdx].pt);
    }

    // Compute homography using RANSAC
    std::vector<char> inliers_mask;
    cv::Mat H = cv::findHomography(pts_anchor, pts_scene, cv::RANSAC, RANSAC_THRESH, inliers_mask);

    // Check if homography was found
    if (H.empty() || H.rows != 3 || H.cols != 3)
    {
        result.status = 0;
        return result;
    }

    // Count inliers
    int num_inliers = 0;
    for (char inlier : inliers_mask)
    {
        if (inlier)
            num_inliers++;
    }

    // Verify homography quality (at least 50% inliers)
    if (num_inliers < MIN_MATCHES || num_inliers < good_matches.size() * 0.3)
    {
        result.status = 0;
        return result;
    }

    // Copy homography matrix to result
    for (int i = 0; i < 3; i++)
    {
        for (int j = 0; j < 3; j++)
        {
            result.homography[i * 3 + j] = H.at<double>(i, j);
        }
    }

    // Transform anchor corners to scene coordinates
    std::vector<cv::Point2f> anchor_corners = {
        {0, 0},
        {static_cast<float>(anchor_gray.cols), 0},
        {static_cast<float>(anchor_gray.cols), static_cast<float>(anchor_gray.rows)},
        {0, static_cast<float>(anchor_gray.rows)}};

    std::vector<cv::Point2f> scene_corners;
    cv::perspectiveTransform(anchor_corners, scene_corners, H);

    // Store corners in result
    for (int i = 0; i < 4; i++)
    {
        result.corners[i * 2] = scene_corners[i].x;
        result.corners[i * 2 + 1] = scene_corners[i].y;
    }

    // Compute center (average of corners)
    result.center_x = 0;
    result.center_y = 0;
    for (const auto &corner : scene_corners)
    {
        result.center_x += corner.x;
        result.center_y += corner.y;
    }
    result.center_x /= 4.0f;
    result.center_y /= 4.0f;

    // Compute rotation angle from top edge
    float dx = scene_corners[1].x - scene_corners[0].x;
    float dy = scene_corners[1].y - scene_corners[0].y;
    result.rotation = std::atan2(dy, dx);

    // Compute scale (average of top and left edge ratios)
    float top_edge = std::sqrt(dx * dx + dy * dy);
    float left_dx = scene_corners[3].x - scene_corners[0].x;
    float left_dy = scene_corners[3].y - scene_corners[0].y;
    float left_edge = std::sqrt(left_dx * left_dx + left_dy * left_dy);

    float original_width = static_cast<float>(anchor_gray.cols);
    float original_height = static_cast<float>(anchor_gray.rows);

    result.scale = (top_edge / original_width + left_edge / original_height) / 2.0f;

    // Validate the detected quadrilateral (should be convex and not too distorted)
    // Check if corners form a valid quadrilateral
    auto cross_product = [](const cv::Point2f &o, const cv::Point2f &a, const cv::Point2f &b)
    {
        return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    };

    // All cross products should have the same sign for a convex polygon
    float cp1 = cross_product(scene_corners[0], scene_corners[1], scene_corners[2]);
    float cp2 = cross_product(scene_corners[1], scene_corners[2], scene_corners[3]);
    float cp3 = cross_product(scene_corners[2], scene_corners[3], scene_corners[0]);
    float cp4 = cross_product(scene_corners[3], scene_corners[0], scene_corners[1]);

    bool is_convex = (cp1 > 0 && cp2 > 0 && cp3 > 0 && cp4 > 0) ||
                     (cp1 < 0 && cp2 < 0 && cp3 < 0 && cp4 < 0);

    if (!is_convex)
    {
        result.status = 0;
        return result;
    }

    // Check aspect ratio distortion (should not be too extreme)
    float aspect_ratio = top_edge / left_edge;
    float original_aspect = original_width / original_height;
    float aspect_distortion = aspect_ratio / original_aspect;

    if (aspect_distortion < 0.3f || aspect_distortion > 3.0f)
    {
        result.status = 0;
        return result;
    }

    result.num_matches = num_inliers;
    result.status = 1;
    return result;
}

extern "C"
{

    HomographyResult hg_find_homography(
        const uint8_t *anchor_bytes, size_t anchor_size,
        const uint8_t *scene_bytes, size_t scene_size)
    {
        HomographyResult result = {};

        // Validate input
        if (anchor_bytes == nullptr || scene_bytes == nullptr)
        {
            result.status = -1;
            return result;
        }

        if (anchor_size == 0 || scene_size == 0)
        {
            result.status = -1;
            return result;
        }

        // Decode anchor image
        std::vector<uint8_t> anchor_vec(anchor_bytes, anchor_bytes + anchor_size);
        cv::Mat anchor = cv::imdecode(anchor_vec, cv::IMREAD_GRAYSCALE);

        if (anchor.empty())
        {
            result.status = -2;
            return result;
        }

        // Decode scene image
        std::vector<uint8_t> scene_vec(scene_bytes, scene_bytes + scene_size);
        cv::Mat scene = cv::imdecode(scene_vec, cv::IMREAD_GRAYSCALE);

        if (scene.empty())
        {
            result.status = -3;
            return result;
        }

        return compute_homography_internal(anchor, scene);
    }

    HomographyResult hg_find_homography_raw(
        const uint8_t *anchor_data, int anchor_width, int anchor_height, int anchor_channels,
        const uint8_t *scene_data, int scene_width, int scene_height, int scene_channels)
    {
        HomographyResult result = {};

        // Validate input
        if (anchor_data == nullptr || scene_data == nullptr)
        {
            result.status = -1;
            return result;
        }

        if (anchor_width <= 0 || anchor_height <= 0 ||
            scene_width <= 0 || scene_height <= 0)
        {
            result.status = -1;
            return result;
        }

        if (anchor_channels != 1 && anchor_channels != 3 && anchor_channels != 4)
        {
            result.status = -1;
            return result;
        }

        if (scene_channels != 1 && scene_channels != 3 && scene_channels != 4)
        {
            result.status = -1;
            return result;
        }

        // Create cv::Mat from raw data
        int anchor_type = anchor_channels == 1 ? CV_8UC1 : anchor_channels == 3 ? CV_8UC3
                                                                                : CV_8UC4;
        int scene_type = scene_channels == 1 ? CV_8UC1 : scene_channels == 3 ? CV_8UC3
                                                                             : CV_8UC4;

        cv::Mat anchor(anchor_height, anchor_width, anchor_type, const_cast<uint8_t *>(anchor_data));
        cv::Mat scene(scene_height, scene_width, scene_type, const_cast<uint8_t *>(scene_data));

        // Convert to grayscale
        cv::Mat anchor_gray, scene_gray;

        if (anchor_channels == 1)
        {
            anchor_gray = anchor;
        }
        else if (anchor_channels == 3)
        {
            cv::cvtColor(anchor, anchor_gray, cv::COLOR_RGB2GRAY);
        }
        else
        {
            cv::cvtColor(anchor, anchor_gray, cv::COLOR_RGBA2GRAY);
        }

        if (scene_channels == 1)
        {
            scene_gray = scene;
        }
        else if (scene_channels == 3)
        {
            cv::cvtColor(scene, scene_gray, cv::COLOR_RGB2GRAY);
        }
        else
        {
            cv::cvtColor(scene, scene_gray, cv::COLOR_RGBA2GRAY);
        }

        return compute_homography_internal(anchor_gray, scene_gray);
    }

    HomographyResult hg_find_homography_from_points(
        const float *pts0_x, const float *pts0_y,
        const float *pts1_x, const float *pts1_y,
        int num_points,
        int anchor_width, int anchor_height)
    {
        HomographyResult result = {};

        // Validate input
        if (pts0_x == nullptr || pts0_y == nullptr ||
            pts1_x == nullptr || pts1_y == nullptr)
        {
            result.status = -1;
            return result;
        }

        if (num_points < 4)
        {
            result.status = 0;
            result.num_matches = num_points;
            return result;
        }

        if (anchor_width <= 0 || anchor_height <= 0)
        {
            result.status = -1;
            return result;
        }

        // Convert to OpenCV point vectors
        std::vector<cv::Point2f> pts_anchor, pts_scene;
        pts_anchor.reserve(num_points);
        pts_scene.reserve(num_points);

        for (int i = 0; i < num_points; i++)
        {
            pts_anchor.push_back(cv::Point2f(pts0_x[i], pts0_y[i]));
            pts_scene.push_back(cv::Point2f(pts1_x[i], pts1_y[i]));
        }

        result.num_matches = num_points;

        // Compute homography using RANSAC
        std::vector<char> inliers_mask;
        cv::Mat H = cv::findHomography(pts_anchor, pts_scene, cv::RANSAC, RANSAC_THRESH, inliers_mask);

        // Check if homography was found
        if (H.empty() || H.rows != 3 || H.cols != 3)
        {
            result.status = 0;
            return result;
        }

        // Count inliers
        int num_inliers = 0;
        for (char inlier : inliers_mask)
        {
            if (inlier)
                num_inliers++;
        }

        // Verify homography quality
        if (num_inliers < MIN_MATCHES || num_inliers < num_points * 0.3)
        {
            result.status = 0;
            return result;
        }

        // Copy homography matrix to result
        for (int i = 0; i < 3; i++)
        {
            for (int j = 0; j < 3; j++)
            {
                result.homography[i * 3 + j] = H.at<double>(i, j);
            }
        }

        // Transform anchor corners to scene coordinates
        std::vector<cv::Point2f> anchor_corners = {
            {0, 0},
            {static_cast<float>(anchor_width), 0},
            {static_cast<float>(anchor_width), static_cast<float>(anchor_height)},
            {0, static_cast<float>(anchor_height)}};

        std::vector<cv::Point2f> scene_corners;
        cv::perspectiveTransform(anchor_corners, scene_corners, H);

        // Store corners in result
        for (int i = 0; i < 4; i++)
        {
            result.corners[i * 2] = scene_corners[i].x;
            result.corners[i * 2 + 1] = scene_corners[i].y;
        }

        // Compute center (average of corners)
        result.center_x = 0;
        result.center_y = 0;
        for (const auto &corner : scene_corners)
        {
            result.center_x += corner.x;
            result.center_y += corner.y;
        }
        result.center_x /= 4.0f;
        result.center_y /= 4.0f;

        // Compute rotation angle from top edge
        float dx = scene_corners[1].x - scene_corners[0].x;
        float dy = scene_corners[1].y - scene_corners[0].y;
        result.rotation = std::atan2(dy, dx);

        // Compute scale (average of top and left edge ratios)
        float top_edge = std::sqrt(dx * dx + dy * dy);
        float left_dx = scene_corners[3].x - scene_corners[0].x;
        float left_dy = scene_corners[3].y - scene_corners[0].y;
        float left_edge = std::sqrt(left_dx * left_dx + left_dy * left_dy);

        float original_width = static_cast<float>(anchor_width);
        float original_height = static_cast<float>(anchor_height);

        result.scale = (top_edge / original_width + left_edge / original_height) / 2.0f;

        // Validate the detected quadrilateral (should be convex)
        auto cross_product = [](const cv::Point2f &o, const cv::Point2f &a, const cv::Point2f &b)
        {
            return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
        };

        float cp1 = cross_product(scene_corners[0], scene_corners[1], scene_corners[2]);
        float cp2 = cross_product(scene_corners[1], scene_corners[2], scene_corners[3]);
        float cp3 = cross_product(scene_corners[2], scene_corners[3], scene_corners[0]);
        float cp4 = cross_product(scene_corners[3], scene_corners[0], scene_corners[1]);

        bool is_convex = (cp1 > 0 && cp2 > 0 && cp3 > 0 && cp4 > 0) ||
                         (cp1 < 0 && cp2 < 0 && cp3 < 0 && cp4 < 0);

        if (!is_convex)
        {
            result.status = 0;
            return result;
        }

        // Check aspect ratio distortion
        float aspect_ratio = top_edge / left_edge;
        float original_aspect = original_width / original_height;
        float aspect_distortion = aspect_ratio / original_aspect;

        if (aspect_distortion < 0.3f || aspect_distortion > 3.0f)
        {
            result.status = 0;
            return result;
        }

        result.num_matches = num_inliers;
        result.status = 1;
        return result;
    }

    const char *hg_lib_version(void)
    {
        return HOMOGRAPHY_LIB_VERSION;
    }

    // ============================================================================
    // Paper Detection Implementation
    // ============================================================================

    /**
     * Order points in clockwise order starting from top-left
     */
    static std::vector<cv::Point2f> order_points_clockwise(const std::vector<cv::Point2f> &pts)
    {
        if (pts.size() != 4)
            return pts;

        std::vector<cv::Point2f> ordered(4);

        // Sum of coordinates: top-left has smallest sum, bottom-right has largest
        // Difference: top-right has smallest diff, bottom-left has largest
        std::vector<float> sums(4), diffs(4);
        for (int i = 0; i < 4; i++)
        {
            sums[i] = pts[i].x + pts[i].y;
            diffs[i] = pts[i].y - pts[i].x;
        }

        auto min_sum_it = std::min_element(sums.begin(), sums.end());
        auto max_sum_it = std::max_element(sums.begin(), sums.end());
        auto min_diff_it = std::min_element(diffs.begin(), diffs.end());
        auto max_diff_it = std::max_element(diffs.begin(), diffs.end());

        ordered[0] = pts[min_sum_it - sums.begin()];   // top-left
        ordered[1] = pts[min_diff_it - diffs.begin()]; // top-right
        ordered[2] = pts[max_sum_it - sums.begin()];   // bottom-right
        ordered[3] = pts[max_diff_it - diffs.begin()]; // bottom-left

        return ordered;
    }

    /**
     * Check if a quadrilateral is convex
     */
    static bool is_convex_quadrilateral(const std::vector<cv::Point2f> &pts)
    {
        if (pts.size() != 4)
            return false;

        auto cross_product = [](const cv::Point2f &o, const cv::Point2f &a, const cv::Point2f &b)
        {
            return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
        };

        float cp1 = cross_product(pts[0], pts[1], pts[2]);
        float cp2 = cross_product(pts[1], pts[2], pts[3]);
        float cp3 = cross_product(pts[2], pts[3], pts[0]);
        float cp4 = cross_product(pts[3], pts[0], pts[1]);

        return (cp1 > 0 && cp2 > 0 && cp3 > 0 && cp4 > 0) ||
               (cp1 < 0 && cp2 < 0 && cp3 < 0 && cp4 < 0);
    }

    /**
     * Compute edge length
     */
    static float edge_length(const cv::Point2f &p1, const cv::Point2f &p2)
    {
        float dx = p2.x - p1.x;
        float dy = p2.y - p1.y;
        return std::sqrt(dx * dx + dy * dy);
    }

    /**
     * Internal function to detect paper in grayscale image
     */
    static PaperDetectionResult detect_paper_internal(
        const cv::Mat &gray,
        const PaperDetectionConfig *config)
    {
        PaperDetectionResult result = {};

        // Use default config if not provided
        PaperDetectionConfig cfg;
        if (config != nullptr)
        {
            cfg = *config;
        }
        else
        {
            cfg.canny_threshold1 = 50;
            cfg.canny_threshold2 = 150;
            cfg.blur_kernel_size = 5;
            cfg.min_area_ratio = 0.05f;
            cfg.max_area_ratio = 0.95f;
            cfg.expected_aspect_ratio = 210.0f / 297.0f; // A4
            cfg.aspect_ratio_tolerance = 0.3f;
            cfg.paper_width_mm = 210.0f;
            cfg.paper_height_mm = 297.0f;
            cfg.focal_length = 0; // Skip pose estimation
            cfg.cx = 0;
            cfg.cy = 0;
        }

        float image_area = static_cast<float>(gray.cols * gray.rows);
        float min_area = image_area * cfg.min_area_ratio;
        float max_area = image_area * cfg.max_area_ratio;

        // Apply Gaussian blur to reduce noise
        cv::Mat blurred;
        if (cfg.blur_kernel_size > 0 && cfg.blur_kernel_size % 2 == 1)
        {
            cv::GaussianBlur(gray, blurred, cv::Size(cfg.blur_kernel_size, cfg.blur_kernel_size), 0);
        }
        else
        {
            blurred = gray;
        }

        // Apply Canny edge detection
        cv::Mat edges;
        cv::Canny(blurred, edges, cfg.canny_threshold1, cfg.canny_threshold2);

        // Dilate edges to close gaps
        cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));
        cv::dilate(edges, edges, kernel);

        // Find contours
        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(edges, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        if (contours.empty())
        {
            result.status = 0;
            return result;
        }

        // Find the best quadrilateral contour
        std::vector<cv::Point2f> best_quad;
        float best_score = -1.0f;
        float best_area = 0;

        // Minimum edge length in pixels (to filter out noise)
        float min_edge_length = std::min(gray.cols, gray.rows) * 0.05f; // At least 5% of smaller dimension
        
        for (const auto &contour : contours)
        {
            float area = static_cast<float>(cv::contourArea(contour));

            // Filter by area
            if (area < min_area || area > max_area)
                continue;

            // Approximate the contour to a polygon
            // Use larger epsilon (0.03-0.04) for more aggressive simplification
            float peri = static_cast<float>(cv::arcLength(contour, true));
            std::vector<cv::Point> approx;
            cv::approxPolyDP(contour, approx, 0.035 * peri, true);

            // We need exactly 4 points (quadrilateral)
            if (approx.size() != 4)
                continue;

            // Convert to Point2f
            std::vector<cv::Point2f> quad;
            for (const auto &p : approx)
            {
                quad.push_back(cv::Point2f(static_cast<float>(p.x), static_cast<float>(p.y)));
            }

            // Order points clockwise
            quad = order_points_clockwise(quad);

            // Check if convex
            if (!is_convex_quadrilateral(quad))
                continue;

            // Compute edge lengths
            float edge0 = edge_length(quad[0], quad[1]); // top
            float edge1 = edge_length(quad[1], quad[2]); // right
            float edge2 = edge_length(quad[2], quad[3]); // bottom
            float edge3 = edge_length(quad[3], quad[0]); // left
            
            // Check minimum edge length (filter out small noise contours)
            float min_edge = std::min({edge0, edge1, edge2, edge3});
            if (min_edge < min_edge_length)
                continue;
            
            // Compute aspect ratio (width / height)
            float width = (edge0 + edge2) / 2.0f;
            float height = (edge1 + edge3) / 2.0f;

            // Ensure width < height for portrait orientation
            float aspect_ratio = std::min(width, height) / std::max(width, height);

            // Check aspect ratio if expected ratio is provided
            if (cfg.expected_aspect_ratio > 0)
            {
                float ratio_diff = std::abs(aspect_ratio - cfg.expected_aspect_ratio) / cfg.expected_aspect_ratio;
                if (ratio_diff > cfg.aspect_ratio_tolerance)
                    continue;
            }

            // Score: prefer larger area with better aspect ratio match
            float aspect_score = 1.0f;
            if (cfg.expected_aspect_ratio > 0)
            {
                float ratio_diff = std::abs(aspect_ratio - cfg.expected_aspect_ratio) / cfg.expected_aspect_ratio;
                aspect_score = 1.0f - ratio_diff;
            }

            float score = area * aspect_score;

            if (score > best_score)
            {
                best_score = score;
                best_quad = quad;
                best_area = area;
            }
        }

        if (best_quad.empty())
        {
            result.status = 0;
            return result;
        }

        // Store corners
        for (int i = 0; i < 4; i++)
        {
            result.corners[i * 2] = best_quad[i].x;
            result.corners[i * 2 + 1] = best_quad[i].y;
        }

        // Compute center
        result.center_x = 0;
        result.center_y = 0;
        for (const auto &p : best_quad)
        {
            result.center_x += p.x;
            result.center_y += p.y;
        }
        result.center_x /= 4.0f;
        result.center_y /= 4.0f;

        // Compute area and perimeter
        result.area = best_area;
        result.perimeter = 0;
        for (int i = 0; i < 4; i++)
        {
            result.perimeter += edge_length(best_quad[i], best_quad[(i + 1) % 4]);
        }

        // Compute aspect ratio
        float width = (edge_length(best_quad[0], best_quad[1]) + edge_length(best_quad[3], best_quad[2])) / 2.0f;
        float height = (edge_length(best_quad[0], best_quad[3]) + edge_length(best_quad[1], best_quad[2])) / 2.0f;
        result.aspect_ratio = std::min(width, height) / std::max(width, height);

        // Compute homography from canonical rectangle to detected quad
        // Canonical rectangle: [0,0], [paper_width, 0], [paper_width, paper_height], [0, paper_height]
        float paper_w = (cfg.paper_width_mm > 0) ? cfg.paper_width_mm : 210.0f;
        float paper_h = (cfg.paper_height_mm > 0) ? cfg.paper_height_mm : 297.0f;

        // Determine orientation: if detected quad is more wide than tall, swap dimensions
        if (width > height)
        {
            std::swap(paper_w, paper_h);
        }

        std::vector<cv::Point2f> canonical_corners = {
            {0, 0},
            {paper_w, 0},
            {paper_w, paper_h},
            {0, paper_h}};

        cv::Mat H = cv::findHomography(canonical_corners, best_quad);

        if (!H.empty() && H.rows == 3 && H.cols == 3)
        {
            for (int i = 0; i < 3; i++)
            {
                for (int j = 0; j < 3; j++)
                {
                    result.homography[i * 3 + j] = H.at<double>(i, j);
                }
            }
        }

        // Compute camera pose if intrinsics are provided
        if (cfg.focal_length > 0)
        {
            // Camera matrix
            cv::Mat camera_matrix = (cv::Mat_<double>(3, 3) << cfg.focal_length, 0, cfg.cx > 0 ? cfg.cx : gray.cols / 2.0,
                                     0, cfg.focal_length, cfg.cy > 0 ? cfg.cy : gray.rows / 2.0,
                                     0, 0, 1);

            // No distortion
            cv::Mat dist_coeffs = cv::Mat::zeros(4, 1, CV_64F);

            // 3D object points (paper corners in paper coordinate system, Z=0)
            std::vector<cv::Point3f> object_points = {
                {0, 0, 0},
                {paper_w, 0, 0},
                {paper_w, paper_h, 0},
                {0, paper_h, 0}};

            cv::Mat rvec, tvec;
            bool solved = cv::solvePnP(object_points, best_quad, camera_matrix, dist_coeffs, rvec, tvec);

            if (solved)
            {
                result.rvec[0] = rvec.at<double>(0);
                result.rvec[1] = rvec.at<double>(1);
                result.rvec[2] = rvec.at<double>(2);
                result.tvec[0] = tvec.at<double>(0);
                result.tvec[1] = tvec.at<double>(1);
                result.tvec[2] = tvec.at<double>(2);
            }
        }

        result.status = 1;
        return result;
    }

    PaperDetectionResult hg_detect_paper(
        const uint8_t *image_data, int image_width, int image_height, int image_channels,
        const PaperDetectionConfig *config)
    {
        PaperDetectionResult result = {};

        // Validate input
        if (image_data == nullptr)
        {
            result.status = -1;
            return result;
        }

        if (image_width <= 0 || image_height <= 0)
        {
            result.status = -1;
            return result;
        }

        if (image_channels != 1 && image_channels != 3 && image_channels != 4)
        {
            result.status = -1;
            return result;
        }

        // Create cv::Mat from raw data
        int cv_type = image_channels == 1 ? CV_8UC1 : image_channels == 3 ? CV_8UC3
                                                                          : CV_8UC4;

        cv::Mat image(image_height, image_width, cv_type, const_cast<uint8_t *>(image_data));

        // Convert to grayscale
        cv::Mat gray;
        if (image_channels == 1)
        {
            gray = image;
        }
        else if (image_channels == 3)
        {
            cv::cvtColor(image, gray, cv::COLOR_RGB2GRAY);
        }
        else
        {
            cv::cvtColor(image, gray, cv::COLOR_RGBA2GRAY);
        }

        return detect_paper_internal(gray, config);
    }

    PaperDetectionResult hg_detect_paper_encoded(
        const uint8_t *image_bytes, size_t image_size,
        const PaperDetectionConfig *config)
    {
        PaperDetectionResult result = {};

        // Validate input
        if (image_bytes == nullptr || image_size == 0)
        {
            result.status = -1;
            return result;
        }

        // Decode image
        std::vector<uint8_t> image_vec(image_bytes, image_bytes + image_size);
        cv::Mat gray = cv::imdecode(image_vec, cv::IMREAD_GRAYSCALE);

        if (gray.empty())
        {
            result.status = -1;
            return result;
        }

        return detect_paper_internal(gray, config);
    }

    PaperDetectionConfig hg_default_paper_config(void)
    {
        PaperDetectionConfig config = {};
        config.canny_threshold1 = 50;
        config.canny_threshold2 = 150;
        config.blur_kernel_size = 5;
        config.min_area_ratio = 0.05f;
        config.max_area_ratio = 0.95f;
        config.expected_aspect_ratio = 210.0f / 297.0f; // A4
        config.aspect_ratio_tolerance = 0.3f;
        config.paper_width_mm = 210.0f;
        config.paper_height_mm = 297.0f;
        config.focal_length = 0; // Skip pose estimation by default
        config.cx = 0;
        config.cy = 0;
        return config;
    }

} // extern "C"
