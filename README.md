# Utility Ownership and the Heat-Driven Electricity Poverty Gap

Honors thesis, Columbia economics-math (advisor: Prof. Gernot Wagner). Full research
design, data sources, and build plan are in `CLAUDE.md` — this file is a map of what
actually exists in the repo right now and how the pieces fit together.

**Research question:** does the gap between how much low-income and higher-income
households cut electricity use during extreme heat depend on whether their utility is
investor-owned, a cooperative, or municipal — and is that driven by state regulation or
by the utility's own governance?

## Status

| Phase | What | Status |
|---|---|---|
| 0 | Freeze the seminar's old build for reference | Done, committed (`0a4020d`) |
| 1 | Diagnose the seminar's headline result on the frozen panel | Done, not committed. **Conclusion changed mid-phase** — see below |
| 2 | Download EIA-861/861M, feasibility gate | Downloads + numbers done, not committed. **Decision pending** (monthly vs. annual panel) |
| 3+ | Build the utility-month panel | Not started |

## Repo layout (as it exists, not the aspirational CLAUDE.md tree)

```
scripts/
  00_legacy/          seminar's original scripts, frozen, DO NOT EDIT (see notes/legacy_map.md)
  01_download/         p2_01_get_eia.R, p2_02_get_eia861m.R
  02_build/            00_feasibility_counts.R
  03_analysis/         p1_00_setup.R ... p1_03_wild_bootstrap.R  (Phase 1 diagnostics)
data/
  legacy/              frozen seminar panel, gitignored
  raw/eia/, raw/eia861m/   downloaded EIA files + MANIFEST.csv, gitignored
notes/
  legacy_map.md         Phase 0: which old script made which file
  phase1_summary.md      Phase 1: the model, the math, what survives and what doesn't
  2026-09-27_session_summary.md   Phase 2 session notes
output/tables/          saved regression tables and feasibility-count CSVs
```

## Phase 1 — legacy diagnostics

**Goal:** before touching the rebuild, check whether the seminar's headline finding
(steeper poverty gap in co-op counties on hot days) survives ordinary scrutiny, using the
frozen seminar panel (`data/legacy/master_panel_monthly_fc.csv`, 333,127 rows, 2,793
counties, 2015-2024).

| Script | What it does |
|---|---|
| `p1_00_setup.R` | Not run directly. Sourced by the other three. Loads the panel, builds every interaction term, and defines two model formulas: `SPEC5` (the seminar's original, incomplete spec) and `SPEC5_sat` (the corrected one — see below). |
| `p1_01_replicate_spec5.R` | Replicates the seminar's numbers exactly, compares county- vs. state-clustered SEs, then checks `SPEC5` against `SPEC5_sat` and the muni-triple sign flip. |
| `p1_02_robustness.R` | Leave-one-state-out robustness (Texas, Kansas, Tennessee — the states that carry most of the co-op variation) and poverty fixed at its 2019 value instead of the yearly ACS value. |
| `p1_03_wild_bootstrap.R` | Wild cluster bootstrap (B=9,999) on the co-op triples, since ordinary clustering is unreliable with only 48 state clusters. |

**The headline finding, and why it changed mid-phase:** the seminar's `SPEC5` has a
triple interaction (`bin × poverty × ownership`) but is missing the lower-order terms it
implies (`bin × ownership`, `poverty × ownership`, plus `poverty` and `ownership` on their
own). Without them, the triple silently absorbs effects that have nothing to do with a
poverty gap. Once `SPEC5_sat` adds those terms, **none of the co-op or municipal triples
survive** — the seminar's "steeper poverty gap in co-op counties" was mostly an artifact
of the missing terms, not a real effect visible in this 165-county sample. A different,
smaller finding survives instead: co-op and municipal counties use less extra electricity
on hot days *regardless of poverty*. Full derivation, the corrected coefficient table, and
every robustness check: `notes/phase1_summary.md`.

**To rerun:** from the repo root, `source("scripts/03_analysis/p1_01_replicate_spec5.R")`,
then `p1_02_robustness.R`, then `p1_03_wild_bootstrap.R` (each `source()`s
`p1_00_setup.R` itself). Each is self-contained and safe to run in a fresh session.

## Phase 2 — downloads and the feasibility gate

**Goal:** before building the utility-month panel, get four numbers that decide whether
the county-level bug (165 co-op counties) is actually fixed by moving to the annual 861
census, and how much of that census EIA-861M (the monthly outcome data) actually covers.

| Script | What it does |
|---|---|
| `p2_01_get_eia.R` | Downloads the annual EIA-861 census, 2015-2024 (`data/raw/eia/`), extracts `Utility_Data`, `Service_Territory`, `Sales_Ult_Cust`, and `Short_Form` from each year's zip. Download-and-extract only — reads nothing. |
| `p2_02_get_eia861m.R` | Downloads EIA-861M (monthly sales/customers), 2015-2024 (`data/raw/eia861m/`). Handles three different filenames across the decade and EIA's occasional mislabeled file extensions. |
| `00_feasibility_counts.R` | Reads everything the two download scripts produced and computes/saves the four numbers below. |

Both downloaders log every file to `data/raw/MANIFEST.csv` (source, URL, local path,
timestamp, sha256) and are idempotent — rerunning skips anything already on disk.

### Three things about the source data worth knowing before touching it again
1. **EIA-861M has three different filenames across 2015-2024** (`f826YYYY.xls`,
   `retail_sales_YYYY.xlsx`, `sales_ult_cust_YYYY.xlsx`) but identical internal structure
   once loaded. A fourth, similarly-named file, `sales_revenue.xlsx`, is a *different*
   product (state-level only, no utility ID) — don't use it.
2. **`Short_Form` filers** (small utilities that file a simplified return) live in a
   separate `Short_Form_YYYY.xlsx` file every year except 2019, when EIA folded them
   directly into `Utility_Data_2019.xlsx` (flagged `Short Form == "Y"`). They report only
   a *total* customer count, never a residential-specific one, which is a real,
   structural limit — about 295 of ~2,560 co-op counties are served only by short-form
   co-ops and can never get a residential rate variable from EIA-861 alone.
3. **A utility operating in multiple states gets one row per state**, not one row total
   (e.g. Utility #925 has separate Arkansas and Louisiana rows every year). Any join on
   `Utility Number` alone will silently create a many-to-many match — always join on
   `(year, Utility Number, State)`.

### The four feasibility numbers (2015-2024)
1. **Ownership counts, full census:** ~875-895 co-op utilities/year, ~1,820-1,842
   municipal.
2. **Counties with ≥1 co-op:** ~2,514-2,534/year. **Passes the sanity check** — the
   seminar's bug gave 165; this is nowhere close, confirming the county-level ownership
   assignment bug is fixed by moving to the annual census.
3. **861M utility-count coverage** (861M utilities ÷ detail-filer census utilities):
   co-op ~12-16%, municipal ~8-15%.
4. **861M residential-customer coverage:** co-op ~24-27%, municipal ~45-51%. Both
   improve somewhat after 2020.

Saved to `output/tables/p2_ownership_counts_full_census.csv`,
`p2_counties_with_coop.csv`, `p2_861m_utility_coverage.csv`,
`p2_861m_customer_coverage.csv`.

### Open decision (not mine to make)
Utility-count coverage is thin; customer coverage is better but still partial. Per
CLAUDE.md this is a ⏸ check-in, not a unilateral call:
- **Monthly panel from 861M** — full within-year weather variation, ~25%/46% customer
  coverage.
- **Annual panel from the 861 census** — full utility coverage, only year-to-year weather
  variation (annual bin counts, no within-year variation).

**To rerun:** `Rscript scripts/01_download/p2_01_get_eia.R`, then
`p2_02_get_eia861m.R`, then `Rscript scripts/02_build/00_feasibility_counts.R`.

## What's not committed

Nothing from Phase 1 or Phase 2 is committed to git yet — only Phase 0
(`0a4020d`). Raw data (`data/raw/`, `data/legacy/`) is gitignored by design and never
should be; everything else (scripts, `MANIFEST.csv`, `output/tables/*.csv`, `notes/*.md`)
is a candidate for the next commit.
