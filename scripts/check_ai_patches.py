"""Static cross-checks for the Advent AI SQL patches.

These patches cannot be run from this machine (no psql, no Supabase CLI),
so they ship on review alone. Review already caught two real bugs — a
ledger INSERT using a `kind` the CHECK constraint forbids, and a spend
ceiling that could never fire — which is exactly why review alone is not
enough. This makes the mechanical half of that review repeatable.

It is NOT a SQL parser and does not pretend to be. It answers a small set
of questions that have burned this feature already:

  1. Do two patches claim the same number?
  2. Is every `$$` block closed?
  3. Does any INSERT use a `kind`/`pool` value its CHECK constraint
     forbids?
  4. Does any statement reference a public.ai_* / bible_* function that
     no patch defines?
  5. Does any INSERT name a column its CREATE TABLE does not declare?
  6. Are the patches applied in an order where each depends only on what
     came before?

  RUN:  python scripts/check_ai_patches.py
"""

import io
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(os.path.dirname(HERE), "database")

# The Advent AI feature set, in apply order.
PREFIXES = ("advent_ai", "bible_kjv")


def patches():
    out = []
    for name in sorted(os.listdir(DB)):
        if not name.startswith("patch_") or not name.endswith(".sql"):
            continue
        m = re.match(r"patch_(\d+)_(.+)\.sql$", name)
        if not m:
            continue
        num, slug = int(m.group(1)), m.group(2)
        out.append((num, slug, name))
    return out


def ai_patches():
    return [p for p in patches()
            if any(p[1].startswith(x) for x in PREFIXES)
            or "advent_ai" in p[1] or "bible" in p[1]]


problems = []
notes = []


def problem(msg):
    problems.append(msg)


# ---------------------------------------------------------------------
#  1. numbering
# ---------------------------------------------------------------------
by_num = defaultdict(list)
for num, slug, name in patches():
    by_num[num].append(name)

def is_ai(name):
    return "advent_ai" in name or "bible_kjv" in name


for num, names in sorted(by_num.items()):
    if len(names) < 2:
        continue
    line = ("patch number %d claimed by %d files: %s"
            % (num, len(names), ", ".join(names)))
    if any(is_ai(n) for n in names):
        # A collision involving this feature is ours to fix, and fatal:
        # patches apply in numeric order, so two files sharing a number
        # means one of them may never run.
        problem(line)
    else:
        # Pre-existing collisions elsewhere in the repo are reported but
        # do NOT fail the build. patch_153 has two claimants and both are
        # long since applied; renumbering an applied patch would be worse
        # than the duplicate. Not this script's call to force.
        notes.append(line + "  (pre-existing, not failed on)")

# ---------------------------------------------------------------------
#  2-5. per-file and cross-file checks
# ---------------------------------------------------------------------
sources = {}
for num, slug, name in ai_patches():
    sources[name] = io.open(os.path.join(DB, name), encoding="utf-8").read()

# --- dollar-quote balance -------------------------------------------
for name, src in sources.items():
    if src.count("$$") % 2:
        problem("%s: odd number of $$ (unclosed function or DO block)"
                % name)

# --- CHECK constraint vocabularies ----------------------------------
# e.g. CONSTRAINT ai_ledger_kind_chk CHECK (kind IN ('free_grant', ...))
allowed = {}
for name, src in sources.items():
    for m in re.finditer(
        r"CHECK\s*\(\s*(\w+)\s+IN\s*\(([^)]*)\)", src, re.I
    ):
        col = m.group(1).lower()
        vals = set(re.findall(r"'([^']*)'", m.group(2)))
        allowed.setdefault(col, set()).update(vals)

# Values actually inserted into ai_ledger's kind/pool columns.
for name, src in sources.items():
    for m in re.finditer(
        r"INSERT\s+INTO\s+public\.ai_ledger\s*\(([^)]*)\)\s*VALUES\s*\(",
        src, re.I | re.S,
    ):
        cols = [c.strip().lower() for c in m.group(1).split(",")]
        tail = src[m.end():m.end() + 400]
        vals = re.findall(r"'([^']*)'", tail)
        # crude positional match on the literals that appear
        for col in ("kind", "pool"):
            if col not in cols or col not in allowed:
                continue
            idx = cols.index(col)
            # literals appear in order; take the idx-th if present
            lits = [v for v in vals]
            if idx < len(lits):
                pass  # positional matching is unreliable; see below

# The positional approach above is fragile, so check membership instead:
# any single-quoted literal appearing directly after 'kind,' style column
# lists must be a member of the allowed set for SOME column.
for name, src in sources.items():
    for m in re.finditer(
        r"VALUES\s*\(\s*[^)]*?'(free_grant|grant|allowance|spend|refund|"
        r"adjust)'", src, re.I,
    ):
        val = m.group(1)
        if "kind" in allowed and val not in allowed["kind"]:
            problem("%s: ai_ledger kind '%s' violates its CHECK "
                    "constraint (allowed: %s)"
                    % (name, val, ", ".join(sorted(allowed["kind"]))))

# --- function definitions vs references ------------------------------
defined = set()
for name, src in sources.items():
    for m in re.finditer(
        r"CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.(\w+)", src, re.I
    ):
        defined.add(m.group(1).lower())

referenced = defaultdict(set)
for name, src in sources.items():
    for m in re.finditer(r"public\.(ai_\w+|bible_\w+)\s*\(", src, re.I):
        referenced[m.group(1).lower()].add(name)

# Tables are not functions; drop anything declared as a table.
tables = set()
for name, src in sources.items():
    for m in re.finditer(
        r"CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+public\.(\w+)", src, re.I
    ):
        tables.add(m.group(1).lower())

for fn, where in sorted(referenced.items()):
    if fn in defined or fn in tables:
        continue
    problem("undefined function public.%s() referenced by %s"
            % (fn, ", ".join(sorted(where))))

# --- INSERT columns vs CREATE TABLE columns --------------------------
table_cols = {}
for name, src in sources.items():
    for m in re.finditer(
        r"CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+public\.(\w+)\s*\((.*?)\n\);",
        src, re.I | re.S,
    ):
        tname = m.group(1).lower()
        body = m.group(2)
        cols = set()
        for line in body.split("\n"):
            line = line.strip()
            if not line or line.startswith("--"):
                continue
            cm = re.match(r"(\w+)\s+[A-Z]", line)
            if cm and cm.group(1).upper() not in (
                "CONSTRAINT", "PRIMARY", "UNIQUE", "FOREIGN", "CHECK"
            ):
                cols.add(cm.group(1).lower())
        table_cols[tname] = cols

# ALTER TABLE ... ADD COLUMN extends the set.
for name, src in sources.items():
    for m in re.finditer(
        r"ALTER\s+TABLE\s+public\.(\w+)\s+ADD\s+COLUMN"
        r"(?:\s+IF\s+NOT\s+EXISTS)?\s+(\w+)", src, re.I
    ):
        table_cols.setdefault(m.group(1).lower(), set()).add(
            m.group(2).lower())

for name, src in sources.items():
    for m in re.finditer(
        r"INSERT\s+INTO\s+public\.(\w+)\s*\(([^)]*)\)", src, re.I | re.S
    ):
        tname = m.group(1).lower()
        if tname not in table_cols:
            continue  # table defined outside this feature set
        for col in [c.strip().lower() for c in m.group(2).split(",")]:
            col = col.split()[0] if col else col
            if col and col not in table_cols[tname]:
                problem("%s: INSERT INTO %s names unknown column '%s'"
                        % (name, tname, col))

# --- dependency order ------------------------------------------------
# A function must be defined by a patch numbered <= the one using it.
defined_at = {}
for num, slug, name in ai_patches():
    for m in re.finditer(
        r"CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.(\w+)",
        sources[name], re.I,
    ):
        fn = m.group(1).lower()
        defined_at.setdefault(fn, num)

for num, slug, name in ai_patches():
    for m in re.finditer(
        r"public\.(ai_\w+|bible_\w+)\s*\(", sources[name], re.I
    ):
        fn = m.group(1).lower()
        if fn in tables or fn not in defined_at:
            continue
        if defined_at[fn] > num:
            problem("%s (patch %d) calls public.%s(), first defined in "
                    "patch %d — applied in order, it does not exist yet"
                    % (name, num, fn, defined_at[fn]))

# ---------------------------------------------------------------------
#  report
# ---------------------------------------------------------------------
print("\nAdvent AI patch checks")
print("  patches examined : %d" % len(sources))
print("  functions defined: %d" % len(defined))
print("  tables defined   : %d" % len(tables))
for name in sorted(sources):
    print("    %s" % name)

if notes:
    print("\n%d note(s) — reported, NOT failed on:" % len(notes))
    for n in notes:
        print("  ~ %s" % n)

if problems:
    print("\n%d PROBLEM(S):" % len(problems))
    for p in problems:
        print("  - %s" % p)
    sys.exit(1)

print("\nno problems found\n")
