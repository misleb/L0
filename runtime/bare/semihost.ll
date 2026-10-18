; semihost.ll -- standard error and the exit status by semihosting, for a
; board QEMU emulates: the Arm semihosting calls, which QEMU answers for
; RISC-V as for Arm, made by the architecture's own trap instruction,
; @l0_arch_semihost(op, block). It carries no triple. A board's part that
; has no emulator beneath it delivers the two some other way.

declare i64 @l0_arch_semihost(i64, ptr)

; SYS_EXIT with ADP_Stopped_ApplicationExit, whose subcode, the status, QEMU
; makes its own exit status.
define void @l0_semihost_exit(i64 %status) noreturn {
entry:
  %blk = alloca [2 x i64], align 8
  store i64 131110, ptr %blk
  %p1 = getelementptr i64, ptr %blk, i64 1
  store i64 %status, ptr %p1
  %r = call i64 @l0_arch_semihost(i64 24, ptr %blk)
  br label %hang
hang:
  br label %hang
}

@tt = private constant [4 x i8] c":tt\00"
@err_handle = internal global i64 -1

; ":tt" opened in mode 8, "a", is the host's standard error.
define internal i64 @semi_stderr() {
entry:
  %h = load i64, ptr @err_handle
  %have = icmp sge i64 %h, 0
  br i1 %have, label %done, label %open
open:
  %blk = alloca [3 x i64], align 8
  %p0 = ptrtoint ptr @tt to i64
  store i64 %p0, ptr %blk
  %p1 = getelementptr i64, ptr %blk, i64 1
  store i64 8, ptr %p1
  %p2 = getelementptr i64, ptr %blk, i64 2
  store i64 3, ptr %p2
  %n = call i64 @l0_arch_semihost(i64 1, ptr %blk)
  store i64 %n, ptr @err_handle
  br label %done
done:
  %r = phi i64 [ %h, %entry ], [ %n, %open ]
  ret i64 %r
}

; Writes the n bytes at buf on the host's standard error, as l0_host_write
; does: how many, or -5.
define i64 @l0_semihost_err_write(ptr %buf, i64 %n) {
entry:
  %h = call i64 @semi_stderr()
  %blk = alloca [3 x i64], align 8
  store i64 %h, ptr %blk
  %q1 = getelementptr i64, ptr %blk, i64 1
  %bi = ptrtoint ptr %buf to i64
  store i64 %bi, ptr %q1
  %q2 = getelementptr i64, ptr %blk, i64 2
  store i64 %n, ptr %q2
  %unwritten = call i64 @l0_arch_semihost(i64 5, ptr %blk)
  %wrote = sub i64 %n, %unwritten
  %none = icmp sle i64 %wrote, 0
  %r = select i1 %none, i64 -5, i64 %wrote
  ret i64 %r
}
