shader_type canvas_item;

uniform sampler2D unlitTexture; // Texture for binary 0
uniform sampler2D litTexture; // Texture for binary 1
uniform sampler2D binaryDataTexture; // 2D texture for binary data

uniform sampler2D binaryDeadTexture;
uniform sampler2D deadzoneDataTexture;

uniform sampler2D greenDataTexture;

uniform int gridWidth;      // Number of cells horizontally and vertically

const int cellSize = 8;    // Cell size in pixels
const float fadeDistance = 32.0; // Distance from border where fading starts

void fragment() {
	vec2 totalGridSize = vec2(float(gridWidth) * float(cellSize));

	vec2 scaledUV = UV * float(gridWidth);

	ivec2 cellIndex = ivec2(floor(scaledUV));

	vec2 cellUV = fract(scaledUV);
	bool isInsideCell = all(greaterThanEqual(cellUV, vec2(0.0))) && all(lessThan(cellUV, vec2(1.0)));

	vec2 binaryDataUV = vec2(
		float(cellIndex.x) / float(gridWidth - 1),
		float(cellIndex.y) / float(gridWidth - 1)
	);

	float binaryValue = texture(binaryDataTexture, binaryDataUV).r;
	float binaryDead = texture(deadzoneDataTexture, binaryDataUV).r;
	float binaryGreen = texture(greenDataTexture, binaryDataUV).r;
	bool isWhite = binaryValue > 0.5;
	bool isDeadzone = binaryDead > 0.8;
	bool isGreen = binaryGreen > 0.6;

	float distanceX = min(scaledUV.x, float(gridWidth) - scaledUV.x) * float(cellSize);
	float distanceY = min(scaledUV.y, float(gridWidth) - scaledUV.y) * float(cellSize);
	float distanceToBorder = min(distanceX, distanceY);

	vec4 color = texture(unlitTexture, cellUV);
	vec4 dead_color = texture(binaryDeadTexture, cellUV);
	vec4 green_color = vec4(0,1.0,0,1.0);

	if(isWhite && isInsideCell){
		color = texture(litTexture, cellUV);
	}

	if(isDeadzone && isInsideCell){
		color = dead_color;
	}

	if(isGreen && isInsideCell && color.a == 0.0 ){
		color = green_color;
	}

	float alphaFactor = log(distanceToBorder) / log(fadeDistance);
	color.a *= alphaFactor;

	COLOR = color;
}