# Session summary — 2026-09-27

Phase 2 (data downloads + feasibility gate). Nothing below is committed yet.

## What got built

| File | Status |
|---|---|
| `scripts/01_download/p2_01_get_eia.R` | Working. Downloads annual EIA-861 (2015-2024), extracts `Utility_Data`/`Service_Territory`/`Short_Form`, builds combined ownership counts |
| `scripts/01_download/p2_02_get_eia861m.R` | Working, tested end-to-end. Downloads EIA-861M (monthly) across all 3 filename eras |
| `scripts/02_build/00_feasibility_counts.R` | Working, tested end-to-end. Computes all 4 CLAUDE.md feasibility numbers, 2015-2024, saves to `output/tables/p2_*.csv` |
| `scripts/02_build/joinserviceterr.R` | Empty stub, superseded by `00_feasibility_counts.R` -- probably delete |
| `data/raw/eia/` (zips + extracted xlsx) | 10 years, on disk, gitignored |
| `data/raw/eia861m/` (10 files) | On disk, gitignored |
| `data/raw/MANIFEST.csv` | Logging every download (source, url, path, sha256, timestamp) |

## What we found out

**The download itself was harder than expected — three separate discoveries, each changing a number we'd already computed:**

1. **EIA-861M has three different filenames across the decade**, not one: `f826YYYY.xls` (2015-16), `retail_sales_YYYY.xlsx` (2017-20), `sales_ult_cust_YYYY.xlsx` (2021-24). A fourth file, `sales_revenue.xlsx`, looks similar but is a completely different (state-level, no utility ID) product -- a dead end I ruled out before building around it.

2. **`Utility_Data`'s "Short Form" column is a 2019-only artifact.** That year, EIA bundled small ("short-form") utility filers directly into `Utility_Data_2019.xlsx` with a flag; every other year ships them in a separate `Short_Form_YYYY.xlsx` file we weren't originally reading. I initially "fixed" 2019 by filtering the flagged rows out -- that was **wrong**; the right fix was reading both files and combining them for every year. Consequence: our real co-op/muni universe is ~875-895 co-ops and ~1,820-1,842 munis per year (not the ~805-830 the `Utility_Data`-only read had been showing).

3. **Short-form filers report only a Total customer count, never a residential-specific one.** This is a structural limit in EIA's own data, not a bug: about 295 of ~2,560 co-op counties (11.5%) are served only by short-form co-ops and can never get a residential rate variable from EIA-861 alone.

**Two real bugs caught by testing before they'd have silently corrupted the feasibility numbers:**
- A join for the county-count check was missing `State` from the key. A multi-state utility (e.g. Utility #925, operating in both AR and LA) matched every one of its territory rows against *both* its state-records -- a many-to-many join, not just a warning to suppress. Fixed by joining on `(year, Utility Number, State)`. This lowered the "counties with >=1 co-op" number from an inflated ~2,560 to the correct ~2,514-2,534 -- still comfortably above CLAUDE.md's >2,000 threshold.
- EIA served the 2016 861M file with a `.xls` extension, but its actual content is xlsx (zip) format -- `readxl` picked the wrong parser and failed. Now sniffed and auto-renamed at download time.

## The four feasibility numbers (2015-2024, final)

1. **Ownership counts, full census:** ~875-895 co-op utilities/year, ~1,820-1,842 municipal.
2. **Counties with >=1 co-op:** ~2,514-2,534/year. **Passes the sanity check** (seminar's bug gave 165; this is nowhere close).
3. **861M utility-count coverage vs. detail-filer census:** co-op ~12-16%, municipal ~8-15%.
4. **861M residential-customer coverage:** co-op ~24-27%, municipal ~45-51%. Both improve somewhat after 2020 (the detail-filer census shrank as more small utilities went short-form-only; 861M's sample size held roughly steady).

## Where this leaves us
This is the CLAUDE.md "⏸ CHECK IN" gate (section 4.2) -- before building the panel, you need to decide between:
- **Monthly panel from 861M**: full within-year weather variation, ~25%/46% customer coverage.
- **Annual panel from the 861 census**: full utility coverage, but only year-to-year weather variation (annual bin counts).

Not yet decided -- this isn't mine to decide unilaterally per CLAUDE.md.

## Loose ends for next time
- `scripts/02_build/joinserviceterr.R` is an empty stub -- probably safe to delete once `00_feasibility_counts.R` is confirmed to supersede it.
- Nothing from today is committed. Scripts, `MANIFEST.csv`, and the four `output/tables/p2_*.csv` are all candidates; raw data stays gitignored as intended.
- The Short Form / customer-coverage findings (points 2-3 above) are worth a paragraph in the eventual data section regardless of which panel gets chosen -- they're a real, documented limitation of the EIA-861 census itself.
