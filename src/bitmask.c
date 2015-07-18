#include "bitmask.h"
#include "rte_malloc.h"
#include "debug.h"

struct mg_bitmask * mg_bitmask_create(uint16_t size){
  uint16_t n_blocks = (size-1)/64 + 1;
  struct mg_bitmask *mask = rte_zmalloc(NULL, sizeof(struct mg_bitmask) + (size-1)/64 * 8 + 8, 0);
  mask->size = size;
  mask->n_blocks = n_blocks;
  return mask;
}
void mg_bitmask_free(struct mg_bitmask * mask){
  rte_free(mask);
}

void mg_bitmask_clear_all(struct mg_bitmask * mask){
  // TODO: check if memset() would be faster for 64bit values...
  uint16_t i;
  for(i=0; i< mask->n_blocks; i++){
    mask->mask[i] = 0;
  }
}

// This will only touch the first n bits. If other bits are set/cleared, they
// will not be affected
void mg_bitmask_set_n_one(struct mg_bitmask * mask, uint16_t n){
  // TODO: check if memset() would be faster for 64bit values...
  uint64_t * msk = mask->mask;
  while(n>=64){
    *msk = 0xffffffffffffffff;
    n -= 64;
    msk++;
  }
  if(n & 0x3f){
    *msk |= (0xffffffffffffffff >> (64-n));
  }
}

void mg_bitmask_set_all_one(struct mg_bitmask * mask){
  // TODO: check if memset() would be faster for 64bit values...
  // TODO: use mg_bitmask_set_n_one instead...
  uint16_t i;
  for(i=0; i< mask->n_blocks; i++){
    mask->mask[i] = 0xffffffffffffffff;
  }
  // FIXME XXX TODO why do we need this??? can't we just set all blocks to 1s?
  if(mask->size & 0x3f){
    mask->mask[mask->n_blocks-1] = (0xffffffffffffffff >> (64-(mask->size & 0x3f)));
  }
}

uint8_t mg_bitmask_get_bit(struct mg_bitmask * mask, uint16_t n){
  // printf("CCC get bit %d\n", n);
  // printhex("mask = ", mask, 30);
  // printhex("mask = ", mask->mask, 30);
  // uint64_t r1 = mask->mask[n/64] & (1ULL<< (n&0x3f));
  // printhex("r1 = ", &r1, 8);
  uint8_t result = ( (mask->mask[n/64] & (1ULL<< (n&0x3f))) != 0);
  // printf("result = %d\n", (int)result);
  return result;
}

void mg_bitmask_set_bit(struct mg_bitmask * mask, uint16_t n){
  //printf(" CC set bit nr %d\n", n);
  //printhex("mask = ", mask->mask, 8*3);
  mask->mask[n/64] |= (1ULL<< (n&0x3f));
  //printhex("mask = ", mask->mask, 8*3);
}

void mg_bitmask_clear_bit(struct mg_bitmask * mask, uint16_t n){
  mask->mask[n/64] &= ~(1ULL<< (n&0x3f));
}

void mg_bitmask_and(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result){
  uint16_t i;
  for(i=0; i< mask1->n_blocks; i++){
    result->mask[i] = mask1->mask[i] & mask2->mask[i];
  }
}

void mg_bitmask_xor(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result){
  uint16_t i;
  for(i=0; i< mask1->n_blocks; i++){
    result->mask[i] = mask1->mask[i] ^ mask2->mask[i];
  }
}

void mg_bitmask_or(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result){
  uint16_t i;
  for(i=0; i< mask1->n_blocks; i++){
    result->mask[i] = mask1->mask[i] | mask2->mask[i];
  }
}

void mg_bitmask_not(struct mg_bitmask * mask1, struct mg_bitmask * result){
  uint16_t i;
  for(i=0; i< mask1->n_blocks; i++){
    result->mask[i] = ~(mask1->mask[i]);
  }
}
