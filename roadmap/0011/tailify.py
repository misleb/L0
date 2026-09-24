#!/usr/bin/env python3
"""Prototype the tail-call options as rewrites of IR the L0 compiler emitted.

This stands in for changes to compiler/emit.l0, so each option can be tried on
real output, including the compiler's own, before anyone edits the emitter.
Every rewrite is a pure function of the input text, as the emitter's output
must be (spec 10.4).

Usage: tailify.py [OPTIONS] < in.ll > out.ll

  --ret-direct   In a branch that stores a value into a join slot and jumps
                 to a block that only loads the slot and returns it, return
                 the value directly instead. Repeated to a fixpoint, so nested
                 if/match joins collapse too. (option 4)
  --tail         Mark every call to an L0 function that is immediately
                 followed by a ret of its result with `tail`. (option 2)
  --musttail     Same, with `musttail`, keeping the C convention. (option 1)
  --musttail-same-arity
                 `musttail` only where caller and callee have the same
                 number of parameters, `tail` elsewhere: the most the C
                 convention allows. (option 1)
  --tailcc       Give every internal L0 function the tailcc convention and
                 mark its tail calls `musttail`. @l0_f_main stays ccc because
                 the runtime calls it. (option 1, tailcc variant)
  --pad-arity    Give every internal L0 function the same number of i64
                 parameters, the largest arity in the module, so that with
                 --musttail every tail call between them has matching
                 prototypes under the C convention. (option 1, uniform
                 convention)
  --selfloop     Turn self-recursive tail calls into a branch back to a loop
                 header, after moving the parameters into alloca slots.
                 (option 3)
  --no-hoist     With --selfloop, leave the if/match join allocas where the
                 emitter put them, which is inside the loop.
  --noinline     Add `noinline` to every L0 function, to model a program
                 large enough that its recursive functions are not inlined.
"""
import re
import sys

DEFINE = re.compile(r'^define (internal )?i64 @(l0_[fp]_\w+)\(([^)]*)\)(.*)\{$')
LABEL = re.compile(r'^([A-Za-z_][\w.]*):$')
CALL = re.compile(r'^  (%[\w.]+) = call i64 @(l0_[fp]_\w+)\((.*)\)$')
RET = re.compile(r'^  ret i64 (\S+)$')
STORE = re.compile(r'^  store i64 (\S+), ptr (%[\w.]+)$')
BR = re.compile(r'^  br label %([\w.]+)$')
LOAD = re.compile(r'^  (%[\w.]+) = load i64, ptr (%[\w.]+)$')
ALLOCA = re.compile(r'^  %[\w.]+ = alloca i64$')


def split_functions(lines):
    """Yield ('text', [lines]) and ('fn', [lines]) chunks in order."""
    out, cur, infn = [], [], False
    for ln in lines:
        if not infn and DEFINE.match(ln):
            if cur:
                out.append(('text', cur))
            cur, infn = [ln], True
        elif infn and ln == '}':
            cur.append(ln)
            out.append(('fn', cur))
            cur, infn = [], False
        else:
            cur.append(ln)
    if cur:
        out.append(('text', cur))
    return out


def blocks_of(fn):
    """Header line, list of (label, [instrs]), closing line."""
    head, body, tail = fn[0], fn[1:-1], fn[-1]
    blocks, label, instrs = [], None, []
    for ln in body:
        m = LABEL.match(ln)
        if m:
            if label is not None:
                blocks.append((label, instrs))
            label, instrs = m.group(1), []
        else:
            instrs.append(ln)
    blocks.append((label, instrs))
    return head, blocks, tail


def join_blocks(head, blocks, tail):
    out = [head]
    for label, instrs in blocks:
        out.append(label + ':')
        out.extend(instrs)
    out.append(tail)
    return out


def ret_direct(fn):
    head, blocks, tail = blocks_of(fn)
    changed = True
    while changed:
        changed = False
        retjoin = {}
        for label, ins in blocks:
            if len(ins) == 2:
                ml, mr = LOAD.match(ins[0]), RET.match(ins[1])
                if ml and mr and mr.group(1) == ml.group(1):
                    retjoin[label] = ml.group(2)
        for i, (label, ins) in enumerate(blocks):
            if len(ins) >= 2:
                ms, mb = STORE.match(ins[-2]), BR.match(ins[-1])
                if ms and mb and retjoin.get(mb.group(1)) == ms.group(2):
                    blocks[i] = (label, ins[:-2] + ['  ret i64 ' + ms.group(1)])
                    changed = True
        # Drop join blocks nothing branches to any more.
        text = '\n'.join(l for _, ins in blocks for l in ins)
        kept = [blocks[0]]
        for label, ins in blocks[1:]:
            if ('%' + label + ',') in text or ('%' + label + ' ') in text \
                    or text.endswith('%' + label) or ('%' + label + '\n') in text:
                kept.append((label, ins))
            else:
                changed = True
        blocks = kept
    return join_blocks(head, blocks, tail)


def mark_tail(fn, marker, conv_of, caller, arity=None):
    out = list(fn)
    for i in range(len(out) - 1):
        mc, mr = CALL.match(out[i]), RET.match(out[i + 1])
        if mc and mr and mr.group(1) == mc.group(1):
            callee = mc.group(2)
            m = marker
            if marker == 'musttail' and conv_of(callee) != conv_of(caller):
                m = 'tail'
            if arity is not None and arity.get(callee) != arity.get(caller):
                m = 'tail'
            cc = conv_of(callee)
            cc = (cc + ' ') if cc else ''
            out[i] = '  %s = %s call %si64 @%s(%s)' % (
                mc.group(1), m, cc, callee, mc.group(3))
    return out


def set_calling_conv(fn, conv_of):
    out = []
    for ln in fn:
        m = DEFINE.match(ln)
        if m and conv_of(m.group(2)):
            ln = 'define %si64 @%s(%s)%s{' % (
                ('internal ' if m.group(1) else '') + conv_of(m.group(2)) + ' ',
                m.group(2), m.group(3), m.group(4))
        else:
            ln = re.sub(r'(= (?:tail |musttail )?call )i64 @(l0_[fp]_\w+)\(',
                        lambda mm: mm.group(1) + (conv_of(mm.group(2)) + ' ' if conv_of(mm.group(2)) else '')
                        + 'i64 @' + mm.group(2) + '(', ln)
        out.append(ln)
    return out


def self_loop(fn, hoist):
    m = DEFINE.match(fn[0])
    name, params = m.group(2), m.group(3)
    pnames = re.findall(r'i64 (%a\d+)', params)
    head, blocks, tail = blocks_of(fn)
    has_self = any(
        CALL.match(ins[k]) and CALL.match(ins[k]).group(2) == name and
        k + 1 < len(ins) and RET.match(ins[k + 1]) and
        RET.match(ins[k + 1]).group(1) == CALL.match(ins[k]).group(1)
        for _, ins in blocks for k in range(len(ins)))
    if not has_self or not pnames:
        return fn
    head = head.replace(params, ', '.join('i64 %s.in' % p for p in pnames))
    entry_label, entry = blocks[0]
    # Entry keeps the stack check; the loop header reloads the parameters.
    pre = [entry[0]]
    rest = entry[1:]
    pre += ['  %%p%s = alloca i64' % p[2:] for p in pnames]
    pre += ['  store i64 %s.in, ptr %%p%s' % (p, p[2:]) for p in pnames]
    hoisted = []
    if hoist:
        newblocks = []
        for label, ins in [('loop.body', rest)] + blocks[1:]:
            keep = []
            for ln in ins:
                (hoisted if ALLOCA.match(ln) else keep).append(ln)
            newblocks.append((label, keep))
    else:
        newblocks = [('loop.body', rest)] + blocks[1:]
    pre += hoisted + ['  br label %loop.head']
    head_block = ('loop.head', ['  %s = load i64, ptr %%p%s' % (p, p[2:]) for p in pnames]
                  + ['  br label %loop.body'])
    out_blocks = [(entry_label, pre), head_block]
    for label, ins in newblocks:
        new = []
        k = 0
        while k < len(ins):
            mc = CALL.match(ins[k])
            mr = RET.match(ins[k + 1]) if k + 1 < len(ins) else None
            if mc and mr and mc.group(2) == name and mr.group(1) == mc.group(1):
                args = re.findall(r'i64 ([^,]+)', mc.group(3))
                new += ['  store i64 %s, ptr %%p%s' % (a.strip(), p[2:])
                        for a, p in zip(args, pnames)]
                new.append('  br label %loop.head')
                k += 2
            else:
                new.append(ins[k])
                k += 1
        out_blocks.append((label, new))
    return join_blocks(head, out_blocks, tail)


def pad_arity(fn, k, is_internal):
    """Every internal L0 function takes exactly k i64 parameters; calls to
    them pass 0 for the ones they do not use."""
    out = []
    for ln in fn:
        m = DEFINE.match(ln)
        if m and is_internal(m.group(2)):
            ps = [p.strip() for p in m.group(3).split(',') if p.strip()]
            ps += ['i64 %%pad%d' % i for i in range(len(ps), k)]
            ln = 'define %si64 @%s(%s)%s{' % (
                'internal ' if m.group(1) else '', m.group(2), ', '.join(ps), m.group(4))
        else:
            def fix(mm):
                if not is_internal(mm.group(2)):
                    return mm.group(0)
                args = [a.strip() for a in mm.group(3).split(',') if a.strip()]
                args += ['i64 0'] * (k - len(args))
                return mm.group(1) + '@' + mm.group(2) + '(' + ', '.join(args) + ')'
            ln = re.sub(r'(call (?:tailcc )?i64 )@(l0_[fp]_\w+)\(([^)]*)\)', fix, ln)
        out.append(ln)
    return out


def pad_to(fn, padded):
    """Like pad_arity, but each function to its own padded arity."""
    out = []
    for ln in fn:
        m = DEFINE.match(ln)
        if m:
            ps = [p.strip() for p in m.group(3).split(',') if p.strip()]
            ps += ['i64 %%pad%d' % i for i in range(len(ps), padded[m.group(2)])]
            ln = 'define %si64 @%s(%s)%s{' % (
                'internal ' if m.group(1) else '', m.group(2), ', '.join(ps), m.group(4))
        else:
            def fix(mm):
                args = [a.strip() for a in mm.group(3).split(',') if a.strip()]
                args += ['i64 0'] * (padded.get(mm.group(2), len(args)) - len(args))
                return mm.group(1) + '@' + mm.group(2) + '(' + ', '.join(args) + ')'
            ln = re.sub(r'(call (?:tailcc )?i64 )@(l0_[fp]_\w+)\(([^)]*)\)', fix, ln)
        out.append(ln)
    return out


def tail_edges(chunks):
    """(caller, callee) for every call immediately followed by a ret of it,
    after --ret-direct has been applied to each function."""
    edges = []
    for kind, fn in chunks:
        if kind != 'fn':
            continue
        caller = DEFINE.match(fn[0]).group(2)
        for i in range(len(fn) - 1):
            mc, mr = CALL.match(fn[i]), RET.match(fn[i + 1])
            if mc and mr and mr.group(1) == mc.group(1):
                edges.append((caller, mc.group(2)))
    return edges


def component_arity(arity, edges):
    """Each function's padded arity: the largest arity in its connected
    component of the tail-call graph, main excluded. Union-find over names
    in sorted order, so the result does not depend on iteration order."""
    parent = {s: s for s in arity}

    def find(s):
        while parent[s] != s:
            parent[s] = parent[parent[s]]
            s = parent[s]
        return s
    for a, b in edges:
        if 'l0_f_main' in (a, b) or a not in parent or b not in parent:
            continue
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)
    best = {}
    for s in sorted(arity):
        r = find(s)
        best[r] = max(best.get(r, 0), arity[s])
    return {s: (arity[s] if s == 'l0_f_main' else best[find(s)]) for s in arity}


def main():
    opts = set(sys.argv[1:])
    lines = sys.stdin.read().split('\n')
    tailcc = '--tailcc' in opts

    def conv_of(sym):
        return 'tailcc' if tailcc and sym != 'l0_f_main' else ''

    chunks = split_functions(lines)
    arity = {}
    for kind, chunk in chunks:
        if kind == 'fn':
            m = DEFINE.match(chunk[0])
            arity[m.group(2)] = len(re.findall(r'i64 %', m.group(3)))
    if '--ret-direct' in opts:
        chunks = [(k, ret_direct(c) if k == 'fn' else c) for k, c in chunks]
    if '--pad-component' in opts:
        padded = component_arity(arity, tail_edges(chunks))
        grown = sorted(s for s in arity if padded[s] != arity[s])
        sys.stderr.write('pad-component: %d of %d functions padded, extra params %d\n'
                         % (len(grown), len(arity), sum(padded[s] - arity[s] for s in arity)))
    out = []
    for kind, chunk in chunks:
        if kind == 'text':
            out.extend(chunk)
            continue
        fn = chunk
        caller = DEFINE.match(fn[0]).group(2)
        if '--selfloop' in opts:
            fn = self_loop(fn, '--no-hoist' not in opts)
        if '--pad-component' in opts:
            fn = mark_tail(fn, 'musttail', conv_of, caller, padded)
        elif '--pad-arity' in opts and '--musttail' in opts:
            padded = {s: (a if s == 'l0_f_main' else max(arity.values()))
                      for s, a in arity.items()}
            fn = mark_tail(fn, 'musttail', conv_of, caller, padded)
        elif '--musttail-same-arity' in opts:
            fn = mark_tail(fn, 'musttail', conv_of, caller, arity)
        elif '--musttail' in opts or tailcc:
            fn = mark_tail(fn, 'musttail', conv_of, caller)
        elif '--tail' in opts:
            fn = mark_tail(fn, 'tail', conv_of, caller)
        if tailcc:
            fn = set_calling_conv(fn, conv_of)
        if '--pad-component' in opts:
            fn = pad_to(fn, padded)
        elif '--pad-arity' in opts:
            k = max(arity.values())
            fn = pad_arity(fn, k, lambda s: s != 'l0_f_main')
        if '--noinline' in opts:
            fn[0] = fn[0][:-1] + 'noinline {' if fn[0].endswith(' {') else fn[0]
        out.extend(fn)
    sys.stdout.write('\n'.join(out))


if __name__ == '__main__':
    main()
