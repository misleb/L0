/* l0rt.c -- entry point linked into every compiled L0 program.
 *
 * Supplies the host half of the contract in spec/L0.md section 9: read stdin
 * into a byte list, apply main, write the result. Both symbols below are
 * defined by the generated IR (spec section 10.2).
 */

#include "l0core.h"

extern l0_val l0_f_main(l0_val input);
extern l0_val l0_main_ret_kind;

static int run(void *unused) {
  (void)unused;
  l0_val input = l0_read_stdin_list();
  l0_val result = l0_f_main(input);
  l0_write_result(result, (int)l0_main_ret_kind);
  return 0;
}

int main(void) {
  l0_arena_init();
  return l0_run_on_big_stack(run, NULL);
}
