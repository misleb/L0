#!/usr/bin/env python3
"""Runs json and python3 -m json.tool --indent 2 on edge cases and reports
where they disagree: one accepting what the other rejects, or different
output. usage: differ.py PATH-TO-json"""
import subprocess
import sys

prog = sys.argv[1]
cases = [
    b'1', b'-0', b'-0.0', b'1.0', b'1.50', b'1E5', b'1e-3', b'0e0', b'1e400',
    b'12345678901234567890123', b'1' * 5000,
    b'NaN', b'Infinity', b'-Infinity',
    b'{"a":1,"b":2,"a":3}',
    b'"\\u0000\\u001f\\u007f\\u0080\\uffff"', b'"\x7f"', b'"\xc3\xa9\xe2\x82\xac"',
    b'"\\ud800"', b'"\\udc00\\ud800"', b'"\\uD834\\uDD1E"',
    b'"\xed\xa0\x80"', b'"\xc0\xaf"', b'"\xf4\x90\x80\x80"', b'"\xff"',
    b'\xef\xbb\xbf{}', b' \t\r\n[ ]\r\n', b'[1,]', b'{"a":1,}', b'[01]', b'[.5]',
    b'[1.]', b'"a\rb"', b'"a\nb"', b'[' * 900 + b']' * 900, b'[' * 5000 + b']' * 5000,
    b'', b'   ', b'nul', b'[true false]', b'{"a" : [ {}, [] , "x" ] }',
]
bad = 0
for c in cases:
    ours = subprocess.run([prog], input=c, capture_output=True)
    theirs = subprocess.run([sys.executable, "-m", "json.tool", "--indent", "2"],
                            input=c, capture_output=True)
    ok_o, ok_t = ours.returncode == 0, theirs.returncode == 0
    label = repr(c if len(c) < 40 else c[:20] + b'...(%d bytes)' % len(c))
    if ok_o != ok_t:
        bad += 1
        print("ACCEPTS DIFFER", label, "json:", ok_o, "json.tool:", ok_t)
        print("   json:", (ours.stdout or ours.stderr)[:80])
        last = (theirs.stderr.splitlines() or [b""])[-1]
        print("   tool:", (theirs.stdout if ok_t else last)[:80])
    elif ok_o and ours.stdout != theirs.stdout:
        bad += 1
        print("OUTPUT DIFFERS", label)
        print("   json:", ours.stdout[:80])
        print("   tool:", theirs.stdout[:80])
print(len(cases), "cases,", bad, "differences")
