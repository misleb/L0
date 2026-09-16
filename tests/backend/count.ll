; Validates: recursion, is_empty/tail, alloca-based locals, int output.
;
; Equivalent L0:
;   (def count ((xs (list int))) int
;     (if (is_empty xs) 0 (add 1 (count (tail xs)))))
;   (def main ((input (list int))) int (count input))
;
; Locals are alloca slots rather than hand-built phi nodes, which is the style
; spec section 10.4 permits and the eventual compiler is expected to use.

declare i64 @l0_is_empty(i64)
declare i64 @l0_tail(i64)

@l0_main_ret_kind = global i64 0

define i64 @l0_f_count(i64 %xs.arg) {
entry:
  %xs = alloca i64
  store i64 %xs.arg, ptr %xs
  %0 = load i64, ptr %xs
  %1 = call i64 @l0_is_empty(i64 %0)
  %2 = icmp ne i64 %1, 0
  br i1 %2, label %then, label %else

then:
  ret i64 0

else:
  %3 = load i64, ptr %xs
  %4 = call i64 @l0_tail(i64 %3)
  %5 = call i64 @l0_f_count(i64 %4)
  %6 = add i64 1, %5
  ret i64 %6
}

define i64 @l0_f_main(i64 %input) {
entry:
  %0 = call i64 @l0_f_count(i64 %input)
  ret i64 %0
}
