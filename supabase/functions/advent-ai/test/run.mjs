// Test runner for the Advent AI edge function's pure logic.
//
// Two jobs, in order:
//
//   1. **Syntax-check every file.** The edge function is deployed by
//      `supabase functions deploy`, which is the first thing that ever
//      parses it — so a syntax error ships silently from a repo whose
//      Dart analyzer and Dart tests are both green. That has already
//      happened once here: an escaped "\n\n" was written as a literal
//      newline inside a double-quoted string, and nothing in the project
//      could see it.
//
//   2. **Run the behavioural tests** against the transpiled modules.
//
// esbuild is fetched by npx on demand. Nothing is vendored, there is no
// package.json, and no lockfile is touched — this must not alter the
// Flutter app's dependency story in any way.
//
//   RUN:  node supabase/functions/advent-ai/test/run.mjs

import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const fnDir = join(here, "..");
const buildDir = join(here, ".build");

const ESBUILD = "esbuild@0.25.0";
const SOURCES = ["index.ts", "provider.ts", "prompt.ts", "bible.ts"];

/// Files with pure, Deno-free logic worth executing. `index.ts` and
/// `provider.ts` reach for Deno.serve / Deno.env at module scope, so
/// they are syntax-checked only — running them here would prove nothing
/// except that node is not Deno.
const TESTABLE = ["bible.ts"];

/// Runs esbuild from INSIDE the function directory, with bare relative
/// paths.
///
/// This repo lives under "adventist super app" — a path with spaces —
/// and on Windows `shell: true` makes the shell re-split every argument
/// on whitespace. esbuild then sees three input files instead of one and
/// reports "Must use outdir when there are multiple input files", which
/// is indistinguishable from a syntax error in every source at once.
///
/// Passing `cwd` and bare filenames keeps every argument space-free, so
/// the shell has nothing to split.
function npx(args, cwd = fnDir) {
  return execFileSync("npx", ["--yes", ESBUILD, ...args], {
    cwd,
    stdio: ["ignore", "pipe", "pipe"],
    encoding: "utf8",
    shell: process.platform === "win32",
  });
}

let failed = false;

// A scratch output path, NOT the platform null device. On Windows
// esbuild reads `--outfile=NUL` as a second INPUT file and fails with
// "Must use outdir when there are multiple input files" — which looks
// exactly like a syntax error in every source file at once, and sends
// you hunting for a bug that is not there.
rmSync(buildDir, { recursive: true, force: true });
mkdirSync(buildDir, { recursive: true });
const scratch = "test/.build/_syntax_check.js";

// ---- 1. syntax -------------------------------------------------------
console.log("\nsyntax");
for (const file of SOURCES) {
  try {
    npx([file, "--loader:.ts=ts", "--outfile=" + scratch]);
    console.log(`  ok    ${file}`);
  } catch (e) {
    failed = true;
    console.log(`  FAIL  ${file}`);
    console.log(String(e.stderr ?? e.message).split("\n").slice(0, 8)
      .map((l) => "        " + l).join("\n"));
  }
}

if (failed) {
  console.log("\nsyntax errors — not running behavioural tests\n");
  process.exit(1);
}

// ---- 2. behaviour ----------------------------------------------------
for (const file of TESTABLE) {
  npx([
    file,
    "--loader:.ts=ts",
    "--format=esm",
    "--outfile=test/.build/" + file.replace(/\.ts$/, ".mjs"),
  ]);
}

const TESTS = ["bible_refs.test.mjs", "turns.test.mjs"];
try {
  for (const t of TESTS) {
    await import(pathToFileURL(join(here, t)).href);
  }
} catch (e) {
  // The test file exits non-zero itself on failure; anything reaching
  // here is a genuine crash.
  console.error(e);
  process.exit(1);
}
