import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int /*samples_per_axis*/, // ignore for now
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Circle> circles,
                  StructuredBuffer<Polyline> polylines,
                  StructuredBuffer<QuadraticBezier> /*quadratic_beziers*/, // ignore for now
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(background, 1.0);

    float2 pixel = float2(tid.x + 0.5, height - tid.y - 0.5); 

    for (int s = 0; s < num_shapes; s++) {
	Shape shape = shapes[s]; 
	
	if (shape.type == ShapeType.Circle) {
		Circle circle = circles[shape.index]; 

		float distance = length(pixel - circle.center); 
		
		if (shape.use_fill && distance <= circle.radius) {
			image[tid] = shape.fill_rgba; 
		}
		if (shape.use_stroke && 
			abs(distance - circle.radius) <= shape.stroke_width / 2.0) {
			image[tid] = shape.stroke_rgba; 
		}
	}
	else if (shape.type == ShapeType.Polyline) {
		Polyline poly = polylines[shape.index]; 

		int num_points = poly.pts_end - poly.pts_begin; 
		int num_edges = poly.closed ? num_points : num_points - 1; 
		
		int winding = 0; 

		if (poly.closed && shape.use_fill) {
			for (int i = 0; i < num_points; i++) {
				int j = (i + 1) % num_points; 

				float2 a = points[poly.pts_begin + i]; 
				float2 b = points[poly.pts_begin + j]; 
				
				bool crossesY = (a.y > pixel.y) != (b.y > pixel.y);

				if (crossesY) {
    					float t = (pixel.y - a.y) / (b.y - a.y);
					float intersectionX = a.x + t * (b.x - a.x);

    					if (pixel.x < intersectionX) {
        					if (b.y > a.y) {
            						winding++;
        					} else {
            						winding--;
        					}
    					}
				}
			}
			if (winding != 0) {
				image[tid] = shape.fill_rgba; 			
			}
		}
		if (shape.use_stroke) {
			for (int i = 0; i < num_edges; i++) {
				int j = (i + 1) % num_points; 
				float2 a = points[poly.pts_begin + i]; 
				float2 b = points[poly.pts_begin + j]; 

				float2 ab = b - a; 
				float2 ap = pixel - a; 

				float denom = dot(ab, ab); 
				
				if (denom <= 0.0) {
					continue; 
				}
				float t = dot(ap, ab) / denom;
        			float unclamped_t = t;

        			t = clamp(t, 0.0, 1.0);

        			float2 closest = a + t * ab;
        			float distance = length(pixel - closest);

        			bool in_stroke = distance <= shape.stroke_width / 2.0;

        			if (!poly.closed && i == 0 && unclamped_t < 0.0) {
            				in_stroke = false;
        			}

        			if (!poly.closed && i == num_edges - 1 && unclamped_t > 1.0) {
            				in_stroke = false;
        			}

        			if (in_stroke) {
            				image[tid] = shape.stroke_rgba;
        			}
    			}	

		}
	}
	
    }
}
