#include "lpm.h"
#include <rte_table.h>
#include <rte_table_lpm.h>

void* (*mp_lpm_table_create)(void *params, int socket_id, uint32_t entry_size) = rte_table_lpm_ops.f_create;



