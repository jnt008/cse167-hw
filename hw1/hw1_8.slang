
import hw1_common;

float4 alphaBlend(float4 foreground, float4 background) {
    float alpha = foreground.a;

    float3 color = alpha * foreground.rgb
        + (1.0 - alpha) * background.rgb;

    return float4(color, 1.0);
}

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
        uniform float3 background,
        uniform int samples_per_axis,
        StructuredBuffer<Shape> shapes,
        uniform int num_shapes,
        StructuredBuffer<Circle> circles,
        StructuredBuffer<Polyline> polylines,
        StructuredBuffer<QuadraticBezier> quadratic_beziers,
        StructuredBuffer<float2> points,
        RWTexture2D<float4> image) {

    uint width, height;
    image.GetDimensions(width, height);

    if (tid.x >= width || tid.y >= height) {
        return;
    }

    float4 total_color = float4(0.0);

    for (int sy = 0; sy < samples_per_axis; sy++) {
        for (int sx = 0; sx < samples_per_axis; sx++) {

            float2 pixel = float2(
                    tid.x + (sx + 0.5) / samples_per_axis,
                    height - tid.y - (sy + 0.5) / samples_per_axis
                    );

            float4 sample_color = float4(background, 1.0);

            // Process shapes from back to front
            for (int s = num_shapes - 1; s >= 0; s--) {
                Shape shape = shapes[s];

                float3 object_pos = mul(
                        shape.world_to_obj,
                        float3(pixel, 1.0)
                        );

                float2 object_pixel = object_pos.xy;

                if (shape.type == ShapeType.Circle) {
                    Circle circle = circles[shape.index];

                    float distance = length(
                            object_pixel - circle.center
                            );

                    // Circle fill
                    if (shape.use_fill &&
                            distance <= circle.radius) {

                        sample_color = alphaBlend(
                                shape.fill_rgba,
                                sample_color
                                );
                    }

                    // Circle stroke
                    if (shape.use_stroke &&
                            abs(distance - circle.radius) <=
                            shape.stroke_width / 2.0) {

                        sample_color = alphaBlend(
                                shape.stroke_rgba,
                                sample_color
                                );
                    }
                }

                else if (shape.type == ShapeType.Polyline) {
                    Polyline poly = polylines[shape.index];

                    int num_points = poly.pts_end - poly.pts_begin;
                    int num_edges; 
                    if (poly.closed) {
                        num_edges = num_points; 
                    } else {
                        num_edges = num_points - 1; 
                    }

                    int winding = 0;

                    // Polyline fill
                    if (poly.closed && shape.use_fill) {
                        for (int i = 0; i < num_points; i++) {
                            int j = (i + 1) % num_points;

                            float2 a = points[poly.pts_begin + i];
                            float2 b = points[poly.pts_begin + j];

                            bool crossesY =
                                (a.y > object_pixel.y) !=
                                (b.y > object_pixel.y);

                            if (crossesY) {
                                float t =
                                    (object_pixel.y - a.y) /
                                    (b.y - a.y);

                                float intersectionX =
                                    a.x + t * (b.x - a.x);

                                if (object_pixel.x < intersectionX) {
                                    if (b.y > a.y) {
                                        winding++;
                                    } else {
                                        winding--;
                                    }
                                }
                            }
                        }

                        if (winding != 0) {
                            sample_color = alphaBlend(
                                    shape.fill_rgba,
                                    sample_color
                                    );
                        }
                    }

                    // Polyline stroke
                    if (shape.use_stroke) {
                        bool in_any_stroke = false;

                        for (int i = 0; i < num_edges; i++) {
                            int j = (i + 1) % num_points;

                            float2 a = points[poly.pts_begin + i];
                            float2 b = points[poly.pts_begin + j];

                            float2 ab = b - a;
                            float2 ap = object_pixel - a;

                            float denom = dot(ab, ab);

                            if (denom <= 0.0) {
                                continue;
                            }

                            float t = dot(ap, ab) / denom;
                            float unclamped_t = t;

                            t = clamp(t, 0.0, 1.0);

                            float2 closest = a + t * ab;
                            float distance = length(
                                    object_pixel - closest
                                    );

                            bool in_stroke =
                                distance <= shape.stroke_width / 2.0;

                            if (!poly.closed &&
                                    i == 0 &&
                                    unclamped_t < 0.0) {
                                in_stroke = false;
                            }

                            if (!poly.closed &&
                                    i == num_edges - 1 &&
                                    unclamped_t > 1.0) {
                                in_stroke = false;
                            }

                            if (in_stroke) {
                                in_any_stroke = true;
                            }
                        }

                        // Blend stroke only once per shape
                        if (in_any_stroke) {
                            sample_color = alphaBlend(
                                    shape.stroke_rgba,
                                    sample_color
                            );
                        }
                    }
                    }
                    // Get the Bezier curve and its control points
                    else if (shape.type == ShapeType.QuadraticBezier) {
                        QuadraticBezier bezier = quadratic_beziers[shape.index]; 

                        int num_points = bezier.pts_end - bezier.pts_begin; 
                        int winding = 0; 

                        int num_segments; 
                        if (bezier.closed) {
                            num_segments = num_points / 2;     
                        } else {
                            num_segments = (num_points - 1) / 2; 
                        }

                        float min_distance = 1e20; 

                        // Go through each Bezier segment
                        for (int i = 0; i < num_segments; i++) {
                            int k = 2 * i; 
                            float2 p0 = points[bezier.pts_begin + k]; 
                            float2 p1 = points[bezier.pts_begin + k + 1]; 
                            float2 p2 = points[bezier.pts_begin + (k + 2) % num_points]; 

                            // Coefficients for the quadratic Bezier equation
                            float2 A = p0 - 2.0 * p1 + p2; 
                            float2 B = 2.0 * (p1 - p0); 
                            float2 C = p0; 

                            // Coefficients for finding the closest point on the Bezier curve
                            float2 D = C - object_pixel; 

                            float cubic_a = 2.0 * dot(A, A); 
                            float cubic_b = 3.0 * dot(A, B); 
                            float cubic_c = dot(B, B) + 2.0 * dot(D, A); 
                            float cubic_d = dot(D, B); 

                            float3 cubic_roots; 
                            int num_roots = solve_cubic(
                                cubic_a, cubic_b, cubic_c, cubic_d, cubic_roots
                            );

                            // Endpoints with flat caps on the ends of open curves
                            bool first_open = !bezier.closed && i == 0;
                            bool last_open = !bezier.closed && i == num_segments - 1;

                            bool use_start = !(first_open &&
                                dot(object_pixel - p0, B) < 0.0);
                            bool use_end = !(last_open &&
                                dot(object_pixel - p2, 2.0 * A + B) > 0.0);

                            if (use_start) {
                                min_distance = min(min_distance, length(p0 - object_pixel));
                            }
                            if (use_end) {
                                min_distance = min(min_distance, length(p2 - object_pixel));
                            }

                            for (int r = 0; r < num_roots; r++) {
                                float t = cubic_roots[r];

                                if (t >= 0.0 && t <= 1.0) {
                                    float2 curve_point = A * t * t + B * t + C;
                                    float distance = length(curve_point - object_pixel);
                                    min_distance = min(min_distance, distance);
                                }
                            }

                            // Where the curve crosses the pixel's horizontal line
                            float a = A.y; 
                            float b = B.y;
                            float c = C.y - object_pixel.y; 

                            float2 roots; 
                            bool has_roots = solve_quadratic(a, b, c, roots); 

                            if (has_roots) {
                                for (int r = 0; r < 2; r++) {
                                    float t = roots[r]; 

                                    if (t >= 0.0 && t <= 1.0) {
                                        float2 curve_point = A * t * t + B * t + C; 

                                        if (curve_point.x > object_pixel.x) {
                                            float derivative_y = 2.0 * A.y * t + B.y; 

                                            if (derivative_y > 0.0) {
                                                winding++; 
                                            } else if (derivative_y < 0.0) {
                                                winding--; 
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // Fill inside of the Bezier shape 
                        if (bezier.closed && shape.use_fill && winding != 0) {
                            sample_color = alphaBlend(
                                    shape.fill_rgba, 
                                    sample_color
                            ); 
                        }
                        // Draw the Bezier stroke
                        if (shape.use_stroke && min_distance <= shape.stroke_width / 2.0) {
                            sample_color = alphaBlend(
                                shape.stroke_rgba,
                                sample_color
                            );
                        }
                    
                }

            }
            total_color += sample_color; 
        }

    }
    image[tid] = total_color /
            float(samples_per_axis * samples_per_axis);
}
