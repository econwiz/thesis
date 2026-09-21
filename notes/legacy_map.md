# Legacy map — seminar build (`~/public_policy_project`)

Frozen copies: scripts in `scripts/00_legacy/` (unchanged; the two files from subfolders were
renamed with a prefix to avoid name collisions), panel in `data/legacy/` (gitignored).
Original repo is left untouched. All legacy paths are hard-coded to `/Users/aliabonanno/public_policy_project/`.

## Panel the regressions ran on
`master_panel_monthly_fc.csv` — county × year × month, 2015–2024.
335,878 rows, 2,814 counties, 69 columns (333,127 rows / 2,793 counties after `dropna` in the estimation sample, per `empiricaldes.html`).
Regression code: `praccyreg.ipynb`, cell 3 (Specs 1–5, 8). Cell 1 of the same notebook runs on the annual `master_panel.csv` (early draft, not the headline).

## Which script produced which file
| Script | Output |
|---|---|
| `01_acs_cleaning.ipynb` | `acs_poverty_panel.csv` (S1701, ACS 5-yr 2012–2024), `acs_controls_panel.csv` |
| `02_eia_cleaning.ipynb` | `eia861_sales.csv`, `eia861_territory.csv`, `eia861_county_panel.csv` (annual), `eia861m_sales.csv` (monthly) |
| `03_noaa_cleaning.ipynb` | `noaa_heat_panel.csv` (older), `noaa_panel_final.csv` (9 bins + precip, county-month) |
| `04_master_merge.ipynb` | `master_panel_monthly.csv` → `master_panel_monthly_fc.csv` (adds URDB fixed charge, RUCC, COVID, interactions). Cells 2/3/7 are successive rewrites of the same merge; the last (cell 7) is the final version |
| `openei.ipynb`, `Untitled1.ipynb` | URDB fixed charges, TOU prevalence, state co-op concentration, LIHEAP look-ups |
| `summarystats.ipynb`, `explainer.ipynb`, `empiricaldes.html`, `results.html` | Tables/figures/presentation only |
| `mergeprism.py` | Downloader for PRISM 4km tmean/tmax 2015–2024. **`prism/tmax/` is empty — never used.** |
| `oldnotebook_mastermerge.ipynb`, `figures_mergeacsnoaa.ipynb`, `Untitled.ipynb` | Earlier drafts / scratch |

## Where ownership was assigned (the flaw)
- `02_eia_cleaning.ipynb` cell ~4 and the 861M block: keep {IOU, Cooperative, Municipal, Political Subdivision, State, Federal}; map Political Subdivision, State **and Federal → "Municipal"**. Marketers/behind-the-meter/facility dropped.
- `04_master_merge.ipynb` (cell 0 ~l.104; cell 7): 861M utility-month rows inner-joined to the 861 territory file on (utility_id, year, state); `dominant_ownership_type` = ownership of the utility with the **most residential customers in that county-month** (`sort_values(...).groupby(...).first()`).
- Consequences: only utilities that report individually in 861M can ever be "dominant", hence 165 co-op / 117 muni / 2,532 IOU counties (2,814 total). It is computed per month; 15 counties change type over time. Spec 5 dummies (`is_coop`, `is_municipal`) come from this.

## Temperature
- Product: NOAA/NCEI county files `tempdata/tavg-YYYYMM-cty-scaled.csv` (daily county values in °C, one row per county-month, day1–day31). NCEI→FIPS state crosswalk applied. PRISM not used.
- Bins (`03_noaa_cleaning.ipynb`, "Doremus" bins), on daily **Tavg**, right-closed `(low, high]`, edges `[-inf,-5,0,5,10,15,20,25,30,inf]`:
  bin1 ≤−5, bin2 (−5,0], bin3 (0,5], bin4 (5,10], bin5 (10,15], bin6 (15,20] = **reference**, bin7 (20,25], bin8 (25,30], bin9 >30.
- Binned at county level from daily county values (correct order). Precipitation monthly total in mm added.

## Spec 5 as actually run (`praccyreg.ipynb` cell 3, `linearmodels.PanelOLS`)
`log_res_sales_per_customer ~ bins1-5,7-9 + [bin7-9 × pov_dm] + [bin7-9 × pov_dm × coop] + [bin7-9 × pov_dm × muni] + prcp + prcp² + month_2..12 + income + pct_white/black/hispanic + pct_bachelors_plus + unemployment + EntityEffects(county) + TimeEffects(year)`
- SEs clustered by **county** (`cluster_entity=True`).
- Poverty = ACS 5-yr S1701 share <150% FPL, **time-varying** (vintage = panel year), demeaned over the sample.
- Poverty and ownership interactions on **hot bins 7–9 only**; other controls are **not** interacted with bins.
- Headline coefficients (typed by hand in `Untitled1`/`explainer`, from results in `empiricaldes.html`): coop triple −0.025 (bin8), −0.038 (bin9); public bin9 +0.048. No saved regression logs — to be reproduced in Phase 1.

## Discrepancies to resolve
1. `empiricaldes.html` says **county × month FE**; the code has **county FE + month dummies + year FE**.
2. Poverty is time-varying in legacy; the thesis fixes it at the 2019 vintage.
3. Controls are not interacted with bins in legacy.
4. Bin 9 is a rare event (≈1 day/month even in summer co-op counties), so bin-9 estimates are fragile.
5. Federal is folded into "Municipal" in legacy (kept as-is for now; decision deferred by Alia).
6. Clustering is by county, not state.
