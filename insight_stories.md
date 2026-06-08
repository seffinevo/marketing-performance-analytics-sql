# Insight Stories

Three analytical stories derived from the marketing analytics dataset. Each story starts from a business question, works through the data, and ends with an actionable recommendation.

---

# Story 1 – Window Matters: D0 vs D7 vs D30

## Business Question
How long does it typically take from click to conversion — and which measurement window should we use so that performance reporting is not misleading?

---

## Assumptions and Limitations
- **Source:** `marketing.vw_click_cohort_cvr_d0_d7_d30`
- **Grain:** `campaign_id + cohort_date`
- **Date span:** 2024-01-15 to 2024-03-28
- **CVR definition (GA4-style):** sessions with ≥1 conversion / total sessions. Each session is counted once regardless of how many conversions it produced.
- **Window definitions:**
  - D0: conversions on the same calendar day as cohort_date
  - D7: conversions up to cohort_date + 7 days (inclusive)
  - D30: conversions up to cohort_date + 30 days (inclusive)
- **Weighted CVR:** calculated as `SUM(converted_sessions) / SUM(total_sessions)` — not as an average of per-row ratios — to avoid distortion from small cohorts.
- **Limitation:** windows are calendar-day based, not timestamp-accurate relative to click time. This can be upgraded in a future iteration.

---

## Findings

### Overall rollup

| total_sessions | CVR_D0 | CVR_D7 | CVR_D30 | lift_D0→D7 | lift_D7→D30 |
|---:|---:|---:|---:|---:|---:|
| 5,198 | 1% | 24% | 26% | +24pp | +2pp |

Most of the conversion lift is realized by D7. Extending the window to D30 adds only marginal incremental signal (+2pp).

---

### By campaign

| campaign_name | total_sessions | CVR_D0 | CVR_D7 | CVR_D30 | lift_D0→D7 | lift_D7→D30 |
|---|---:|---:|---:|---:|---:|---:|
| Facebook Leads | 1,963 | 0% | 25% | 26% | +25pp | +1pp |
| Google Search – Brand | 2,426 | 2% | 24% | 26% | +22pp | +2pp |
| Organic Search | 809 | 0% | 24% | 26% | +24pp | +2pp |

The same window pattern holds across all campaigns. This means the D7 dominance is not driven by a single campaign — it reflects a consistent underlying behavior.

---

### By device

| device | total_sessions | CVR_D0 | CVR_D7 | CVR_D30 | lift_D0→D7 | lift_D7→D30 |
|---|---:|---:|---:|---:|---:|---:|
| Mobile | 1,737 | 1% | 26% | 28% | +25pp | +1pp |
| Desktop | 1,744 | 1% | 24% | 26% | +24pp | +2pp |
| Tablet | 1,717 | 1% | 23% | 25% | +22pp | +2pp |

D7 dominates across all devices. Device-level differences are small in this sample (tablet slightly lower than mobile and desktop).

---

## Conclusion and Recommendation
Window choice is a first-order driver of KPI interpretation: D0 misses ~96% of conversions that eventually materialize by D30. Most of the signal arrives by D7, making it the best balance between timeliness and completeness.

- **Operational reporting (daily/weekly):** standardize on **D7 CVR** as the primary window.
- **Deeper reviews / ROI context:** retain **D30 CVR** as a secondary completeness check, but treat it as marginal since incremental lift beyond D7 is small in this dataset.
- **Cross-segment comparisons:** always use weighted CVR (`SUM/SUM`) rather than averaging per-row rates, to avoid distortion from small cohorts.

---

## Future Improvements
- Upgrade cohort windows to be timestamp-accurate relative to `click_datetime` (instead of calendar-day anchored).
- Add a minimum-volume threshold per cohort to formalize stability and reduce noise in small samples.

---
---

# Story 2 – Orphan Clicks: Tracking Guardrail and Wasted Spend

## Business Question
What is the level of orphan clicks (clicks with no associated session), how much spend is tied to them, and how should this be monitored as a tracking guardrail?

---

## Assumptions and Limitations
- **Source:** `marketing.vw_clicks_orphan_flagged`
- **Grain (source layer):** `click_id` (one row per click; aggregated to campaign/day for monitoring)
- **Date span:** 2024-01-15 to 2024-03-28
- **Scope:** paid clicks only (filtered to `cost > 0`)
- **Definitions:**
  - `is_orphan_click = 1` when no matching session exists for a click (via `clicks LEFT JOIN sessions ON click_id`)
  - `orphan_rate = orphan_clicks / total_clicks`
  - `orphan_cost_share = orphan_click_costs / total_cost`
- **Limitation:** orphan clicks cannot be broken down by session-level dimensions (device, landing_page) because those dimensions only exist when a session exists.

---

## Findings

### Overall (paid clicks only)

| clicks | orphan_clicks | total_cost | orphan_click_costs | orphan_rate | orphan_cost_share |
|---:|---:|---:|---:|---:|---:|
| 4,851 | 462 | $20,416.96 | $1,939.63 | 9.5% | 9.5% |

Orphan clicks account for ~9.5% of paid clicks and ~9.5% of paid spend.

---

### By campaign

| campaign_name | clicks | orphan_clicks | orphan_rate | total_cost | orphan_click_costs | orphan_cost_share |
|---|---:|---:|---:|---:|---:|---:|
| Google Search – Brand | 2,695 | 269 | 10.0% | $11,593.95 | $1,150.50 | 9.9% |
| Facebook Leads | 2,156 | 193 | 8.9% | $8,823.01 | $789.13 | 8.9% |

Orphan rates are similar across campaigns (~9–10%). However, absolute orphan spend is higher where total spend is higher — Google Search – Brand carries the largest orphan cost impact.

---

### Monitoring baseline (percentile distribution across campaign-days)

| p50 orphan_rate | p90 orphan_rate | p95 orphan_rate | max orphan_rate |
|---:|---:|---:|---:|
| 9.6% | 11.4% | 11.4% | 11.4% |

The distribution is tight: p95 is close to the observed maximum, indicating a stable baseline with no outlier campaign-days in this sample. A practical alert threshold can be set at ~11.4% (plus a small buffer).

---

## Conclusion and Recommendation
Orphan clicks sit in a consistent, stable range — this is not a one-off tracking incident, but a steady baseline tracking loss. That said, a stable baseline still represents ~$1,940 of untracked spend, and is worth monitoring.

- **Monitoring (guardrail):** track `orphan_rate` and `orphan_cost_share` as instrumentation KPIs. Trigger an alert when either exceeds p95 (~11.4%) or shows a sustained upward trend.
- **Incident response:** if the guardrail spikes, investigate tracking/measurement causes first — redirect changes, tag firing issues, consent mode behavior, click_id propagation, or bot traffic.
- **Cost optimization (optional):** if investigation effort is justified, prioritize by absolute orphan spend: start with Google Search – Brand (~$1,150), then Facebook Leads (~$789).

---

## Future Improvements
- Capture click-level metadata (e.g., landing page, device, referrer) at click time, to enable meaningful breakdowns for orphan clicks without relying on session data.
- Add a time-series guardrail (e.g., weekly orphan_rate trend + spike detection rule) to support automated monitoring.

---
---

# Story 3 – Conversion Mix Drives Lag

## Business Question
Does conversion lag differ by first conversion type (Lead / Registration / Purchase) — and could conversion-type mix explain differences in campaign-level timing?

---

## Assumptions and Limitations
- **Source:** `marketing.vw_first_conversion_type`
- **Grain:** `session_id` (one row per converted session; deterministic tie-breaker applied for sessions with multiple conversion types)
- **Date span:** 2024-01-15 to 2024-03-28
- **Scope:** analysis is among converted sessions only. The metrics below describe timing and mix — they are not CVR.
- **Timing metric:** `share_by_Dx = sessions_converted_by_Dx / total_converted_sessions` per conversion type (conditional on conversion having occurred)
- **Window definitions:** same calendar-day logic as Story 1 (D0 / D7 / D30)

---

## Findings

### Conversion type mix (among converted sessions)

| conversion_type | converted_sessions | share |
|---|---:|---:|
| Lead | 1,059 | 77.9% |
| Registration | 177 | 13.0% |
| Purchase | 123 | 9.1% |

Lead is the dominant first conversion type. Purchase is a small share of overall conversions.

---

### Timing profile by first conversion type

| conversion_type | converted_sessions | share_by_D0 | share_by_D7 | share_by_D30 | lift_D0→D7 | lift_D7→D30 |
|---|---:|---:|---:|---:|---:|---:|
| Lead | 1,059 | 4% | 99% | 100% | +96pp | +1pp |
| Registration | 177 | 4% | 100% | 100% | +96pp | +0pp |
| Purchase | 123 | 3% | 33% | 99% | +30pp | +66pp |

Lead and Registration are effectively complete by D7. Purchase is fundamentally different: only 33% arrive by D7, and most of the lift (+66pp) happens between D7 and D30.

---

### First conversion mix by campaign

| campaign_name | Lead share | Registration share | Purchase share |
|---|---:|---:|---:|
| Google Search – Brand | 78.1% | 12.9% | 9.0% |
| Facebook Leads | 78.0% | 13.1% | 9.0% |
| Organic Search | 77.4% | 13.2% | 9.4% |

The mix is nearly identical across all three campaigns. In this dataset, between-campaign lag differences are not driven by conversion-type mix.

---

## Conclusion and Recommendation
Conversion type is a first-order driver of lag. Lead and Registration are fast (D7 captures nearly all outcomes). Purchase is slow — D7 alone would materially undercount purchase outcomes. Since the mix is stable across campaigns, mix is not the explanation for campaign-level differences here — but it would become a factor in any dataset where mix shifts over time or differs across segments.

- **Operational reporting:** use **D7** as the primary window for Lead and Registration.
- **Purchase reporting:** use **D30** (or track D7 + D30 together), since D7 misses the majority of purchase outcomes.
- **Cross-group comparisons:** include first-conversion mix alongside windowed metrics, to avoid misinterpreting apparent performance differences that are actually driven by mix composition.

---

## Future Improvements
- Track mix shifts over time (weekly/monthly) to detect changes that would alter lag interpretation and window recommendations.
