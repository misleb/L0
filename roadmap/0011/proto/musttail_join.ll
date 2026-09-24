; The shape the emitter produces today for a call in an if branch, with the
; call marked musttail: the call is followed by a store and a branch to the
; join block, not by ret. The verifier rejects it.
;
;   clang -c musttail_join.ll   ->  "musttail call must precede a ret ..."

define internal i64 @loop(i64 %a0, i64 %a1) {
entry:
  %r0 = alloca i64
  %c = icmp eq i64 %a0, 0
  br i1 %c, label %Lt0, label %Le0
Lt0:
  store i64 %a1, ptr %r0
  br label %Lx0
Le0:
  %n = sub i64 %a0, 1
  %acc = add i64 %a1, 1
  %t = musttail call i64 @loop(i64 %n, i64 %acc)
  store i64 %t, ptr %r0
  br label %Lx0
Lx0:
  %v = load i64, ptr %r0
  ret i64 %v
}

define i64 @entry(i64 %n) {
  %r = call i64 @loop(i64 %n, i64 0)
  ret i64 %r
}
