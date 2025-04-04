#version 450
#[compute]

const int gridWidth = 1024;

const vec4 aliveColor = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 deadColor = vec4(0.0, 0.0, 0.0, 1.0);

layout (local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout (set = 0, binding = 0, r8) restrict uniform readonly image2D inputImage;
layout (set = 0, binding = 1, r8) restrict uniform writeonly image2D outputImage;

layout(push_constant) uniform PushConstants {
	ivec2 friendlyStart;
	ivec2 friendlyEnd;

	ivec2 deadlyStart;
	ivec2 deadlyEnd;

	ivec2 barrierStart;
	ivec2 barrierEnd;

	int generation;
	int reverseInterval;
	bool enableExploding;
	bool enableReversing;
} params;

bool isCellAlive(int x, int y) {
	vec4 pixel = imageLoad(inputImage, ivec2(x, y));
	return pixel.r > 0.5;
}

int getLiveNeighbours(int x, int y) {
	int count = 0;
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			if (i == 0 && j == 0) continue;
			int nx = x + i;
			int ny = y + j;
			if (nx >= 0 && nx < gridWidth && ny >= 0 && ny < gridWidth) {
				count += int(isCellAlive(nx, ny));
			}
		}
	}
	return count;
}

int countNeighbors5x5(int x, int y) {
	int count = 0;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			if (i == 0 && j == 0) continue;
			int nx = x + i;
			int ny = y + j;
			if (nx >= 0 && nx < gridWidth && ny >= 0 && ny < gridWidth) {
				count += int(isCellAlive(nx, ny));
			}
		}
	}
	return count;
}

int countCardinalAlive(int x, int y) {
	int count = 0;
	if (x > 0 && isCellAlive(x - 1, y)) count++;
	if (x < gridWidth - 1 && isCellAlive(x + 1, y)) count++;
	if (y > 0 && isCellAlive(x, y - 1)) count++;
	if (y < gridWidth - 1 && isCellAlive(x, y + 1)) count++;
	return count;
}

bool inZone(ivec2 pos, ivec2 start, ivec2 end) {
	return pos.x >= start.x && pos.x <= end.x &&
		   pos.y >= start.y && pos.y <= end.y;
}

bool inFriendlyZone(ivec2 pos) { return inZone(pos, params.friendlyStart, params.friendlyEnd); }
bool inDeadlyZone(ivec2 pos) { return inZone(pos, params.deadlyStart, params.deadlyEnd); }
bool inBarrierZone(ivec2 pos) { return inZone(pos, params.barrierStart, params.barrierEnd); }

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (pos.x >= gridWidth || pos.y >= gridWidth) return;

	bool isAlive = isCellAlive(pos.x, pos.y);
	int liveNeighbours = getLiveNeighbours(pos.x, pos.y);
	bool nextState = isAlive;

	if (inFriendlyZone(pos)) {
		if (isAlive && liveNeighbours < 2) {
			int largeAreaNeighbors = countNeighbors5x5(pos.x, pos.y);
			nextState = largeAreaNeighbors >= 4;
		} else {
			nextState = (isAlive && (liveNeighbours == 2 || liveNeighbours == 3)) || (!isAlive && liveNeighbours == 3);
		}
	}
	else if (inDeadlyZone(pos)) {
		if (isAlive && liveNeighbours >= 3) {
			nextState = false;
		} else {
			nextState = (isAlive && (liveNeighbours == 2 || liveNeighbours == 3)) || (!isAlive && liveNeighbours == 3);
		}
	}
	else if (inBarrierZone(pos)) {
		if (isAlive) {
			nextState = countCardinalAlive(pos.x, pos.y) >= 2;
		} else {
			nextState = false;
		}
	}
	else {
		if (isAlive && (liveNeighbours < 2 || liveNeighbours > 3)) {
			nextState = false;
		} else if (!isAlive && liveNeighbours == 3) {
			nextState = true;
		}
	}

	// Reversing Time
	if (params.enableReversing && (params.generation % params.reverseInterval == 0)) {
		nextState = !nextState;
	}

	// Exploding Cells
	if (params.enableExploding && isAlive && liveNeighbours >= 3) {
		ivec2 up    = pos + ivec2(0, -1);
		ivec2 down  = pos + ivec2(0, 1);
		ivec2 left  = pos + ivec2(-1, 0);
		ivec2 right = pos + ivec2(1, 0);

		if (up.y >= 0) imageStore(outputImage, up, aliveColor);
		if (down.y < gridWidth) imageStore(outputImage, down, aliveColor);
		if (left.x >= 0) imageStore(outputImage, left, aliveColor);
		if (right.x < gridWidth) imageStore(outputImage, right, aliveColor);
	}

	vec4 newColor = nextState ? aliveColor : deadColor;
	imageStore(outputImage, pos, newColor);
}
