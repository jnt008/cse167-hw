import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  StructuredBuffer<float2> polyline,
                  uniform int num_polyline,
                  uniform bool is_closed,
                  uniform bool use_fill_color,
                  uniform float3 fill_color,
                  uniform bool use_stroke_color,
                  uniform float3 stroke_color,
                  uniform float stroke_width,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(0.5, 0.5, 0.5, 1.0);

    float2 pixel = float2(tid.x, height - 1 - tid.y);

//FILL CODE -----------------------------------------------
    int winding = 0;

    if (is_closed && use_fill_color) {
        for (int i = 0; i < num_polyline; i++) {

            //finds the next point (% helps us wrap back to the first point)
            int j = (i + 1) % num_polyline;

            float2 a = polyline[i];
            float2 b = polyline[j];

            //checks if the ray from the pixel goes through ab line
            bool crossesY = (a.y > pixel.y) != (b.y > pixel.y);

            if (crossesY) {

                //calculate the percentage of the line ab that the pixel sits on
                float t = (pixel.y - a.y) / (b.y - a.y);

                //calculate the intersection's x coordinate
                float intersectionX = a.x + t * (b.x - a.x);

                //only count intersections to the right of the pixel
                if (pixel.x < intersectionX) {

                    //edge is going upward
                    if (b.y > a.y) {
                        winding++;
                    }
                    //edge is going downward
                    else {
                        winding--;
                    }
                }
            }
        }

        //non-zero winding means the pixel is inside the shape
        if (winding != 0) {
            image[tid] = float4(fill_color, 1.0);
        }
    }

    // STROKE CODE -----------------------------------------------------

    //closed shape has an extra edge from the last point back to the first point
    int num_edges = is_closed ? num_polyline : num_polyline - 1;

    //for each point
    for (int i = 0; i < num_edges; i++) {

        //finds the next point (% helps us wrap back to the first point)
        int j = (i + 1) % num_polyline;

        //first point
        float2 a = polyline[i];

        //second point
        float2 b = polyline[j];

        //vector from a to b
        float2 ab = b - a;

        //direction from a to the pixel
        float2 ap = pixel - a;

        //the percentage/fraction of the way from point A to point B where the closest point to the pixel is located
        float t = dot(ap, ab) / dot(ab, ab);

        // save t before clamping it
        float unclamped_t = t;

        //if t is less than 0 or greater than 1, then the closest point is outside of the line segment
        t = clamp(t, 0.0, 1.0);

        //the point on line ab that is closest to pixel
        float2 closest = a + t * ab;

        float distance = length(pixel - closest);

        // check if pixel is within the stroke width
        bool in_stroke = distance <= stroke_width / 2.0;

        // make the beginning of an open polyline have a flat cap
        if (!is_closed && i == 0 && unclamped_t < 0.0) {
            in_stroke = false;
        }

        // make the end of an open polyline have a flat cap
        if (!is_closed && i == num_edges - 1 && unclamped_t > 1.0) {
            in_stroke = false;
        }
        
        if (use_stroke_color && in_stroke) {
            image[tid] = float4(stroke_color, 1.0);
        }
    }
}