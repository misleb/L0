; Validates: data block allocation, tag dispatch via switch, field access.
;
; Equivalent L0:
;   (data Shape (Circle int) (Rect int int))
;   (def area ((s Shape)) int
;     (match s ((Circle r) (mul 3 (mul r r))) ((Rect w h) (mul w h))))
;   (def main ((input (list int))) int (area (Rect 6 7)))
;
; Tags are declaration order, so Circle is 0 and Rect is 1. The default switch
; label is unreachable because match is proved exhaustive at compile time.

declare i64 @l0_data_new(i64, i64)
declare void @l0_data_set(i64, i64, i64)
declare i64 @l0_data_tag(i64)
declare i64 @l0_data_get(i64, i64)

@l0_main_ret_kind = global i64 0

define i64 @l0_f_area(i64 %s.arg) {
entry:
  %s = alloca i64
  store i64 %s.arg, ptr %s
  %0 = load i64, ptr %s
  %tag = call i64 @l0_data_tag(i64 %0)
  switch i64 %tag, label %nomatch [
    i64 0, label %arm.Circle
    i64 1, label %arm.Rect
  ]

arm.Circle:
  %1 = load i64, ptr %s
  %r = call i64 @l0_data_get(i64 %1, i64 0)
  %2 = mul i64 %r, %r
  %3 = mul i64 3, %2
  ret i64 %3

arm.Rect:
  %4 = load i64, ptr %s
  %w = call i64 @l0_data_get(i64 %4, i64 0)
  %5 = load i64, ptr %s
  %h = call i64 @l0_data_get(i64 %5, i64 1)
  %6 = mul i64 %w, %h
  ret i64 %6

nomatch:
  unreachable
}

define i64 @l0_f_main(i64 %input) {
entry:
  %0 = call i64 @l0_data_new(i64 1, i64 2)
  call void @l0_data_set(i64 %0, i64 0, i64 6)
  call void @l0_data_set(i64 %0, i64 1, i64 7)
  %1 = call i64 @l0_f_area(i64 %0)
  ret i64 %1
}
