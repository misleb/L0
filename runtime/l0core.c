/* l0core.c -- see l0core.h */

#include "l0core.h"

#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ------------------------------------------------------------------ errors */

void l0_runtime_error(const char *msg) {
  /* Deliberately does not flush stdout: spec section 8 requires that a failed
   * run produce no standard output. _exit skips atexit handlers for the same
   * reason. */
  fputs("l0: runtime error: ", stderr);
  fputs(msg, stderr);
  fputc('\n', stderr);
  fflush(stderr);
  _exit(L0_EXIT_RUNTIME_ERROR);
}

/* ------------------------------------------------------------------- arena */

#define L0_CHUNK_BYTES (64u * 1024u * 1024u)

static char *arena_cur;
static char *arena_end;

void l0_arena_init(void) { /* allocation is lazy; nothing to do */ }

static void arena_grow(size_t bytes) {
  size_t want = bytes > L0_CHUNK_BYTES ? bytes : L0_CHUNK_BYTES;
  char *chunk = (char *)malloc(want);
  if (chunk == NULL) l0_runtime_error("heap exhausted");
  arena_cur = chunk;
  arena_end = chunk + want;
}

void *l0_arena_alloc(size_t bytes) {
  bytes = (bytes + 15u) & ~(size_t)15u; /* keep everything 16-byte aligned */
  if ((size_t)(arena_end - arena_cur) < bytes) arena_grow(bytes);
  void *p = arena_cur;
  arena_cur += bytes;
  return p;
}

/* ------------------------------------------------------------------- lists */

l0_val l0_cons(l0_val head, l0_val tail) {
  l0_val *cell = (l0_val *)l0_arena_alloc(2 * sizeof(l0_val));
  cell[0] = head;
  cell[1] = tail;
  return (l0_val)(intptr_t)cell;
}

l0_val l0_head(l0_val list) {
  if (list == 0) l0_runtime_error("head of empty list");
  return ((l0_val *)(intptr_t)list)[0];
}

l0_val l0_tail(l0_val list) {
  if (list == 0) l0_runtime_error("tail of empty list");
  return ((l0_val *)(intptr_t)list)[1];
}

l0_val l0_is_empty(l0_val list) { return list == 0 ? 1 : 0; }

/* -------------------------------------------------------------- arithmetic */

/* div and mod are runtime calls rather than instructions so that generated IR
 * contains no error checking, and so that the three cases LLVM treats as
 * undefined behavior get L0's defined wrapping result. See spec section 6.1. */

l0_val l0_div(l0_val a, l0_val b) {
  if (b == 0) l0_runtime_error("division by zero");
  if (b == -1 && a == INT64_MIN) return INT64_MIN;
  return a / b;
}

l0_val l0_mod(l0_val a, l0_val b) {
  if (b == 0) l0_runtime_error("modulo by zero");
  if (b == -1 && a == INT64_MIN) return 0;
  return a % b;
}

/* ------------------------------------------------------------- data blocks */

l0_val l0_data_new(l0_val tag, l0_val nfields) {
  l0_val *block =
      (l0_val *)l0_arena_alloc((size_t)(nfields + 1) * sizeof(l0_val));
  block[0] = tag;
  for (l0_val i = 0; i < nfields; i++) block[i + 1] = 0;
  return (l0_val)(intptr_t)block;
}

void l0_data_set(l0_val block, l0_val index, l0_val value) {
  ((l0_val *)(intptr_t)block)[index + 1] = value;
}

l0_val l0_data_tag(l0_val block) { return ((l0_val *)(intptr_t)block)[0]; }

l0_val l0_data_get(l0_val block, l0_val index) {
  return ((l0_val *)(intptr_t)block)[index + 1];
}

/* --------------------------------------------------------------- host I/O */

l0_val l0_read_stdin_list(void) {
  size_t cap = 1u << 16, len = 0;
  unsigned char *buf = (unsigned char *)malloc(cap);
  if (buf == NULL) l0_runtime_error("heap exhausted");

  for (;;) {
    if (len == cap) {
      cap *= 2;
      unsigned char *grown = (unsigned char *)realloc(buf, cap);
      if (grown == NULL) l0_runtime_error("heap exhausted");
      buf = grown;
    }
    size_t n = fread(buf + len, 1, cap - len, stdin);
    if (n == 0) break;
    len += n;
  }

  /* Built back to front so the list ends up in input order. */
  l0_val list = 0;
  for (size_t i = len; i > 0; i--) list = l0_cons((l0_val)buf[i - 1], list);
  free(buf);
  return list;
}

static void write_list(l0_val list) {
  unsigned char buf[65536];
  size_t n = 0;
  while (list != 0) {
    l0_val *cell = (l0_val *)(intptr_t)list;
    if (n == sizeof buf) {
      fwrite(buf, 1, n, stdout);
      n = 0;
    }
    /* Reduced modulo 256; the cast gives the correct result for negatives. */
    buf[n++] = (unsigned char)((uint64_t)cell[0] & 0xFFu);
    list = cell[1];
  }
  if (n != 0) fwrite(buf, 1, n, stdout);
}

void l0_write_result(l0_val value, int ret_kind) {
  switch (ret_kind) {
    case L0_RET_INT: printf("%lld\n", (long long)value); break;
    case L0_RET_BOOL: fputs(value != 0 ? "true\n" : "false\n", stdout); break;
    case L0_RET_LIST: write_list(value); break;
    default: l0_runtime_error("internal: bad return kind for main");
  }
  fflush(stdout);
}

/* ---------------------------------------------------------- big stack run */

#define L0_ALTSTACK_BYTES (1u << 17)
#define L0_DEFAULT_STACK_MB 512u

static void stack_overflow_handler(int sig, siginfo_t *info, void *ctx) {
  (void)sig;
  (void)info;
  (void)ctx;
  /* A well-typed L0 program cannot access invalid memory for any other reason,
   * so attributing this to the stack is safe. Only async-signal-safe calls
   * here. */
  static const char msg[] = "l0: runtime error: stack exhausted\n";
  ssize_t ignored = write(2, msg, sizeof(msg) - 1);
  (void)ignored;
  _exit(L0_EXIT_RUNTIME_ERROR);
}

static void install_stack_overflow_handler(void) {
  static char altstack[L0_ALTSTACK_BYTES];
  stack_t ss;
  memset(&ss, 0, sizeof ss);
  ss.ss_sp = altstack;
  ss.ss_size = sizeof altstack;
  if (sigaltstack(&ss, NULL) != 0) return;

  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_sigaction = stack_overflow_handler;
  sa.sa_flags = SA_ONSTACK | SA_SIGINFO;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGSEGV, &sa, NULL);
  sigaction(SIGBUS, &sa, NULL);
}

typedef struct {
  int (*fn)(void *);
  void *arg;
  int result;
} BigStackCall;

static void *big_stack_trampoline(void *p) {
  BigStackCall *call = (BigStackCall *)p;
  install_stack_overflow_handler();
  call->result = call->fn(call->arg);
  return NULL;
}

int l0_run_on_big_stack(int (*fn)(void *), void *arg) {
  size_t mb = L0_DEFAULT_STACK_MB;
  const char *env = getenv("L0_STACK_MB");
  if (env != NULL && *env != '\0') {
    long v = strtol(env, NULL, 10);
    if (v > 0) mb = (size_t)v;
  }

  pthread_attr_t attr;
  if (pthread_attr_init(&attr) != 0) return fn(arg);
  pthread_attr_setstacksize(&attr, mb * 1024u * 1024u);

  BigStackCall call;
  call.fn = fn;
  call.arg = arg;
  call.result = 1;

  pthread_t thread;
  int rc = pthread_create(&thread, &attr, big_stack_trampoline, &call);
  pthread_attr_destroy(&attr);
  if (rc != 0) {
    /* Requested stack was unavailable; the default stack is better than
     * refusing to run. */
    install_stack_overflow_handler();
    return fn(arg);
  }
  pthread_join(thread, NULL);
  return call.result;
}
