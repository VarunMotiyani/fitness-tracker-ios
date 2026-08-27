# 08 — API Model Cost Analysis

_Date: 2026-08-27_

Cost modelling for the LLM calls. Provider/model is **not chosen**
([06-decisions.md](06-decisions.md) A5) — this page sizes the decision.

All figures are **deliberately high-side** and **illustrative**. Model prices
change often; re-check at selection time. The token volume comes from
[03-technical-architecture.md](03-technical-architecture.md) §6.5.

---

## 1. Volume recap (high-side)

Assumes ~5 sessions/week (~22/month — the user's stated ceiling; real usage is
often lower), near-daily app opens, ~3 swaps per session. No prompt caching.

| Call | Count/mo | Input/mo | Output/mo |
|------|---------:|---------:|----------:|
| Weekly plan generation | 8 | 160,000 | 24,000 |
| Adjust remaining week | 30 | 240,000 | 30,000 |
| Session finalization | 22 | 55,000 | 17,600 |
| Swap | 66 | 132,000 | 19,800 |
| Post-session feedback analysis | 22 | 39,600 | 8,800 |
| InBody extraction | 1 | 2,000 | 500 |
| **Total** | **~150** | **~630,000** | **~100,000** |

**≈ 730K tokens/month → budget ~1M/month with margin → ~10–12M tokens/year.**

---

## 2. Cost by model (high-side volume, no caching)

Rough early-2026 list prices, USD per **million** tokens. Verify before choosing.

| Model class | $/M in | $/M out | Cost/month | Cost/year |
|-------------|-------:|--------:|-----------:|----------:|
| Gemini Flash (2.0-class) | 0.10 | 0.40 | ~$0.10 | **~$1.5** |
| GPT-mini-class | 0.15 | 0.60 | ~$0.15 | **~$2** |
| Gemini Flash (2.5-class, thinking) | 0.30 | 2.50 | ~$0.44 | **~$5** |
| GPT-4.1-mini-class | 0.40 | 1.60 | ~$0.41 | **~$5** |
| Claude Haiku-class | 0.80 | 4.00 | ~$0.90 | **~$11** |
| Claude Sonnet-class | 3.00 | 15.00 | ~$3.40 | **~$41** |
| **Gemini API free tier** | — | — | **$0** | **$0** — ~150 calls/mo ≈ 5/day, well under free RPM/RPD limits |
| **On-device (Apple Foundation Models)** | — | — | **$0** | **$0** — needs Apple-Intelligence hardware (not iPhone 14; OK on a future 17 Pro) |

Formula used: `cost = (input_tokens/1e6 × price_in) + (output_tokens/1e6 × price_out)`
with input ≈ 0.63M, output ≈ 0.10M per month.

---

## 3. Levers

| Lever | Effect |
|-------|--------|
| **Prompt caching** (system prompt + catalog slice are static) | Cuts monthly **input** 50–90% → toward ~200K. Biggest single saving. |
| **Keep "adjust remaining week" rule-engine-only** (no LLM) | Removes ~38% of monthly input (630K → ~390K). |
| **Rolling history window** (already in design) | Caps per-call input as data grows — no unbounded creep. |
| **Reasoning / thinking mode** | Multiplies **output** ~3–10×. Push cost up; matters most on models with expensive output (Sonnet, 2.5 Flash-thinking). |
| **Smaller catalog slice** (send only owned-equipment exercises) | Already assumed; keeps weekly-gen input near 20K not 40K+. |

---

## 4. Scenarios

| Scenario | Input/mo | Output/mo | Flash/mini | Sonnet-class |
|----------|---------:|----------:|-----------:|-------------:|
| **Realistic** (this-page high-side) | 630K | 100K | ~$1–5/yr | ~$41/yr |
| **With caching + rules-only adjust** | ~120K | ~70K | <$1/yr | ~$12/yr |
| **Pathological** (2× calls, thinking on, no caching) | ~1.3M | ~1.0M | <$40/yr | ~$200/yr |

---

## 5. Bottom line

- On any **cheap-smart model** (Gemini Flash / GPT-mini class): **$1–6/year**.
- On the **Gemini API free tier**: plausibly **$0** at this volume.
- Even a **frontier model** (Sonnet-class): **~$40/year** — the bottom of the
  ₹2–3k/year commercial-app range the user was avoiding.
- Cost is **not** a deciding factor between the cheap-smart candidates. Choose on
  **reasoning quality, latency, and structured-output reliability**; cost only
  rules out running everything through a frontier model unnecessarily.
- The cost meter in the app ([03](03-technical-architecture.md) §8,
  `monthToDateTokenCost` + `pricePerMTok*` settings) exists to catch surprises,
  not because spend is expected to matter.

---

## 6. Caveats

- Prices are from memory as of the knowledge cutoff and **will be stale** — treat
  the table as ratios, not quotes. Re-price at provider selection (Q8).
- Image tokens for the InBody call vary by provider tiling; estimated at ~2K,
  negligible at 1 scan/month.
- Free-tier rate limits change; confirm current RPM/RPD before relying on $0.
- Batch/async discounts and prompt-caching mechanics differ per provider and are
  not modelled here beyond the "levers" note.
