; Validates: bool output (ret_kind 1) and the i1-to-i64 widening convention.
;
; Equivalent L0:
;   (def main ((input (list int))) bool (not (is_empty input)))
;
; not compiles to xor with 1, per spec section 10.3.

declare i64 @l0_is_empty(i64)

@l0_main_ret_kind = global i64 1

define i64 @l0_f_main(i64 %input) {
entry:
  %0 = call i64 @l0_is_empty(i64 %input)
  %1 = xor i64 %0, 1
  ret i64 %1
}
