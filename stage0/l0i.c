/* l0i.c -- stage-0 implementation of L0 v1: reader, type checker, interpreter.
 *
 * THIS FILE IS DISPOSABLE. It exists only to run the L0 compiler that is
 * written in L0, long enough to reach a self-compilation fixpoint. Once
 * seed/stage2.ll is checked in, this file is deleted and L0 has exactly one
 * implementation. Do not invest in it beyond correctness: it does not need to
 * be fast, and it does not need to produce beautiful code.
 *
 * It is the reference for nothing. spec/L0.md is the reference. Where this
 * file and the spec disagree, this file is wrong.
 *
 * Usage:
 *   l0i check FILE...    type check only; errors to stderr, exit 1 on failure
 *   l0i run   FILE...    type check, then run main on stdin
 *
 * Value representation is shared with the compiled runtime via l0core.h, so
 * the interpreter and compiled code can never disagree about what a value is.
 */

#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "l0core.h"

#define MAX_ERRORS 50

/* ------------------------------------------------------------------ memory */

static void *xmalloc(size_t n) {
  void *p = malloc(n);
  if (p == NULL) {
    fputs("l0i: out of memory\n", stderr);
    exit(1);
  }
  return p;
}

/* Grows a realloc'd array to hold at least len+1 elements. */
static void *grow(void *data, int *cap, int len, size_t elem) {
  if (len < *cap) return data;
  int newcap = (*cap == 0) ? 8 : *cap * 2;
  void *p = realloc(data, (size_t)newcap * elem);
  if (p == NULL) {
    fputs("l0i: out of memory\n", stderr);
    exit(1);
  }
  *cap = newcap;
  return p;
}

static char *dup_str(const char *s, size_t n) {
  char *p = (char *)xmalloc(n + 1);
  memcpy(p, s, n);
  p[n] = '\0';
  return p;
}

/* ------------------------------------------------------------------- types */

typedef enum { TY_INT, TY_BOOL, TY_LIST, TY_DATA } TyKind;

typedef struct Ty {
  TyKind kind;
  struct Ty *elem; /* TY_LIST */
  int data_id;     /* TY_DATA */
} Ty;

static Ty ty_int_store = {TY_INT, NULL, -1};
static Ty ty_bool_store = {TY_BOOL, NULL, -1};

#define T_INT (&ty_int_store)
#define T_BOOL (&ty_bool_store)

static Ty *ty_list(Ty *elem) {
  Ty *t = (Ty *)xmalloc(sizeof *t);
  t->kind = TY_LIST;
  t->elem = elem;
  t->data_id = -1;
  return t;
}

static Ty *ty_data(int id) {
  Ty *t = (Ty *)xmalloc(sizeof *t);
  t->kind = TY_DATA;
  t->elem = NULL;
  t->data_id = id;
  return t;
}

static int ty_eq(const Ty *a, const Ty *b) {
  if (a->kind != b->kind) return 0;
  switch (a->kind) {
    case TY_LIST: return ty_eq(a->elem, b->elem);
    case TY_DATA: return a->data_id == b->data_id;
    default: return 1;
  }
}

/* ------------------------------------------------------- program structure */

typedef struct {
  const char *file;
  int line;
  int col;
} Pos;

typedef struct Expr Expr;

typedef struct {
  char *name;
  Pos pos;
  Ty **fields;
  int nfields;
  int tag;
  int data_id;
} Ctor;

typedef struct {
  char *name;
  Pos pos;
  int id; /* index into datas[], which is what a TY_DATA stores */
  struct Sx *decl;
  Ctor **ctors;
  int nctors;
  int cap;
  int max_fields;
} DataTy;

typedef struct {
  char *name;
  Pos pos;
  char **pnames;
  Ty **ptypes;
  int nparams;
  Ty *ret;
  struct Sx *body_sx;
  Expr *body;
  int nslots;
} Fn;

static DataTy **datas;
static int ndatas, cap_datas;
static Ctor **ctors;
static int nctors, cap_ctors;
static Fn **fns;
static int nfns, cap_fns;

static DataTy *find_data(const char *name) {
  for (int i = 0; i < ndatas; i++)
    if (strcmp(datas[i]->name, name) == 0) return datas[i];
  return NULL;
}

static Ctor *find_ctor(const char *name) {
  for (int i = 0; i < nctors; i++)
    if (strcmp(ctors[i]->name, name) == 0) return ctors[i];
  return NULL;
}

static Fn *find_fn(const char *name) {
  for (int i = 0; i < nfns; i++)
    if (strcmp(fns[i]->name, name) == 0) return fns[i];
  return NULL;
}

/* Renders a type as spec-legal source text. Leaks; the process is short. */
static char *ty_str(const Ty *t) {
  switch (t->kind) {
    case TY_INT: return dup_str("int", 3);
    case TY_BOOL: return dup_str("bool", 4);
    case TY_DATA: {
      const char *n = datas[t->data_id]->name;
      return dup_str(n, strlen(n));
    }
    case TY_LIST: {
      char *inner = ty_str(t->elem);
      size_t n = strlen(inner) + 8;
      char *out = (char *)xmalloc(n);
      snprintf(out, n, "(list %s)", inner);
      free(inner);
      return out;
    }
  }
  return dup_str("?", 1);
}

/* ------------------------------------------------------------ diagnostics */

static int error_count;
static jmp_buf decl_bail;
static int decl_bail_active;

static void report(Pos pos, const char *fmt, va_list ap) {
  if (error_count < MAX_ERRORS) {
    fprintf(stderr, "%s:%d:%d: error: ", pos.file, pos.line, pos.col);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
  } else if (error_count == MAX_ERRORS) {
    fprintf(stderr, "l0i: too many errors; stopping\n");
  }
  error_count++;
}

/* Records an error and keeps going. Used for whole-program checks where
 * continuing yields more useful output. */
static void record(Pos pos, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  report(pos, fmt, ap);
  va_end(ap);
}

/* Runs one declaration's worth of checking, recovering from the first error
 * in it so that the remaining declarations still get checked. Loop counters
 * around this must be volatile, since longjmp leaves non-volatile automatic
 * variables indeterminate. */
#define WITH_RECOVERY(stmt)       \
  do {                            \
    if (setjmp(decl_bail) == 0) { \
      decl_bail_active = 1;       \
      stmt;                       \
    }                             \
    decl_bail_active = 0;         \
  } while (0)

/* Records an error and abandons the current declaration, so that one bad
 * function body does not suppress checking of the others. */
static void fail(Pos pos, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  report(pos, fmt, ap);
  va_end(ap);
  if (decl_bail_active) longjmp(decl_bail, 1);
  exit(1);
}

/* ------------------------------------------------------------------ reader */

typedef enum { SX_INT, SX_STR, SX_SYM, SX_LIST } SxKind;

typedef struct Sx {
  SxKind kind;
  Pos pos;
  int64_t ival;          /* SX_INT */
  unsigned char *bytes;  /* SX_STR */
  int nbytes;            /* SX_STR */
  char *sym;             /* SX_SYM */
  struct Sx **items;     /* SX_LIST */
  int nitems;
} Sx;

typedef struct {
  const unsigned char *src;
  size_t len;
  size_t i;
  int line;
  int col;
  const char *file;
} Reader;

static Pos here(Reader *r) {
  Pos p;
  p.file = r->file;
  p.line = r->line;
  p.col = r->col;
  return p;
}

static int at_end(Reader *r) { return r->i >= r->len; }
static int peek(Reader *r) { return at_end(r) ? -1 : r->src[r->i]; }

static int advance(Reader *r) {
  int c = r->src[r->i++];
  if (c == '\n') {
    r->line++;
    r->col = 1;
  } else {
    r->col++;
  }
  return c;
}

static int is_space(int c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}
static int is_digit(int c) { return c >= '0' && c <= '9'; }
static int is_lower_start(int c) { return (c >= 'a' && c <= 'z') || c == '_'; }
static int is_upper_start(int c) { return c >= 'A' && c <= 'Z'; }
static int is_name_rest(int c) {
  return is_lower_start(c) || is_upper_start(c) || is_digit(c);
}

static void skip_trivia(Reader *r) {
  for (;;) {
    while (!at_end(r) && is_space(peek(r))) advance(r);
    if (!at_end(r) && peek(r) == ';') {
      while (!at_end(r) && peek(r) != '\n') advance(r);
      continue;
    }
    return;
  }
}

static int hex_val(int c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static Sx *new_sx(SxKind kind, Pos pos) {
  Sx *s = (Sx *)xmalloc(sizeof *s);
  memset(s, 0, sizeof *s);
  s->kind = kind;
  s->pos = pos;
  return s;
}

static Sx *read_sx(Reader *r);

static Sx *read_string(Reader *r) {
  Pos pos = here(r);
  advance(r); /* the opening quote */

  unsigned char *buf = NULL;
  int len = 0, cap = 0;
  for (;;) {
    if (at_end(r)) fail(pos, "unterminated string literal");
    int c = peek(r);
    if (c == '\n') fail(here(r), "newline in string literal; use \\n");
    advance(r);
    if (c == '"') break;

    if (c == '\\') {
      if (at_end(r)) fail(pos, "unterminated string literal");
      Pos epos = here(r);
      int e = advance(r);
      switch (e) {
        case 'n': c = 10; break;
        case 't': c = 9; break;
        case 'r': c = 13; break;
        case '\\': c = 92; break;
        case '"': c = 34; break;
        case 'x': {
          if (at_end(r)) fail(epos, "incomplete \\x escape");
          int h1 = hex_val(advance(r));
          if (at_end(r)) fail(epos, "incomplete \\x escape");
          int h2 = hex_val(advance(r));
          if (h1 < 0 || h2 < 0)
            fail(epos, "\\x needs exactly two hexadecimal digits");
          c = h1 * 16 + h2;
          break;
        }
        default:
          fail(epos, "unknown escape \\%c; the escapes are \\n \\t \\r \\\\ \\\" \\xHH",
               e);
      }
    }
    buf = (unsigned char *)grow(buf, &cap, len, sizeof *buf);
    buf[len++] = (unsigned char)c;
  }

  Sx *s = new_sx(SX_STR, pos);
  s->bytes = buf;
  s->nbytes = len;
  return s;
}

static Sx *read_number(Reader *r) {
  Pos pos = here(r);
  int negative = 0;
  if (peek(r) == '-') {
    advance(r);
    negative = 1;
  }

  uint64_t mag = 0;
  int ndigits = 0;
  while (!at_end(r) && is_digit(peek(r))) {
    int d = advance(r) - '0';
    if (mag > (UINT64_MAX - (uint64_t)d) / 10)
      fail(pos, "integer literal does not fit in 64 bits");
    mag = mag * 10 + (uint64_t)d;
    ndigits++;
  }
  if (ndigits == 0) fail(pos, "expected digits after '-'");

  /* A name character immediately after the digits means the whole thing was
   * never a number, e.g. 12abc. */
  if (!at_end(r) && is_name_rest(peek(r)))
    fail(pos, "invalid character in integer literal");

  uint64_t limit = negative ? 9223372036854775808ULL : 9223372036854775807ULL;
  if (mag > limit) fail(pos, "integer literal does not fit in 64 bits");

  Sx *s = new_sx(SX_INT, pos);
  if (negative)
    s->ival = (mag == 9223372036854775808ULL) ? INT64_MIN : -(int64_t)mag;
  else
    s->ival = (int64_t)mag;
  return s;
}

static Sx *read_symbol(Reader *r) {
  Pos pos = here(r);
  size_t start = r->i;
  while (!at_end(r) && is_name_rest(peek(r))) advance(r);
  Sx *s = new_sx(SX_SYM, pos);
  s->sym = dup_str((const char *)r->src + start, r->i - start);
  return s;
}

static Sx *read_list(Reader *r) {
  Pos pos = here(r);
  advance(r); /* the opening paren */

  Sx **items = NULL;
  int len = 0, cap = 0;
  for (;;) {
    skip_trivia(r);
    if (at_end(r)) fail(pos, "unclosed '('");
    if (peek(r) == ')') {
      advance(r);
      break;
    }
    Sx *item = read_sx(r);
    items = (Sx **)grow(items, &cap, len, sizeof *items);
    items[len++] = item;
  }

  Sx *s = new_sx(SX_LIST, pos);
  s->items = items;
  s->nitems = len;
  return s;
}

static Sx *read_sx(Reader *r) {
  skip_trivia(r);
  if (at_end(r)) fail(here(r), "unexpected end of file");
  int c = peek(r);
  if (c == '(') return read_list(r);
  if (c == ')') fail(here(r), "unexpected ')'");
  if (c == '"') return read_string(r);
  if (is_digit(c)) return read_number(r);
  if (c == '-') return read_number(r);
  if (is_lower_start(c) || is_upper_start(c)) return read_symbol(r);
  fail(here(r), "unexpected character '%c'", c);
  return NULL;
}

/* ------------------------------------------------------------- name rules */

static const char *reserved_words[] = {"def",  "data", "if",   "let",  "match",
                                       "nil",  "true", "false", "int", "bool",
                                       "list", NULL};

static int is_reserved(const char *name) {
  for (int i = 0; reserved_words[i] != NULL; i++)
    if (strcmp(name, reserved_words[i]) == 0) return 1;
  return 0;
}

static int sym_is(const Sx *s, const char *name) {
  return s->kind == SX_SYM && strcmp(s->sym, name) == 0;
}

static void require_lower_name(const Sx *s, const char *what) {
  if (s->kind != SX_SYM) fail(s->pos, "expected %s", what);
  if (!is_lower_start((unsigned char)s->sym[0]))
    fail(s->pos, "%s must start with a lowercase letter or underscore: %s", what,
         s->sym);
  if (is_reserved(s->sym))
    fail(s->pos, "'%s' is reserved and cannot be used as %s", s->sym, what);
}

/* ------------------------------------------------------------- expressions */

enum {
  B_ADD, B_SUB, B_MUL, B_DIV, B_MOD, B_NEG,
  B_LT, B_LE, B_GT, B_GE, B_EQ,
  B_AND, B_OR, B_NOT,
  B_CONS, B_HEAD, B_TAIL, B_IS_EMPTY
};

static const struct {
  const char *name;
  int arity;
} builtin_table[] = {
    {"add", 2}, {"sub", 2}, {"mul", 2}, {"div", 2}, {"mod", 2}, {"neg", 1},
    {"lt", 2},  {"le", 2},  {"gt", 2},  {"ge", 2},  {"eq", 2},
    {"and", 2}, {"or", 2},  {"not", 1},
    {"cons", 2}, {"head", 1}, {"tail", 1}, {"is_empty", 1},
};

#define NBUILTINS ((int)(sizeof builtin_table / sizeof builtin_table[0]))

static int find_builtin(const char *name) {
  for (int i = 0; i < NBUILTINS; i++)
    if (strcmp(builtin_table[i].name, name) == 0) return i;
  return -1;
}

typedef enum {
  E_INT, E_BOOL, E_STR, E_VAR, E_IF, E_LET, E_NIL, E_MATCH, E_CTOR,
  E_CALL, E_BUILTIN
} EKind;

typedef struct {
  Ctor *ctor;
  int *slots;
  Expr *body;
} Arm;

struct Expr {
  EKind kind;
  Pos pos;
  Ty *type;

  int64_t ival;         /* E_INT, E_BOOL */
  unsigned char *bytes; /* E_STR */
  int nbytes;
  int slot;             /* E_VAR, E_LET */
  Expr *a, *b, *c;      /* E_IF cond/then/else, E_LET value/body */
  Expr **args;          /* E_CALL, E_CTOR, E_BUILTIN */
  int nargs;
  Fn *fn;               /* E_CALL */
  Ctor *ctor;           /* E_CTOR */
  int op;               /* E_BUILTIN */
  Expr *subject;        /* E_MATCH */
  Arm *arms;            /* E_MATCH, indexed by constructor tag */
  int narms;
};

static Expr *new_expr(EKind kind, Pos pos) {
  Expr *e = (Expr *)xmalloc(sizeof *e);
  memset(e, 0, sizeof *e);
  e->kind = kind;
  e->pos = pos;
  return e;
}

/* ---------------------------------------------------------------- scoping */

typedef struct {
  const char *name;
  Ty *type;
  int slot;
} Binding;

static Binding *scope;
static int scope_len, scope_cap;
static int next_slot, max_slots;

static void scope_reset(void) {
  scope_len = 0;
  next_slot = 0;
  max_slots = 0;
}

static int scope_push(const char *name, Ty *type) {
  scope = (Binding *)grow(scope, &scope_cap, scope_len, sizeof *scope);
  int slot = next_slot++;
  if (next_slot > max_slots) max_slots = next_slot;
  scope[scope_len].name = name;
  scope[scope_len].type = type;
  scope[scope_len].slot = slot;
  scope_len++;
  return slot;
}

/* Slots are not reused when a scope closes. Every binding in a function gets
 * its own word, which costs nothing and keeps slot assignment trivial. */
static void scope_pop_to(int len) { scope_len = len; }

static Binding *scope_find(const char *name) {
  for (int i = scope_len - 1; i >= 0; i--) /* backwards, so inner shadows */
    if (strcmp(scope[i].name, name) == 0) return &scope[i];
  return NULL;
}

/* ------------------------------------------------------------ type syntax */

static Ty *parse_type(Sx *s) {
  if (s->kind == SX_SYM) {
    if (strcmp(s->sym, "int") == 0) return T_INT;
    if (strcmp(s->sym, "bool") == 0) return T_BOOL;
    if (is_upper_start((unsigned char)s->sym[0])) {
      DataTy *d = find_data(s->sym);
      if (d == NULL) fail(s->pos, "unknown type '%s'", s->sym);
      return ty_data(d->id);
    }
    if (strcmp(s->sym, "list") == 0)
      fail(s->pos, "'list' needs an element type, as in (list int)");
    fail(s->pos, "unknown type '%s'", s->sym);
  }

  if (s->kind == SX_LIST) {
    if (s->nitems == 2 && sym_is(s->items[0], "list"))
      return ty_list(parse_type(s->items[1]));
    if (s->nitems >= 1 && sym_is(s->items[0], "list"))
      fail(s->pos, "(list ...) takes exactly one element type");
  }

  fail(s->pos, "expected a type: int, bool, (list T), or a data type name");
  return NULL;
}

/* -------------------------------------------------------------- checking */

static Expr *chk(Sx *s);

static Expr *chk_expect(Sx *s, Ty *want, const char *role) {
  Expr *e = chk(s);
  if (!ty_eq(e->type, want))
    fail(e->pos, "%s must be %s, but this is %s", role, ty_str(want),
         ty_str(e->type));
  return e;
}

static Expr *chk_if(Sx *s) {
  if (s->nitems != 4)
    fail(s->pos, "if takes exactly 3 parts: (if condition then else)");
  Expr *e = new_expr(E_IF, s->pos);
  e->a = chk_expect(s->items[1], T_BOOL, "the condition of an if");
  e->b = chk(s->items[2]);
  e->c = chk(s->items[3]);
  if (!ty_eq(e->b->type, e->c->type))
    fail(e->c->pos, "the branches of an if must have the same type, but then is %s and else is %s",
         ty_str(e->b->type), ty_str(e->c->type));
  e->type = e->b->type;
  return e;
}

static Expr *chk_let(Sx *s) {
  if (s->nitems != 4)
    fail(s->pos, "let takes exactly 3 parts: (let name value body)");
  require_lower_name(s->items[1], "a let binding name");

  Expr *e = new_expr(E_LET, s->pos);
  /* The bound name is not in scope in its own value, so this is checked
   * before the binding is pushed. */
  e->a = chk(s->items[2]);

  int mark = scope_len;
  e->slot = scope_push(s->items[1]->sym, e->a->type);
  e->b = chk(s->items[3]);
  scope_pop_to(mark);

  e->type = e->b->type;
  return e;
}

static Expr *chk_nil(Sx *s) {
  if (s->nitems != 2)
    fail(s->pos, "nil takes exactly one element type, as in (nil int)");
  Expr *e = new_expr(E_NIL, s->pos);
  e->type = ty_list(parse_type(s->items[1]));
  return e;
}

static Expr *chk_match(Sx *s) {
  if (s->nitems < 3) fail(s->pos, "match needs a subject and at least one arm");

  Expr *e = new_expr(E_MATCH, s->pos);
  e->subject = chk(s->items[1]);
  if (e->subject->type->kind != TY_DATA)
    fail(e->subject->pos, "match needs a data type to examine, but this is %s",
         ty_str(e->subject->type));

  DataTy *d = datas[e->subject->type->data_id];
  e->narms = d->nctors;
  e->arms = (Arm *)xmalloc((size_t)d->nctors * sizeof *e->arms);
  memset(e->arms, 0, (size_t)d->nctors * sizeof *e->arms);

  Ty *arm_type = NULL;

  for (int i = 2; i < s->nitems; i++) {
    Sx *arm_sx = s->items[i];
    if (arm_sx->kind != SX_LIST || arm_sx->nitems != 2)
      fail(arm_sx->pos, "each match arm is ((Constructor names...) result)");

    Sx *pat = arm_sx->items[0];
    if (pat->kind != SX_LIST || pat->nitems < 1 || pat->items[0]->kind != SX_SYM ||
        !is_upper_start((unsigned char)pat->items[0]->sym[0]))
      fail(pat->pos, "a match pattern starts with a constructor name");

    const char *cname = pat->items[0]->sym;
    Ctor *c = find_ctor(cname);
    if (c == NULL) fail(pat->pos, "unknown constructor '%s'", cname);
    if (c->data_id != e->subject->type->data_id)
      fail(pat->pos, "'%s' is a constructor of %s, not %s", cname,
           datas[c->data_id]->name, d->name);
    if (e->arms[c->tag].body != NULL)
      fail(pat->pos, "'%s' already has an arm in this match", cname);

    int nbind = pat->nitems - 1;
    if (nbind != c->nfields)
      fail(pat->pos, "'%s' has %d field%s, but this pattern binds %d name%s",
           cname, c->nfields, c->nfields == 1 ? "" : "s", nbind,
           nbind == 1 ? "" : "s");

    int mark = scope_len;
    int *slots = (int *)xmalloc((size_t)(nbind == 0 ? 1 : nbind) * sizeof *slots);
    for (int f = 0; f < nbind; f++) {
      require_lower_name(pat->items[f + 1], "a field binding name");
      for (int g = 0; g < f; g++)
        if (strcmp(pat->items[f + 1]->sym, pat->items[g + 1]->sym) == 0)
          fail(pat->items[f + 1]->pos,
               "'%s' is bound twice in the same pattern",
               pat->items[f + 1]->sym);
      slots[f] = scope_push(pat->items[f + 1]->sym, c->fields[f]);
    }
    Expr *body = chk(arm_sx->items[1]);
    scope_pop_to(mark);

    if (arm_type == NULL) {
      arm_type = body->type;
    } else if (!ty_eq(arm_type, body->type)) {
      fail(body->pos, "all match arms must have the same type, but an earlier arm is %s and this one is %s",
           ty_str(arm_type), ty_str(body->type));
    }

    e->arms[c->tag].ctor = c;
    e->arms[c->tag].slots = slots;
    e->arms[c->tag].body = body;
  }

  for (int t = 0; t < d->nctors; t++)
    if (e->arms[t].body == NULL)
      fail(s->pos, "match on %s is missing an arm for '%s'", d->name,
           d->ctors[t]->name);

  e->type = arm_type;
  return e;
}

static Expr *chk_ctor(Sx *s) {
  const char *name = s->items[0]->sym;
  Ctor *c = find_ctor(name);
  if (c == NULL) fail(s->items[0]->pos, "unknown constructor '%s'", name);

  int nargs = s->nitems - 1;
  if (nargs != c->nfields)
    fail(s->pos, "'%s' takes %d field%s, but %d %s given", name, c->nfields,
         c->nfields == 1 ? "" : "s", nargs, nargs == 1 ? "was" : "were");

  Expr *e = new_expr(E_CTOR, s->pos);
  e->ctor = c;
  e->nargs = nargs;
  e->args = (Expr **)xmalloc((size_t)(nargs == 0 ? 1 : nargs) * sizeof *e->args);
  for (int i = 0; i < nargs; i++) {
    e->args[i] = chk(s->items[i + 1]);
    if (!ty_eq(e->args[i]->type, c->fields[i]))
      fail(e->args[i]->pos, "field %d of '%s' must be %s, but this is %s", i + 1,
           name, ty_str(c->fields[i]), ty_str(e->args[i]->type));
  }
  e->type = ty_data(c->data_id);
  return e;
}

static Expr *chk_builtin(Sx *s, int op) {
  int nargs = s->nitems - 1;
  if (nargs != builtin_table[op].arity)
    fail(s->pos, "%s takes %d argument%s, but %d %s given",
         builtin_table[op].name, builtin_table[op].arity,
         builtin_table[op].arity == 1 ? "" : "s", nargs,
         nargs == 1 ? "was" : "were");

  Expr *e = new_expr(E_BUILTIN, s->pos);
  e->op = op;
  e->nargs = nargs;
  e->args = (Expr **)xmalloc((size_t)nargs * sizeof *e->args);
  for (int i = 0; i < nargs; i++) e->args[i] = chk(s->items[i + 1]);

  switch (op) {
    case B_ADD: case B_SUB: case B_MUL: case B_DIV: case B_MOD:
      for (int i = 0; i < 2; i++)
        if (!ty_eq(e->args[i]->type, T_INT))
          fail(e->args[i]->pos, "%s needs int arguments, but this is %s",
               builtin_table[op].name, ty_str(e->args[i]->type));
      e->type = T_INT;
      break;

    case B_NEG:
      if (!ty_eq(e->args[0]->type, T_INT))
        fail(e->args[0]->pos, "neg needs an int, but this is %s",
             ty_str(e->args[0]->type));
      e->type = T_INT;
      break;

    case B_LT: case B_LE: case B_GT: case B_GE: case B_EQ:
      for (int i = 0; i < 2; i++)
        if (!ty_eq(e->args[i]->type, T_INT))
          fail(e->args[i]->pos, "%s compares int values, but this is %s",
               builtin_table[op].name, ty_str(e->args[i]->type));
      e->type = T_BOOL;
      break;

    case B_AND: case B_OR:
      for (int i = 0; i < 2; i++)
        if (!ty_eq(e->args[i]->type, T_BOOL))
          fail(e->args[i]->pos, "%s needs bool arguments, but this is %s",
               builtin_table[op].name, ty_str(e->args[i]->type));
      e->type = T_BOOL;
      break;

    case B_NOT:
      if (!ty_eq(e->args[0]->type, T_BOOL))
        fail(e->args[0]->pos, "not needs a bool, but this is %s",
             ty_str(e->args[0]->type));
      e->type = T_BOOL;
      break;

    case B_CONS: {
      /* The list argument determines the element type; no inference needed. */
      if (e->args[1]->type->kind != TY_LIST)
        fail(e->args[1]->pos, "the second argument of cons must be a list, but this is %s",
             ty_str(e->args[1]->type));
      Ty *elem = e->args[1]->type->elem;
      if (!ty_eq(e->args[0]->type, elem))
        fail(e->args[0]->pos,
             "cons onto %s needs an element of type %s, but this is %s",
             ty_str(e->args[1]->type), ty_str(elem), ty_str(e->args[0]->type));
      e->type = e->args[1]->type;
      break;
    }

    case B_HEAD:
      if (e->args[0]->type->kind != TY_LIST)
        fail(e->args[0]->pos, "head needs a list, but this is %s",
             ty_str(e->args[0]->type));
      e->type = e->args[0]->type->elem;
      break;

    case B_TAIL:
      if (e->args[0]->type->kind != TY_LIST)
        fail(e->args[0]->pos, "tail needs a list, but this is %s",
             ty_str(e->args[0]->type));
      e->type = e->args[0]->type;
      break;

    case B_IS_EMPTY:
      if (e->args[0]->type->kind != TY_LIST)
        fail(e->args[0]->pos, "is_empty needs a list, but this is %s",
             ty_str(e->args[0]->type));
      e->type = T_BOOL;
      break;

    default: fail(s->pos, "internal: unhandled builtin");
  }
  return e;
}

static Expr *chk_call(Sx *s) {
  const char *name = s->items[0]->sym;

  /* Call position resolves to a builtin first, then a def, and never to a
   * local. See spec section 7. */
  int op = find_builtin(name);
  if (op >= 0) return chk_builtin(s, op);

  Fn *f = find_fn(name);
  if (f == NULL) {
    if (scope_find(name) != NULL)
      fail(s->items[0]->pos, "'%s' is a local value, and L0 cannot call a value; there is no function named '%s'",
           name, name);
    fail(s->items[0]->pos, "unknown function '%s'", name);
  }

  int nargs = s->nitems - 1;
  if (nargs != f->nparams)
    fail(s->pos, "%s takes %d argument%s, but %d %s given", name, f->nparams,
         f->nparams == 1 ? "" : "s", nargs, nargs == 1 ? "was" : "were");

  Expr *e = new_expr(E_CALL, s->pos);
  e->fn = f;
  e->nargs = nargs;
  e->args = (Expr **)xmalloc((size_t)(nargs == 0 ? 1 : nargs) * sizeof *e->args);
  for (int i = 0; i < nargs; i++) {
    e->args[i] = chk(s->items[i + 1]);
    if (!ty_eq(e->args[i]->type, f->ptypes[i]))
      fail(e->args[i]->pos, "argument %d of %s must be %s, but this is %s",
           i + 1, name, ty_str(f->ptypes[i]), ty_str(e->args[i]->type));
  }
  e->type = f->ret;
  return e;
}

static Expr *chk(Sx *s) {
  switch (s->kind) {
    case SX_INT: {
      Expr *e = new_expr(E_INT, s->pos);
      e->ival = s->ival;
      e->type = T_INT;
      return e;
    }

    case SX_STR: {
      Expr *e = new_expr(E_STR, s->pos);
      e->bytes = s->bytes;
      e->nbytes = s->nbytes;
      e->type = ty_list(T_INT);
      return e;
    }

    case SX_SYM: {
      if (strcmp(s->sym, "true") == 0 || strcmp(s->sym, "false") == 0) {
        Expr *e = new_expr(E_BOOL, s->pos);
        e->ival = (strcmp(s->sym, "true") == 0) ? 1 : 0;
        e->type = T_BOOL;
        return e;
      }
      if (is_upper_start((unsigned char)s->sym[0])) {
        if (find_ctor(s->sym) != NULL)
          fail(s->pos, "constructor '%s' must be written with parentheses, as in (%s ...)",
               s->sym, s->sym);
        fail(s->pos, "'%s' is a type name, and types are not values", s->sym);
      }
      if (is_reserved(s->sym))
        fail(s->pos, "'%s' is reserved and is not a value here", s->sym);

      Binding *b = scope_find(s->sym);
      if (b == NULL) {
        if (find_fn(s->sym) != NULL || find_builtin(s->sym) >= 0)
          fail(s->pos, "'%s' is a function, and L0 has no function values; call it as (%s ...)",
               s->sym, s->sym);
        fail(s->pos, "unknown variable '%s'", s->sym);
      }
      Expr *e = new_expr(E_VAR, s->pos);
      e->slot = b->slot;
      e->type = b->type;
      return e;
    }

    case SX_LIST: {
      if (s->nitems == 0) fail(s->pos, "() is not an expression");
      Sx *head = s->items[0];
      if (head->kind != SX_SYM)
        fail(head->pos, "expected a function or constructor name here");

      if (strcmp(head->sym, "if") == 0) return chk_if(s);
      if (strcmp(head->sym, "let") == 0) return chk_let(s);
      if (strcmp(head->sym, "nil") == 0) return chk_nil(s);
      if (strcmp(head->sym, "match") == 0) return chk_match(s);
      if (strcmp(head->sym, "def") == 0 || strcmp(head->sym, "data") == 0)
        fail(head->pos, "'%s' can only appear at the top level", head->sym);
      if (strcmp(head->sym, "true") == 0 || strcmp(head->sym, "false") == 0)
        fail(head->pos, "'%s' is not a function", head->sym);
      if (is_upper_start((unsigned char)head->sym[0])) return chk_ctor(s);
      return chk_call(s);
    }
  }
  fail(s->pos, "internal: unhandled expression");
  return NULL;
}

/* ------------------------------------------------------------- collection */

/* Pass A: register data type names, so field types can refer to any of them. */
static void collect_data_names(Sx *d) {
  if (d->nitems < 2 || d->items[1]->kind != SX_SYM ||
      !is_upper_start((unsigned char)d->items[1]->sym[0]))
    fail(d->pos, "a data declaration needs an uppercase type name");
  if (d->nitems < 3)
    fail(d->pos, "data type '%s' needs at least one constructor",
         d->items[1]->sym);

  const char *name = d->items[1]->sym;
  if (is_reserved(name))
    fail(d->items[1]->pos, "'%s' is reserved and cannot name a data type", name);
  DataTy *prior = find_data(name);
  if (prior != NULL) {
    record(d->items[1]->pos, "data type '%s' is already declared at %s:%d:%d",
           name, prior->pos.file, prior->pos.line, prior->pos.col);
    return;
  }

  DataTy *dt = (DataTy *)xmalloc(sizeof *dt);
  memset(dt, 0, sizeof *dt);
  dt->name = d->items[1]->sym;
  dt->pos = d->items[1]->pos;
  dt->decl = d;
  datas = (DataTy **)grow(datas, &cap_datas, ndatas, sizeof *datas);
  dt->id = ndatas;
  datas[ndatas++] = dt;
}

/* Pass B: resolve constructor field types and assign tags. Driven from
 * datas[] rather than the declaration list, so a duplicate data declaration
 * (already reported in pass A, and never registered) cannot be processed. */
static void collect_ctors(DataTy *dt) {
  Sx *d = dt->decl;
  for (int i = 2; i < d->nitems; i++) {
    Sx *cs = d->items[i];
    if (cs->kind != SX_LIST || cs->nitems < 1 || cs->items[0]->kind != SX_SYM ||
        !is_upper_start((unsigned char)cs->items[0]->sym[0]))
      fail(cs->pos, "a constructor is (Name field-types...)");

    const char *cname = cs->items[0]->sym;
    Ctor *prior = find_ctor(cname);
    if (prior != NULL) {
      record(cs->items[0]->pos,
             "constructor '%s' is already declared at %s:%d:%d; constructor names must be unique across all data types",
             cname, prior->pos.file, prior->pos.line, prior->pos.col);
      continue;
    }

    Ctor *c = (Ctor *)xmalloc(sizeof *c);
    memset(c, 0, sizeof *c);
    c->name = cs->items[0]->sym;
    c->pos = cs->items[0]->pos;
    c->nfields = cs->nitems - 1;
    c->tag = dt->nctors;
    c->data_id = dt->id;
    c->fields =
        (Ty **)xmalloc((size_t)(c->nfields == 0 ? 1 : c->nfields) * sizeof *c->fields);
    for (int f = 0; f < c->nfields; f++)
      c->fields[f] = parse_type(cs->items[f + 1]);

    if (c->nfields > dt->max_fields) dt->max_fields = c->nfields;

    dt->ctors =
        (Ctor **)grow(dt->ctors, &dt->cap, dt->nctors, sizeof *dt->ctors);
    dt->ctors[dt->nctors++] = c;

    ctors = (Ctor **)grow(ctors, &cap_ctors, nctors, sizeof *ctors);
    ctors[nctors++] = c;
  }
}

/* Pass C: register function signatures. */
static void collect_fn(Sx *d) {
  if (d->nitems != 5)
    fail(d->pos, "a def is (def name (params...) return-type body)");
  require_lower_name(d->items[1], "a function name");

  const char *name = d->items[1]->sym;
  Fn *prior = find_fn(name);
  if (prior != NULL) {
    record(d->items[1]->pos, "function '%s' is already defined at %s:%d:%d",
           name, prior->pos.file, prior->pos.line, prior->pos.col);
    return;
  }

  Sx *params = d->items[2];
  if (params->kind != SX_LIST)
    fail(params->pos, "expected a parameter list, as in ((x int) (y bool))");

  Fn *f = (Fn *)xmalloc(sizeof *f);
  memset(f, 0, sizeof *f);
  f->name = d->items[1]->sym;
  f->pos = d->items[1]->pos;
  f->nparams = params->nitems;
  f->pnames = (char **)xmalloc((size_t)(f->nparams == 0 ? 1 : f->nparams) * sizeof *f->pnames);
  f->ptypes = (Ty **)xmalloc((size_t)(f->nparams == 0 ? 1 : f->nparams) * sizeof *f->ptypes);

  for (int i = 0; i < f->nparams; i++) {
    Sx *p = params->items[i];
    if (p->kind != SX_LIST || p->nitems != 2)
      fail(p->pos, "each parameter is (name type)");
    require_lower_name(p->items[0], "a parameter name");
    for (int j = 0; j < i; j++)
      if (strcmp(p->items[0]->sym, f->pnames[j]) == 0)
        fail(p->items[0]->pos, "parameter '%s' is declared twice",
             p->items[0]->sym);
    f->pnames[i] = p->items[0]->sym;
    f->ptypes[i] = parse_type(p->items[1]);
  }

  f->ret = parse_type(d->items[3]);
  f->body_sx = d->items[4];

  fns = (Fn **)grow(fns, &cap_fns, nfns, sizeof *fns);
  fns[nfns++] = f;
}

/* Pass D: check one function body. */
static void check_fn_body(Fn *f) {
  scope_reset();
  for (int i = 0; i < f->nparams; i++) scope_push(f->pnames[i], f->ptypes[i]);
  f->body = chk(f->body_sx);
  if (!ty_eq(f->body->type, f->ret))
    fail(f->body->pos, "%s declares return type %s, but its body is %s", f->name,
         ty_str(f->ret), ty_str(f->body->type));
  f->nslots = max_slots;
}

/* ---------------------------------------------------------------- evaluate */

static l0_val eval(Expr *e, l0_val *frame);

static l0_val eval_str(Expr *e) {
  l0_val list = 0;
  for (int i = e->nbytes; i > 0; i--)
    list = l0_cons((l0_val)e->bytes[i - 1], list);
  return list;
}

static l0_val eval_builtin(Expr *e, l0_val *frame) {
  /* Arguments are evaluated left to right, before the operation, including
   * for and/or which are strict. See spec section 8. */
  l0_val a = eval(e->args[0], frame);
  l0_val b = (e->nargs > 1) ? eval(e->args[1], frame) : 0;

  switch (e->op) {
    /* Unsigned arithmetic, because L0 wraps and signed overflow is undefined
     * behavior in C. */
    case B_ADD: return (l0_val)((uint64_t)a + (uint64_t)b);
    case B_SUB: return (l0_val)((uint64_t)a - (uint64_t)b);
    case B_MUL: return (l0_val)((uint64_t)a * (uint64_t)b);
    case B_NEG: return (l0_val)(0u - (uint64_t)a);
    case B_DIV: return l0_div(a, b);
    case B_MOD: return l0_mod(a, b);
    case B_LT: return a < b ? 1 : 0;
    case B_LE: return a <= b ? 1 : 0;
    case B_GT: return a > b ? 1 : 0;
    case B_GE: return a >= b ? 1 : 0;
    case B_EQ: return a == b ? 1 : 0;
    case B_AND: return (a != 0 && b != 0) ? 1 : 0;
    case B_OR: return (a != 0 || b != 0) ? 1 : 0;
    case B_NOT: return a == 0 ? 1 : 0;
    case B_CONS: return l0_cons(a, b);
    case B_HEAD: return l0_head(a);
    case B_TAIL: return l0_tail(a);
    case B_IS_EMPTY: return l0_is_empty(a);
    default: l0_runtime_error("internal: unhandled builtin");
  }
}

static l0_val eval(Expr *e, l0_val *frame) {
  switch (e->kind) {
    case E_INT: return e->ival;
    case E_BOOL: return e->ival;
    case E_STR: return eval_str(e);
    case E_NIL: return 0;
    case E_VAR: return frame[e->slot];

    case E_IF:
      return eval(e->a, frame) != 0 ? eval(e->b, frame) : eval(e->c, frame);

    case E_LET:
      frame[e->slot] = eval(e->a, frame);
      return eval(e->b, frame);

    case E_BUILTIN: return eval_builtin(e, frame);

    case E_CTOR: {
      DataTy *d = datas[e->ctor->data_id];
      /* Blocks are sized for the widest constructor of the type, per spec
       * section 10.1. */
      l0_val block = l0_data_new(e->ctor->tag, d->max_fields);
      for (int i = 0; i < e->nargs; i++)
        l0_data_set(block, i, eval(e->args[i], frame));
      return block;
    }

    case E_MATCH: {
      l0_val v = eval(e->subject, frame);
      Arm *arm = &e->arms[l0_data_tag(v)];
      for (int i = 0; i < arm->ctor->nfields; i++)
        frame[arm->slots[i]] = l0_data_get(v, i);
      return eval(arm->body, frame);
    }

    case E_CALL: {
      Fn *f = e->fn;
      int n = f->nslots > 0 ? f->nslots : 1;
      l0_val callee_frame[n];
      /* Safe to fill the callee frame directly: arguments are evaluated in
       * the caller's frame, so they never read these slots. */
      for (int i = 0; i < e->nargs; i++)
        callee_frame[i] = eval(e->args[i], frame);
      return eval(f->body, callee_frame);
    }
  }
  l0_runtime_error("internal: unhandled expression");
}

/* -------------------------------------------------------------------- main */

static char *read_whole_file(const char *path, size_t *len_out) {
  FILE *fp = fopen(path, "rb");
  if (fp == NULL) {
    fprintf(stderr, "l0i: cannot open %s\n", path);
    exit(1);
  }
  size_t cap = 1u << 16, len = 0;
  char *buf = (char *)xmalloc(cap);
  for (;;) {
    if (len == cap) {
      cap *= 2;
      char *grown = (char *)realloc(buf, cap);
      if (grown == NULL) {
        fputs("l0i: out of memory\n", stderr);
        exit(1);
      }
      buf = grown;
    }
    size_t n = fread(buf + len, 1, cap - len, fp);
    if (n == 0) break;
    len += n;
  }
  fclose(fp);
  *len_out = len;
  return buf;
}

static Sx **decls;
static int ndecls, cap_decls;

static void read_file(const char *path) {
  size_t len;
  char *src = read_whole_file(path, &len);

  Reader r;
  r.src = (const unsigned char *)src;
  r.len = len;
  r.i = 0;
  r.line = 1;
  r.col = 1;
  r.file = path;

  for (;;) {
    skip_trivia(&r);
    if (at_end(&r)) break;
    Sx *d = read_sx(&r);
    if (d->kind != SX_LIST || d->nitems == 0 ||
        (!sym_is(d->items[0], "def") && !sym_is(d->items[0], "data")))
      fail(d->pos, "expected a top-level (def ...) or (data ...)");
    decls = (Sx **)grow(decls, &cap_decls, ndecls, sizeof *decls);
    decls[ndecls++] = d;
  }
}

/* Declarations are processed in four passes so that order never matters:
 * type names, then constructor field types (which may name any type), then
 * function signatures, then function bodies (which may call any function). */
static Fn *check_program(void) {
  volatile int i;

  for (i = 0; i < ndecls; i++)
    if (sym_is(decls[i]->items[0], "data"))
      WITH_RECOVERY(collect_data_names(decls[i]));

  for (i = 0; i < ndatas; i++) WITH_RECOVERY(collect_ctors(datas[i]));

  for (i = 0; i < ndatas; i++)
    if (datas[i]->nctors == 0)
      record(datas[i]->pos, "data type '%s' has no usable constructors",
             datas[i]->name);

  for (i = 0; i < ndecls; i++)
    if (sym_is(decls[i]->items[0], "def")) WITH_RECOVERY(collect_fn(decls[i]));

  for (i = 0; i < nfns; i++) WITH_RECOVERY(check_fn_body(fns[i]));

  return find_fn("main");
}

static int main_ret_kind(Fn *m) {
  if (ty_eq(m->ret, T_INT)) return L0_RET_INT;
  if (ty_eq(m->ret, T_BOOL)) return L0_RET_BOOL;
  if (m->ret->kind == TY_LIST && m->ret->elem->kind == TY_INT)
    return L0_RET_LIST;
  return -1;
}

typedef struct {
  Fn *main_fn;
} RunArgs;

static int run_main(void *p) {
  RunArgs *ra = (RunArgs *)p;
  Fn *m = ra->main_fn;
  l0_val input = l0_read_stdin_list();

  int n = m->nslots > 0 ? m->nslots : 1;
  l0_val frame[n];
  frame[0] = input;
  l0_val result = eval(m->body, frame);

  l0_write_result(result, main_ret_kind(m));
  return 0;
}

static void usage(void) {
  fputs(
      "usage: l0i check FILE...   type check only\n"
      "       l0i run   FILE...   type check, then run main on stdin\n",
      stderr);
}

int main(int argc, char **argv) {
  if (argc < 3) {
    usage();
    return 2;
  }
  int running;
  if (strcmp(argv[1], "check") == 0)
    running = 0;
  else if (strcmp(argv[1], "run") == 0)
    running = 1;
  else {
    usage();
    return 2;
  }

  for (int i = 2; i < argc; i++) read_file(argv[i]);

  if (ndecls == 0) {
    fprintf(stderr, "l0i: no declarations found\n");
    return 1;
  }

  Fn *m = check_program();
  if (error_count > 0) return 1;

  if (!running) return 0;

  if (m == NULL) {
    fprintf(stderr, "l0i: this program has no 'main' function\n");
    return 1;
  }
  if (m->nparams != 1 || m->ptypes[0]->kind != TY_LIST ||
      m->ptypes[0]->elem->kind != TY_INT) {
    fprintf(stderr,
            "%s:%d:%d: error: main must take one parameter of type (list int)\n",
            m->pos.file, m->pos.line, m->pos.col);
    return 1;
  }
  if (main_ret_kind(m) < 0) {
    fprintf(stderr,
            "%s:%d:%d: error: main must return (list int), int, or bool, not %s\n",
            m->pos.file, m->pos.line, m->pos.col, ty_str(m->ret));
    return 1;
  }

  l0_arena_init();
  RunArgs ra;
  ra.main_fn = m;
  return l0_run_on_big_stack(run_main, &ra);
}
