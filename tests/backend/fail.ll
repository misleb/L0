; Validates: a runtime error exits 70, writes one line to stderr, and produces
; no stdout even though main would otherwise have returned output.
;
; Equivalent L0:
;   (def main ((input (list int))) (list int) (cons (head (nil int)) "x"))

declare i64 @l0_cons(i64, i64)
declare i64 @l0_head(i64)

@l0_main_ret_kind = global i64 2

define i64 @l0_f_main(i64 %input) {
entry:
  %0 = call i64 @l0_cons(i64 120, i64 0)   ; "x", never written
  %1 = call i64 @l0_head(i64 0)            ; head of the empty list: error
  %2 = call i64 @l0_cons(i64 %1, i64 %0)
  ret i64 %2
}
