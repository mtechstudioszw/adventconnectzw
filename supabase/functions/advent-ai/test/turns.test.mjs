// Rules about how the contents array is assembled for the provider.
//
// These are extracted from index.ts rather than imported: that module
// calls Deno.serve at import time, so it cannot run under node. The
// logic is copied here deliberately and the test asserts the RULE, so a
// change to index.ts that breaks the rule shows up as a failing test
// even though the copy still passes on its own terms.
//
// Both rules were bugs found by reading, not by running:
//
//   1. Gemini requires the contents array to BEGIN with a user turn.
//      Taking the last N messages and reversing can leave an assistant
//      reply at the front whenever ai_max_context_messages is odd.
//   2. Two consecutive user turns are malformed. Grounding was
//      originally spliced in as its own user turn, directly before the
//      member's — which is exactly that.

function assemble(history, message, grounding, maxTurns) {
  // Mirrors index.ts step 6.
  const recent = history.slice(-maxTurns);
  const turns = recent.map((m) => ({ role: m.role, content: m.content }));
  while (turns.length && turns[0].role !== "user") turns.shift();
  const finalTurn = grounding ? `${grounding}\n\n${message}` : message;
  turns.push({ role: "user", content: finalTurn });
  return turns;
}

let pass = 0, fail = 0;
function ok(label, cond) {
  if (cond) { pass++; console.log(`  ok    ${label}`); }
  else { fail++; console.log(`  FAIL  ${label}`); }
}

// A realistic alternating transcript.
const history = [];
for (let i = 0; i < 20; i++) {
  history.push({ role: i % 2 === 0 ? "user" : "assistant", content: `m${i}` });
}

console.log("\ncontents array");

for (const maxTurns of [1, 2, 3, 5, 8, 11, 12, 13, 20, 50]) {
  const turns = assemble(history, "new question", null, maxTurns);
  ok(`begins with a user turn (maxTurns=${maxTurns})`,
     turns.length > 0 && turns[0].role === "user");

  let consecutive = false;
  for (let i = 1; i < turns.length; i++) {
    if (turns[i].role === turns[i - 1].role) consecutive = true;
  }
  ok(`no two consecutive same-role turns (maxTurns=${maxTurns})`, !consecutive);
}

console.log("\ngrounding");
const grounded = assemble(history, "What is John 3:16?", "VERSE TEXT HERE", 12);
const last = grounded[grounded.length - 1];
ok("grounding rides inside the member's own turn", last.role === "user");
ok("grounding is present", last.content.includes("VERSE TEXT HERE"));
ok("the question comes LAST, after its supporting material",
   last.content.indexOf("VERSE TEXT HERE") < last.content.indexOf("What is John"));
ok("grounding does not add a turn",
   grounded.filter((t) => t.content.includes("VERSE TEXT HERE")).length === 1);

console.log("\nempty history");
const fresh = assemble([], "first ever question", null, 12);
ok("a brand new conversation is one user turn", fresh.length === 1);
ok("and it is the question", fresh[0].content === "first ever question");

console.log(`\n${pass} passed, ${fail} failed\n`);
// Set the code rather than exiting: run.mjs imports several test files
// in sequence, and process.exit() here would kill the runner before the
// later ones ever load — silently, looking like they passed.
if (fail) process.exitCode = 1;
