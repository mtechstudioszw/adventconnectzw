# Advent AI — setup and operations

Everything needed to take Advent AI from "code in the repo" to
"answering members", and the handful of knobs worth knowing afterwards.

---

## 1. Google Cloud — the provider

1. **[aistudio.google.com](https://aistudio.google.com)** → *Get API key*
2. Create the key inside a Google Cloud project.
3. **Enable billing on that project.** Cloud Console → Billing → link a
   card.

### Billing is not optional, and not about scale

Google's own pricing page marks every **free-tier** model as
*"used to improve Google products"*. The paid tier is not.

Members ask Advent AI about depression, marriage trouble, doubt and
money. On the free tier all of that becomes training data. That is the
one outcome this feature was built to avoid, and no amount of prompt
engineering changes it — it is a billing-tier property.

Free-tier rate limits are also applied **per project, not per user**, so
the entire membership would share one quota and the feature would fall
over on the first busy Sabbath.

Develop against the free tier with invented questions if you like. Do not
ship on it.

### What it costs

| | per answer | 10,000 members × 10 questions |
|---|---|---|
| Free tier members (`gemini-2.5-flash-lite`) | ~$0.0005 | ~$46 / month |
| Premium members (`gemini-2.5-flash`) | ~$0.0020 | covered by the subscription |

A Premium member who exhausts all 500 monthly questions costs ~$0.99
against ~$2.55 net of Play's cut. Realistic use is far below the cap.

Two ceilings bound the downside regardless — see
[Cost controls](#cost-controls).

---

## 2. Supabase — store the key

Dashboard → project → **Edge Functions → Secrets**:

| Name | Value |
|---|---|
| `GEMINI_API_KEY` | the key from step 1 |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

**The key must never appear in** the Flutter source, a `.env` file, the
APK/AAB, or the repo. It lives only here. The app never talks to Google —
it talks to the edge function, which holds the key server-side.

---

## 3. Apply the database patches

Seventeen patches, **in numeric order**. All are idempotent, so
re-running one is safe.

```
236  advent_ai_core            conversations + messages
237  advent_ai_balance         allowance, ledger, entitlement
238  advent_ai_config          config keys + service state
239  advent_ai_free_refill     monthly free refill, per-tier model
240  advent_ai_settle_cost     cost settlement + service-role balance
241  advent_ai_bible_schema    corpus tables, search functions
242  bible_kjv_aliases         228 book aliases
243-251  bible_kjv_part01..09  31,100 verses (~570 KB each)
252  advent_ai_app_knowledge   26 app-help entries
```

Apply them the usual way (see `memory/supabase-patch-workflow`): POST the
file contents to
`https://api.supabase.com/v1/projects/{ref}/database/query` with a
management token, **UTF-8 encoded** — these files are full of em-dashes
and PowerShell will mangle them otherwise.

Each patch ends with a verification block that raises `NOTICE ... OK`.
**Read that output.** A multi-statement body runs as one transaction, so a
failure rolls the whole patch back and the next patch will fail confusingly
on the missing objects.

`243`–`251` are independent of one another; if one fails, retry just that
one.

### Before applying, run the static checks

```
python scripts/check_ai_patches.py
```

Catches duplicate patch numbers, unbalanced `$$`, ledger values that
violate their own CHECK constraint, calls to functions no patch defines,
and INSERTs naming columns that do not exist. It runs in CI too.

It reports one **pre-existing** collision — `patch_153` is claimed by two
files, both long since applied — as a note rather than a failure.
Renumbering an applied patch would be worse than the duplicate.

---

## 4. Deploy the edge function

```
supabase functions deploy advent-ai
```

`verify_jwt` must stay **ON**. The caller's identity comes from the
verified token and from nowhere else — no user id is ever read from the
request body, deliberately, so a caller cannot name someone else.

Before deploying, the syntax and logic checks:

```
node supabase/functions/advent-ai/test/run.mjs
```

This exists because `flutter analyze` and `flutter test` cannot see
TypeScript, so `supabase functions deploy` would otherwise be the first
thing that ever parses it. A syntax error would ship from a fully green
repo — which has already happened once here.

---

## 5. Play Console

**Nothing to do.** Advent AI uses the existing `premium_monthly`
subscription. No new product, no consumable, no second billing path.

---

## Cost controls

All in `app_config`, all changeable from the dashboard without shipping
an app update.

| Key | Default | What it does |
|---|---|---|
| `ai_free_grant_units` | `10` | free questions per member per month |
| `ai_premium_monthly_units` | `500` | Premium questions per month |
| `ai_global_free_pool_micros` | `10000000` | lifetime ceiling on free-tier spend |
| `ai_global_daily_cap_micros` | `250000` | per-day ceiling on free-tier spend |
| `ai_rate_free_per_min` / `_day` | `5` / `10` | per-member rate limits |
| `ai_rate_premium_per_min` / `_day` | `10` / `200` | same, for subscribers |
| `ai_max_request_chars` | `2000` | longest question accepted |
| `ai_max_output_tokens` | `1200` | longest answer generated |
| `ai_max_context_messages` | `12` | turns of history sent to the model |
| `ai_model` | `gemini-2.5-flash-lite` | free tier model |
| `ai_model_premium` | `gemini-2.5-flash` | Premium model |

**The ceilings apply to free usage only.** A paying member is never cut
off because the free pool ran dry — they have already paid.

### How spend is actually counted

The unit is debited **before** the provider is called (otherwise a crash
mid-request is a free ride), but the real cost is unknown until the
provider reports usage afterwards.

So the debit carries a deliberately **pessimistic** estimate — the whole
context window in, the whole output cap out — and `ai_settle_cost` corrects
it to what was actually billed. Over-counting briefly is safe; the ceiling
trips slightly early. Under-counting would let the guard drift above real
spend, so the estimate is never allowed to be optimistic.

If you are reconciling the ledger against a Google invoice, read
`meta->>'delta_micros'` on the `adjust` rows, not `cost_micros` — the
CHECK constraint forbids negatives, and the normal settlement is negative.

---

## When something goes wrong

### Turning it off

```sql
SELECT public.ai_trip_service_suspended('reason shown to admins only');
SELECT public.ai_resume_service();
```

While suspended, every member — including subscribers — is told Advent AI
is temporarily unavailable, **nobody is charged, and the Premium button
is hidden.** Selling a subscription for a service that is currently down
is the one thing that would deserve the accusation of a dark pattern.

The edge function trips this automatically when the provider returns a
billing or quota rejection, so a lapsed card stops the app hammering a
dead endpoint instead of showing members nonsense.

### What members see

Five distinct states, deliberately not conflated — conflating them is how
a member gets blamed for an expired card:

| Reason | Meaning | Sells Premium? |
|---|---|---|
| `out_of_free` | their sample is spent | **yes** — the only one |
| `out_of_allowance` | subscriber, month spent | no — they already pay |
| `free_pool_closed` | app-wide free pool dry | yes |
| `service_suspended` | provider refusing us | **no** |
| `blocked` | account barred from the AI | no |

### Blocking an abusive account

```sql
UPDATE public.ai_accounts SET blocked = true WHERE user_id = '...';
```

Only Advent AI is affected. The rest of the app keeps working.

### Checking spend

```sql
SELECT day,
       free_cost_micros / 1000000.0 AS free_dollars,
       cost_micros      / 1000000.0 AS total_dollars,
       messages
  FROM public.ai_spend_daily
 ORDER BY day DESC LIMIT 30;
```

---

## Editing what the AI knows about the app

`ai_app_knowledge` is a table, not a prompt string, so a wrong answer is
a one-row `UPDATE` from the dashboard — live immediately, no app release.

```sql
UPDATE public.ai_app_knowledge
   SET answer = '...', updated_at = NOW()
 WHERE topic = 'create_post';
```

**Accuracy rules when adding rows** (also in `patch_252`'s header):

- **Never name a button you have not seen in the source.** Describe
  navigation ("open the Chat tab"), not labels ("tap the blue New
  Message button"). Navigation is stable; labels change every redesign.
- The five tabs are **Home, Watch, Chat, Marketplace, Profile**. The
  third is labelled *Chat* even though its route is `/messages` —
  writing "the Messages tab" sends members hunting for a tab that does
  not exist.
- Say when something is seller- or admin-only.
- **When unsure, leave it out.** An absent entry makes the model say it
  is not sure, which is correct. A wrong entry makes it lie confidently,
  and the member goes looking for a screen that was never there.

Switch a bad row off without deleting it:

```sql
UPDATE public.ai_app_knowledge SET is_active = false WHERE topic = '...';
```

---

## Where the bubble does not appear

`AdventAiBubble.blockedPrefixes`, pinned by
`test/advent_ai_bubble_test.dart`.

**`/messages` is absolute — founder rule.** An AI button floating over a
private conversation reads as the app watching it. It is not: the bubble
carries no screen content, and Advent AI has no tool that can read a
message. But a member cannot inspect an architecture; they can only see
what is on top of their chat.

Also absent on pre-auth screens, app-replacement screens (maintenance,
banned, update-required), `/admin`, and over itself.

**`/prayer` deliberately allows it**, unlike the advertising blocklist.
An advert on a prayer request is crass; an assistant that can help
someone find a passage to pray through is the opposite.
