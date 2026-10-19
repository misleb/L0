; elf.ll -- the harness kernels' loader for a process's image, the ELF of
; spec section 10.3, linked beside aarch64/kernel.ll and riscv64/kernel.ll
; by boot.sh. It names no machine, and so carries no target triple.
;
; QEMU's loader puts an image's file in a slot of 4 MB as it is, and the
; kernel maps the slot at 0xC0000000. elf_load moves each PT_LOAD's bytes
; from its offset in the file to its address's offset in the slot, zeroes
; each segment past its file bytes, and zeroes the slot from the image's end,
; where the heap starts, so the slot holds the process's memory as the spec
; says a kernel maps it. Pages between segments, of which proc.ld leaves
; none, keep what the file had there. A segment never moves up, since its
; address's offset is at most its file offset, which it checks, so moving
; the segments in order, each a byte at a time upward, never overwrites
; bytes not yet moved. The harness maps the whole slot readable, writable,
; and executable, more than each segment's flags, which the spec allows.
; QEMU keeps no caches, so code moved by stores runs with no maintenance.
;
; The harness's own limit, not the spec's, is the slot: an image whose file
; or memory is over 4 MB is refused.

@base = private constant i64 3221225472                      ; 0xC0000000
@slot = private constant i64 4194304                         ; 4 MB

define internal i64 @rd8(i64 %a) {
  %p = inttoptr i64 %a to ptr
  %v = load i8, ptr %p, align 1
  %w = zext i8 %v to i64
  ret i64 %w
}

define internal i64 @rd16(i64 %a) {
  %p = inttoptr i64 %a to ptr
  %v = load i16, ptr %p, align 1
  %w = zext i16 %v to i64
  ret i64 %w
}

define internal i64 @rd32(i64 %a) {
  %p = inttoptr i64 %a to ptr
  %v = load i32, ptr %p, align 1
  %w = zext i32 %v to i64
  ret i64 %w
}

define internal i64 @rd64(i64 %a) {
  %p = inttoptr i64 %a to ptr
  %v = load i64, ptr %p, align 1
  ret i64 %v
}

; Copies the n bytes from src to dst, at or below src, upward, so that it
; is right where the two overlap.
define internal void @move_down(i64 %dst, i64 %src, i64 %n) #0 {
entry:
  %none = icmp eq i64 %n, 0
  br i1 %none, label %done, label %loop
loop:
  %o = phi i64 [ 0, %entry ], [ %o1, %loop ]
  %s = add i64 %src, %o
  %sp = inttoptr i64 %s to ptr
  %b = load i8, ptr %sp
  %d = add i64 %dst, %o
  %dp = inttoptr i64 %d to ptr
  store i8 %b, ptr %dp
  %o1 = add i64 %o, 1
  %more = icmp ult i64 %o1, %n
  br i1 %more, label %loop, label %done
done:
  ret void
}

define internal void @zero(i64 %a, i64 %n) #0 {
entry:
  %none = icmp eq i64 %n, 0
  br i1 %none, label %done, label %loop
loop:
  %o = phi i64 [ 0, %entry ], [ %o1, %loop ]
  %d = add i64 %a, %o
  %dp = inttoptr i64 %d to ptr
  store i8 0, ptr %dp
  %o1 = add i64 %o, 1
  %more = icmp ult i64 %o1, %n
  br i1 %more, label %loop, label %done
done:
  ret void
}

; Whether the program header at ph, a PT_LOAD, may be the next of the
; image's, after one whose address's offset ended at pe and file bytes at
; po: in the slot, page-aligned, not writable and executable, in order, and
; never moving up.
define internal i1 @load_ok(i64 %ph, i64 %pe, i64 %po) {
entry:
  %fl = add i64 %ph, 4
  %f = call i64 @rd32(i64 %fl)
  %wx = and i64 %f, 3                                        ; PF_W | PF_X
  %notwx = icmp ne i64 %wx, 3
  %offp = add i64 %ph, 8
  %off = call i64 @rd64(i64 %offp)
  %vap = add i64 %ph, 16
  %va = call i64 @rd64(i64 %vap)
  %fszp = add i64 %ph, 32
  %fsz = call i64 @rd64(i64 %fszp)
  %mszp = add i64 %ph, 40
  %msz = call i64 @rd64(i64 %mszp)
  %base = load i64, ptr @base
  %slot = load i64, ptr @slot
  %above = icmp uge i64 %va, %base
  %dest = sub i64 %va, %base
  %dlow = and i64 %dest, 4095
  %olow = and i64 %off, 4095
  %dal = icmp eq i64 %dlow, 0
  %oal = icmp eq i64 %olow, 0
  %fits = icmp ule i64 %fsz, %msz
  %mok = icmp ule i64 %msz, %slot
  %mroom = sub i64 %slot, %msz
  %din = icmp ule i64 %dest, %mroom
  %fok = icmp ule i64 %fsz, %slot
  %froom = sub i64 %slot, %fsz
  %oin = icmp ule i64 %off, %froom
  %down = icmp ule i64 %dest, %off
  %after = icmp uge i64 %dest, %pe
  %oafter = icmp uge i64 %off, %po
  %a0 = and i1 %notwx, %above
  %a1 = and i1 %a0, %dal
  %a2 = and i1 %a1, %oal
  %a3 = and i1 %a2, %fits
  %a4 = and i1 %a3, %mok
  %a5 = and i1 %a4, %din
  %a6 = and i1 %a5, %fok
  %a7 = and i1 %a6, %oin
  %a8 = and i1 %a7, %down
  %a9 = and i1 %a8, %after
  %a10 = and i1 %a9, %oafter
  ret i1 %a10
}

; The entry point of the image in the slot at pa, once its segments are in
; place, if it is an ELF for the machine numbered machine (EM_AARCH64, 183,
; or EM_RISCV, 243); or -1, with nothing moved, if it is not an ELF this
; harness can load.
define i64 @elf_load(i64 %pa, i64 %machine) {
entry:
  %loads = alloca [3 x [4 x i64]]
  %n = alloca i64
  %pe = alloca i64
  %po = alloca i64
  %k = alloca i64
  %base = load i64, ptr @base
  %slot = load i64, ptr @slot
  %magic = call i64 @rd32(i64 %pa)
  %elf = icmp eq i64 %magic, 1179403647                     ; "\7FELF"
  br i1 %elf, label %header, label %bad
header:
  %c0 = add i64 %pa, 4
  %class = call i64 @rd8(i64 %c0)
  %d0 = add i64 %pa, 5
  %data = call i64 @rd8(i64 %d0)
  %t0 = add i64 %pa, 16
  %type = call i64 @rd16(i64 %t0)
  %m0 = add i64 %pa, 18
  %mach = call i64 @rd16(i64 %m0)
  %s0 = add i64 %pa, 54
  %phent = call i64 @rd16(i64 %s0)
  %n0 = add i64 %pa, 56
  %phnum = call i64 @rd16(i64 %n0)
  %p0 = add i64 %pa, 32
  %phoff = call i64 @rd64(i64 %p0)
  %h0 = icmp eq i64 %class, 2                                ; ELFCLASS64
  %h1 = icmp eq i64 %data, 1                                 ; little endian
  %h2 = icmp eq i64 %type, 2                                 ; ET_EXEC
  %h3 = icmp eq i64 %mach, %machine
  %h4 = icmp eq i64 %phent, 56
  %h5 = icmp ule i64 %phnum, 16
  %h6 = icmp ule i64 %phoff, %slot
  %phsz = mul i64 %phnum, 56
  %phend = add i64 %phoff, %phsz
  %h7 = icmp ule i64 %phend, %slot
  %g0 = and i1 %h0, %h1
  %g1 = and i1 %g0, %h2
  %g2 = and i1 %g1, %h3
  %g3 = and i1 %g2, %h4
  %g4 = and i1 %g3, %h5
  %g5 = and i1 %g4, %h6
  %g6 = and i1 %g5, %h7
  store i64 0, ptr %n
  store i64 0, ptr %pe
  store i64 0, ptr %po
  store i64 0, ptr %k
  br i1 %g6, label %scan, label %bad

; Each PT_LOAD, checked and kept, before anything moves, since the first
; segment's place may be where the program headers are.
scan:
  %ki = load i64, ptr %k
  %left = icmp ult i64 %ki, %phnum
  br i1 %left, label %one, label %scanned
one:
  %ko = mul i64 %ki, 56
  %ph0 = add i64 %pa, %phoff
  %ph = add i64 %ph0, %ko
  %pt = call i64 @rd32(i64 %ph)
  %isload = icmp eq i64 %pt, 1                               ; PT_LOAD
  br i1 %isload, label %check, label %skip
check:
  %ni = load i64, ptr %n
  %room = icmp ult i64 %ni, 3
  %pei = load i64, ptr %pe
  %poi = load i64, ptr %po
  %ok = call i1 @load_ok(i64 %ph, i64 %pei, i64 %poi)
  %keep = and i1 %room, %ok
  br i1 %keep, label %kept, label %bad
kept:
  %offp = add i64 %ph, 8
  %off = call i64 @rd64(i64 %offp)
  %vap = add i64 %ph, 16
  %va = call i64 @rd64(i64 %vap)
  %dest = sub i64 %va, %base
  %fszp = add i64 %ph, 32
  %fsz = call i64 @rd64(i64 %fszp)
  %mszp = add i64 %ph, 40
  %msz = call i64 @rd64(i64 %mszp)
  %e0 = getelementptr [3 x [4 x i64]], ptr %loads, i64 0, i64 %ni, i64 0
  store i64 %off, ptr %e0
  %e1 = getelementptr [3 x [4 x i64]], ptr %loads, i64 0, i64 %ni, i64 1
  store i64 %dest, ptr %e1
  %e2 = getelementptr [3 x [4 x i64]], ptr %loads, i64 0, i64 %ni, i64 2
  store i64 %fsz, ptr %e2
  %e3 = getelementptr [3 x [4 x i64]], ptr %loads, i64 0, i64 %ni, i64 3
  store i64 %msz, ptr %e3
  %ni1 = add i64 %ni, 1
  store i64 %ni1, ptr %n
  %pe1 = add i64 %dest, %msz
  store i64 %pe1, ptr %pe
  %po1 = add i64 %off, %fsz
  store i64 %po1, ptr %po
  br label %skip
skip:
  %ki1 = add i64 %ki, 1
  store i64 %ki1, ptr %k
  br label %scan

scanned:
  %en0 = add i64 %pa, 24
  %entryp = call i64 @rd64(i64 %en0)
  %eabove = icmp uge i64 %entryp, %base
  %eoff = sub i64 %entryp, %base
  %ein = icmp ult i64 %eoff, %slot
  %eok = and i1 %eabove, %ein
  %count = load i64, ptr %n
  store i64 0, ptr %k
  br i1 %eok, label %move, label %bad

move:
  %mj = load i64, ptr %k
  %mleft = icmp ult i64 %mj, %count
  br i1 %mleft, label %move1, label %moved
move1:
  %mo = getelementptr [3 x [4 x i64]], ptr %loads, i64 0, i64 %mj, i64 0
  %moff = load i64, ptr %mo
  %md = getelementptr [3 x [4 x i64]], ptr %loads, i64 0, i64 %mj, i64 1
  %mdest = load i64, ptr %md
  %mf = getelementptr [3 x [4 x i64]], ptr %loads, i64 0, i64 %mj, i64 2
  %mfsz = load i64, ptr %mf
  %msrc = add i64 %pa, %moff
  %mdst = add i64 %pa, %mdest
  call void @move_down(i64 %mdst, i64 %msrc, i64 %mfsz)
  %mj1 = add i64 %mj, 1
  store i64 %mj1, ptr %k
  br label %move
moved:
  store i64 0, ptr %k
  br label %bss

bss:
  %bj = load i64, ptr %k
  %bleft = icmp ult i64 %bj, %count
  br i1 %bleft, label %bss1, label %tail
bss1:
  %bd = getelementptr [3 x [4 x i64]], ptr %loads, i64 0, i64 %bj, i64 1
  %bdest = load i64, ptr %bd
  %bf = getelementptr [3 x [4 x i64]], ptr %loads, i64 0, i64 %bj, i64 2
  %bfsz = load i64, ptr %bf
  %bm = getelementptr [3 x [4 x i64]], ptr %loads, i64 0, i64 %bj, i64 3
  %bmsz = load i64, ptr %bm
  %bfrom0 = add i64 %pa, %bdest
  %bfrom = add i64 %bfrom0, %bfsz
  %blen = sub i64 %bmsz, %bfsz
  call void @zero(i64 %bfrom, i64 %blen)
  %bj1 = add i64 %bj, 1
  store i64 %bj1, ptr %k
  br label %bss

; The slot from the image's end, where the heap starts, held the rest of
; the file: its section table and symbols.
tail:
  %end = load i64, ptr %pe
  %tfrom = add i64 %pa, %end
  %tlen = sub i64 %slot, %end
  call void @zero(i64 %tfrom, i64 %tlen)
  ret i64 %entryp
bad:
  ret i64 -1
}

attributes #0 = { "no-builtins" }
