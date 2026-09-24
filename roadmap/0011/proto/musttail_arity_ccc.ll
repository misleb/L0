; Mutual recursion between a 3-argument and a 2-argument function, in the
; direct-return shape, with musttail under the C convention. The verifier
; rejects it: "cannot guarantee tail call due to mismatched parameter counts".

define internal i64 @ping(i64 %n, i64 %acc, i64 %k) {
entry:
  %c = icmp eq i64 %n, 0
  br i1 %c, label %done, label %more
done:
  ret i64 %acc
more:
  %n1 = sub i64 %n, 1
  %a1 = add i64 %acc, %k
  %r = musttail call i64 @pong(i64 %n1, i64 %a1)
  ret i64 %r
}

define internal i64 @pong(i64 %n, i64 %acc) {
entry:
  %c = icmp eq i64 %n, 0
  br i1 %c, label %done, label %more
done:
  ret i64 %acc
more:
  %n1 = sub i64 %n, 1
  %r = musttail call i64 @ping(i64 %n1, i64 %acc, i64 1)
  ret i64 %r
}

define i64 @entry(i64 %n) {
  %r = call i64 @ping(i64 %n, i64 0, i64 1)
  ret i64 %r
}
