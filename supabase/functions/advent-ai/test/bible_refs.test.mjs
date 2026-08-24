// Behavioural tests for the scripture-reference parser in bible.ts.
//
// `parseRefs` is the highest-risk pure function in the grounding path:
// miss a reference and the model answers scripture from memory (the
// fabrication the brief forbids); invent one and we inject the wrong
// passage into the prompt. Neither failure is visible in a code review,
// and neither is caught by the Dart test suite.
//
// The function has no Deno dependency, so it runs under plain node once
// esbuild has transpiled the TypeScript. There is no node_modules and no
// package.json here on purpose — `npx esbuild` is fetched on demand, the
// same way CI does it.
//
//   RUN:  node supabase/functions/advent-ai/test/run.mjs
//
// That wrapper transpiles bible.ts and then executes this file.

import { parseRefs, wantsTopicalSearch } from "./.build/bible.mjs";

let pass = 0, fail = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) { pass++; console.log(`  ok    ${label}`); }
  else { fail++; console.log(`  FAIL  ${label}\n        got      ${a}\n        expected ${e}`); }
}

const ref = (book, chapter, verse, endVerse) => ({ book, chapter, verse, endVerse });

console.log("\nparseRefs — shapes people actually type");
check("John 3:16",
  parseRefs("What does John 3:16 mean?").map(r => [r.book, r.chapter, r.verse, r.endVerse]),
  [["John", 3, 16, undefined]]);

check("range John 3:16-18",
  parseRefs("Read John 3:16-18 please").map(r => [r.book, r.chapter, r.verse, r.endVerse]),
  [["John", 3, 16, 18]]);

check("whole chapter Psalm 23",
  parseRefs("Psalm 23").map(r => [r.book, r.chapter, r.verse]),
  [["Psalm", 23, undefined]]);

check("numbered book 1 Cor 13:4",
  parseRefs("1 Cor 13:4").map(r => [r.book, r.chapter, r.verse]),
  [["1 Cor", 13, 4]]);

check("roman numeral II Timothy 3:16",
  parseRefs("II Timothy 3:16").map(r => [r.book, r.chapter, r.verse]),
  [["II Timothy", 3, 16]]);

check("lowercase romans 8:28",
  parseRefs("romans 8:28").map(r => [r.book, r.chapter, r.verse]),
  [["romans", 8, 28]]);

console.log("\nparseRefs — must NOT match");
check("plain question, no reference",
  parseRefs("How do I create a post?").length, 0);
check("'top 10' is not a book",
  parseRefs("show me the top 10 items").length, 0);
check("'chapter 3' alone is not a book",
  parseRefs("read chapter 3").length, 0);

console.log("\nparseRefs — bounds");
check("caps at 3 references",
  parseRefs("John 3:16 Romans 8:28 Psalm 23 Genesis 1:1 Acts 2:38").length, 3);
check("dedupes repeats",
  parseRefs("John 3:16 and again John 3:16").length, 1);

console.log("\nwantsTopicalSearch");
check("what does the Bible say about forgiveness",
  wantsTopicalSearch("What does the Bible say about forgiveness?"), true);
check("where does scripture teach about the Sabbath",
  wantsTopicalSearch("Where does scripture teach about the Sabbath?"), true);
check("app question is not topical scripture",
  wantsTopicalSearch("How do I change my profile picture?"), false);

console.log(`\n${pass} passed, ${fail} failed\n`);
// Set the code rather than exiting: run.mjs imports several test files
// in sequence, and process.exit() here would kill the runner before the
// later ones ever load — silently, looking like they passed.
if (fail) process.exitCode = 1;
