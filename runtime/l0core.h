/* l0core.h -- L0 value representation, allocation, and host I/O.
 *
 * Shared by the compiled-program runtime (l0rt.c) and the stage-0 interpreter
 * (stage0/l0i.c) so that the two can never disagree about what an L0 value is.
 *
 * Representation is defined in spec/L0.md section 10.1: every L0 value is one
 * i64. Lists are cons-cell pointers with 0 as the empty list; data values are
 * pointers to a tag word followed by one word per field.
 */
#ifndef L0CORE_H
#define L0CORE_H

#include <stddef.h>
#include <stdint.h>

typedef int64_t l0_val;

/* Return kinds for main, matching @l0_main_ret_kind in spec section 10.2. */
#define L0_RET_INT 0
#define L0_RET_BOOL 1
#define L0_RET_LIST 2

#define L0_EXIT_RUNTIME_ERROR 70

/* Bump-pointer arena. Never frees; see spec section 10.3. Initialization is
 * lazy, so calling any allocating function before l0_arena_init is fine. */
void l0_arena_init(void);
void *l0_arena_alloc(size_t bytes);

/* Writes "l0: runtime error: <msg>" to stderr and exits 70 without flushing
 * stdout, so a failed run produces no output at all. */
void l0_runtime_error(const char *msg) __attribute__((noreturn));

/* The runtime interface exported to generated IR. */
l0_val l0_cons(l0_val head, l0_val tail);
l0_val l0_head(l0_val list);
l0_val l0_tail(l0_val list);
l0_val l0_is_empty(l0_val list);
l0_val l0_div(l0_val a, l0_val b);
l0_val l0_mod(l0_val a, l0_val b);
l0_val l0_data_new(l0_val tag, l0_val nfields);
void l0_data_set(l0_val block, l0_val index, l0_val value);
l0_val l0_data_tag(l0_val block);
l0_val l0_data_get(l0_val block, l0_val index);

/* Host I/O. The only impure part of an L0 program's execution. */
l0_val l0_read_stdin_list(void);
void l0_write_result(l0_val value, int ret_kind);

/* Runs fn on a thread with a large stack, because L0 expresses all iteration
 * as recursion and has no tail-call guarantee. Size comes from L0_STACK_MB
 * (default 512). Also installs a handler that reports stack exhaustion as a
 * runtime error rather than a bare segfault. */
int l0_run_on_big_stack(int (*fn)(void *), void *arg);

#endif /* L0CORE_H */
