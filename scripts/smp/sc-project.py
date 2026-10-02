#!/usr/bin/env python3
"""sc-project.py — single-core projection: strip `#if defined(OS_USE_SMP_SCHEDULER)`
(and `#ifdef OS_USE_SMP_SCHEDULER`) blocks, keeping any `#else` branch, exactly as
`unifdef -UOS_USE_SMP_SCHEDULER` would, but with no external dependency.

Only the named macro is resolved (default OS_USE_SMP_SCHEDULER); every other
preprocessor directive is passed through verbatim. Nesting is handled.

    sc-project.py < in > out
    sc-project.py FILE            # in place
    MACRO=OS_FOO sc-project.py …  # different macro
"""
import os, re, sys

MACRO = os.environ.get("MACRO", "OS_USE_SMP_SCHEDULER")
# Controlling directives that are FALSE on a single core (their if-branch is
# dropped, any #else kept):
#   * #if defined(OS_USE_SMP_SCHEDULER) / #ifdef OS_USE_SMP_SCHEDULER
#   * #if defined(OS_INTEGER_RTOS_PORT_NCPU) && (OS_INTEGER_RTOS_PORT_NCPU > 1)
#     — the multi-core (NCPU>1) gate; single core is NCPU == 1.
OURS_PATTERNS = [
    r'^\s*#\s*if(?:def)?\s+(?:defined\s*\(\s*)?' + re.escape(MACRO) + r'\b',
    r'^\s*#\s*if\s+defined\s*\(\s*OS_INTEGER_RTOS_PORT_NCPU\s*\).*OS_INTEGER_RTOS_PORT_NCPU\s*>\s*1',
]
RE_IF_OURS = re.compile('|'.join('(?:%s)' % p for p in OURS_PATTERNS))
RE_IF_ANY  = re.compile(r'^\s*#\s*if(?:n?def)?\b')
RE_ELSE    = re.compile(r'^\s*#\s*else\b')
RE_ELIF    = re.compile(r'^\s*#\s*elif\b')
RE_ENDIF   = re.compile(r'^\s*#\s*endif\b')

def project(lines):
    # stack frames: {'ours':bool, 'active':bool}
    #   active = whether the CURRENT branch of this frame is kept
    stack = []
    emitting = lambda: all(f['active'] for f in stack)
    out = []
    for line in lines:
        if RE_IF_OURS.match(line):
            # macro undefined -> if-branch is dropped; a later #else is kept.
            stack.append({'ours': True, 'active': False})
            continue                          # drop the directive itself
        if RE_IF_ANY.match(line):
            parent = emitting()
            if parent:
                out.append(line)              # pass the foreign directive through
            stack.append({'ours': False, 'active': parent})
            continue
        if RE_ELIF.match(line):
            top = stack[-1] if stack else None
            if top and top['ours']:
                # `#elif` on our macro: our macro stays undefined -> still dropped.
                top['active'] = False
                continue
            if emitting_parent(stack):
                out.append(line)
            continue
        if RE_ELSE.match(line):
            top = stack[-1] if stack else None
            if top and top['ours']:
                top['active'] = not top['active']   # flip to the (kept) else branch
                continue
            if emitting_parent(stack):
                out.append(line)
            continue
        if RE_ENDIF.match(line):
            top = stack.pop() if stack else None
            if top and top['ours']:
                continue                      # drop our #endif
            if emitting():
                out.append(line)
            continue
        if emitting():
            out.append(line)
    return out

def emitting_parent(stack):
    # all frames active except the top one (for a foreign #else/#elif directive)
    return all(f['active'] for f in stack[:-1])

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    if args:
        for path in args:
            with open(path) as f:
                res = project(f.readlines())
            with open(path, 'w') as f:
                f.writelines(res)
    else:
        sys.stdout.writelines(project(sys.stdin.readlines()))

if __name__ == "__main__":
    main()
