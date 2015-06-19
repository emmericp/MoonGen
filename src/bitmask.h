#ifndef MG_BITMASK_H
#define MG_BITMASK_H
#include <stdint.h>

struct mg_bitmask{
  uint16_t size;
  uint16_t n_blocks;
  uint64_t mask[0];
};
struct mg_bitmask * mg_bitmask_create(uint16_t size);
void mg_bitmask_free(struct mg_bitmask * mask);
void mg_bitmask_set_n_one(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_set_all_one(struct mg_bitmask * mask);
uint8_t mg_bitmask_get_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_set_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_clear_all(struct mg_bitmask * mask);
void mg_bitmask_clear_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_and(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result);
void mg_bitmask_xor(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result);
void mg_bitmask_or(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result);
void mg_bitmask_not(struct mg_bitmask * mask1, struct mg_bitmask * result);
#endif
