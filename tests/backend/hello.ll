; Validates: cons, byte-list output, ret_kind 2, the @l0_f_<name> symbol rule.
;
; Equivalent L0:
;   (def main ((input (list int))) (list int) "hi\n")
;
; A string literal is a cons chain built back to front, so the last byte is
; consed first.

declare i64 @l0_cons(i64, i64)

@l0_main_ret_kind = global i64 2

define i64 @l0_f_main(i64 %input) {
entry:
  %0 = call i64 @l0_cons(i64 10, i64 0)     ; "\n" onto the empty list
  %1 = call i64 @l0_cons(i64 105, i64 %0)   ; "i"
  %2 = call i64 @l0_cons(i64 104, i64 %1)   ; "h"
  ret i64 %2
}
