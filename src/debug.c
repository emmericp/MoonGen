#include "debug.h"

#include <stdio.h>

void printhex(char str[], void* data, int len){
  printf(str);
  uint8_t *data8 = data;
  while(len--){
    printf("%02x ", *(data8++));
  }
  printf("\n");
}
