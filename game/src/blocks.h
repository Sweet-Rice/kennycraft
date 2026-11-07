// blocks.h — block types (frozen list from the plan).
#ifndef KC_BLOCKS_H
#define KC_BLOCKS_H

enum {
    B_AIR = 0, B_GRASS, B_DIRT, B_STONE, B_COBBLE, B_LOG, B_LEAVES, B_PLANKS,
    B_SAND, B_BRICK, B_BEDROCK,
    B_SPARE11, B_SPARE12, B_SPARE13, B_SPARE14, B_SPARE15,
    B_COUNT
};

#define WORLD_CHUNKS   256     // 256 x 256 chunks
#define CHUNK_W        16
#define BUILD_MAX_Y    28      // highest y the player may place into; keeps the eye inside the window
#define WORLD_SEED     0x4B43u // "KC"

#endif
