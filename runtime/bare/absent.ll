; absent.ll -- the host functions of a host without an operating system, as
; a host that lacks each facility gives them (spec section 9.2), so that a
; host's own files define only what it has.
;
; Every target's manifest links this. Each definition is weak: a part that
; defines the same function replaces it when the parts are linked into the
; program's module, before anything is optimized, and where none does, the
; facility is absent as section 9.2 says. A new host function gets its
; absent definition here, and then only the hosts that have the facility
; touch it. host-libc.ll, the host under an operating system, is linked
; outside the manifests and keeps its own.

; ---------------------------------------------------------------- streams

; No stream but the standard three is ever open, and those are not closed.
define weak i64 @l0_host_close(i64 %s) {
entry:
  ret i64 -5
}

; ------------------------------------------------------------------ files

; An empty file system, not even a directory, in which nothing can be made:
; a file to read is not there, -3, and one to write has no directory, -9.
define weak i64 @l0_host_open(ptr %path, i64 %mode) {
entry:
  %rd = icmp eq i64 %mode, 1
  %r = select i1 %rd, i64 -3, i64 -9
  ret i64 %r
}

define weak i64 @l0_host_rename(ptr %from, ptr %to) {
entry:
  ret i64 -3
}

define weak i64 @l0_host_remove(ptr %path) {
entry:
  ret i64 -3
}

; ------------------------------------------------------------ environment

; No environment: every setting is unset.
define weak ptr @l0_host_setting(ptr %name) {
entry:
  ret ptr null
}

; ------------------------------------------------------------ a kernel

; No kernel beneath the program (spec section 6.15).
define weak i64 @l0_host_supervisor(i64 %n, i64 %a, i64 %b, i64 %c) {
entry:
  ret i64 -3
}

; ---------------------------------------------------------------- a board

; No board to reset (spec section 6.12).
define weak i64 @l0_host_board_reset() {
entry:
  ret i64 -3
}

; ------------------------------------------------------------- user mode

; No user mode, so no space or frame is ever made, and anything given one
; is told 1, not a space, or for a frame's address, syncing, or freeing 2,
; not a frame (spec section 6.13).
define weak i64 @l0_host_space_new() {
entry:
  ret i64 -3
}

define weak i64 @l0_host_frame_new() {
entry:
  ret i64 -3
}

define weak i64 @l0_host_frame_address(i64 %f) {
entry:
  ret i64 2
}

define weak i64 @l0_host_frame_sync(i64 %f, i64 %dir) {
entry:
  ret i64 2
}

define weak i64 @l0_host_frame_free(i64 %f) {
entry:
  ret i64 2
}

define weak i64 @l0_host_frame_free_count() {
entry:
  ret i64 -3
}

define weak i64 @l0_host_space_unmap(i64 %s, i64 %va) {
entry:
  ret i64 1
}

define weak i64 @l0_host_space_free(i64 %s) {
entry:
  ret i64 1
}

define weak i64 @l0_host_space_map(i64 %s, i64 %va, i64 %f, i64 %perm) {
entry:
  ret i64 1
}

define weak i64 @l0_host_space_map_device(i64 %s, i64 %va, i64 %base, i64 %len) {
entry:
  ret i64 1
}

define weak i64 @l0_host_space_copy(i64 %s, i64 %va, ptr %buf, i64 %n, i64 %dir) {
entry:
  ret i64 1
}

define weak i64 @l0_host_user_run(i64 %s, ptr %words, i64 %n) {
entry:
  ret i64 1
}

; ------------------------------------------------------------ other CPUs

; No CPU but the program's runs threads (spec section 6.18): a thread
; handed to one is told 11, not a CPU, none is ever trapped, and waiting
; is waiting for an interrupt.
define weak i64 @l0_host_cpu_count() {
entry:
  ret i64 1
}

define weak i64 @l0_host_cpu_run(i64 %c, i64 %s, ptr %words, i64 %n, i64 %deadline, i64 %tag) {
entry:
  ret i64 11
}

define weak i64 @l0_host_cpu_trapped(ptr %out) {
entry:
  ret i64 0
}

define weak i64 @l0_host_cpu_wait() {
entry:
  %r = call i64 @l0_host_interrupt_wait()
  ret i64 %r
}

; ------------------------------------------------------------ interrupts

; No interrupts: none is ever taken, and ending one is told 8, interrupt
; not taken (spec section 6.14).
define weak i64 @l0_host_timer_at(i64 %t) {
entry:
  ret i64 -3
}

define weak i64 @l0_host_interrupt_enable(i64 %n) {
entry:
  ret i64 -3
}

define weak i64 @l0_host_interrupt_wait() {
entry:
  ret i64 -3
}

define weak i64 @l0_host_interrupt_done(i64 %n) {
entry:
  ret i64 8
}
