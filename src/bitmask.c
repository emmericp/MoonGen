#include "bitmask.h"
#include "rte_malloc.h"

struct mg_bitmask * mg_bitmask_create(uint16_t size){
  uint16_t n_blocks = (size-1)/64 + 1;
  struct mg_bitmask *mask = rte_zmalloc(NULL, sizeof(struct mg_bitmask) + (size-1)/64 * 8 + 8, 0);
  mask->size = size;
  mask->n_blocks = n_blocks;
  return mask;
}

void mg_bitmask_set_all_one(struct mg_bitmask * mask){
  // TODO: check if memset() would be faster for 64bit values...
  uint16_t i;
  for(i=0; i< mask->n_blocks; i++){
    mask->mask[i] = 0xffffffffffffffff;
  }
  if(mask->size & 0x3f){
    mask->mask[mask->n_blocks-1] = (0xffffffffffffffff >> (64-(mask->size & 0x3f)));
  }
}

uint8_t mg_bitmask_get_bit(struct mg_bitmask * mask, uint16_t n){
  return mask->mask[n/64] & (1ULL<< (n&0x3f));
}

void mg_bitmask_set_bit(struct mg_bitmask * mask, uint16_t n){
  mask->mask[n/64] |= (1ULL<< (n&0x3f));
}

void mg_bitmask_clear_bit(struct mg_bitmask * mask, uint16_t n){
  mask->mask[n/64] &= ~(1ULL<< (n&0x3f));
}

void mg_bitmask_and(struct mg_bitmask * mask1, struct mg_bitmask * mask2){
  uint16_t i;
  for(i=0; i< mask1->n_blocks; i++){
    mask1->mask[i] &= mask2->mask[i];
  }
}

void mg_bitmask_or(struct mg_bitmask * mask1, struct mg_bitmask * mask2){
  uint16_t i;
  for(i=0; i< mask1->n_blocks; i++){
    mask1->mask[i] |= mask2->mask[i];
  }
}
