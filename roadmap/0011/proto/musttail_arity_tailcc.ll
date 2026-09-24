; The same mutual recursion as musttail_arity_ccc.ll, with both functions
; under tailcc. The prototypes still differ, and the verifier accepts it,
; because tailcc lifts musttail's prototype-matching rule (the callee pops
; its own stack arguments). The entry function stays ccc and makes an
; ordinary call, as the runtime's call to @l0_f_main would.

define internal tailcc i64 @ping(i64 %n, i64 %acc, i64 %k) {
entry:
  %c = icmp eq i64 %n, 0
  br i1 %c, label %done, label %more
done:
  ret i64 %acc
more:
  %n1 = sub i64 %n, 1
  %a1 = add i64 %acc, %k
  %r = musttail call tailcc i64 @pong(i64 %n1, i64 %a1)
  ret i64 %r
}

define internal tailcc i64 @pong(i64 %n, i64 %acc) {
entry:
  %c = icmp eq i64 %n, 0
  br i1 %c, label %done, label %more
done:
  ret i64 %acc
more:
  %n1 = sub i64 %n, 1
  %r = musttail call tailcc i64 @ping(i64 %n1, i64 %acc, i64 1)
  ret i64 %r
}

define i64 @entry(i64 %n) {
  %r = call tailcc i64 @ping(i64 %n, i64 0, i64 1)
  ret i64 %r
}
