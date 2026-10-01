# CLAUDE.md — Thesis: Utility Ownership and the Heat-Driven Electricity Poverty Gap

**Revision 2 (2026-09-30).** Replaces the original brief. Phases 1 and 2 are complete and
changed the project materially — read §3 before assuming anything from the earlier version.

Owner: Alia, Columbia economics–math senior, honors thesis, advisor Prof. Gernot Wagner.
She works in R (`fixest`, `data.table`) and Python, and wants to be **guided through** the
build, not handed a black box. Work in small steps, explain what each script does and why,
and stop at the **⏸ CHECK IN** points.

---

## 1. The research question

When extreme heat raises cooling costs, low-income households curtail electricity use rather
than absorb the bill. Foregone cooling during dangerous heat is a health risk, so the size of
this gap is a question about who bears climate damage.

**The thesis asks:** does the poverty gap in heat-driven electricity consumption depend on the
ownership structure of the serving utility — investor-owned (IOU), cooperative, or
municipal/public — and is that dependence driven by **state regulation** or by **internal firm
governance**?

**Framing note (changed since the proposal).** The proposal said: my seminar paper found a
steeper poverty gap in co-op counties; the thesis tests the mechanism behind it. That premise
no longer holds — see §3. The current framing is: *whether* ownership moderates the
heat-driven poverty gap is an open question that existing data cannot answer, because
county-level ownership assignment covers only ~160 co-op counties concentrated in a few
states. This thesis builds the panel that can answer it, and tests the governance channel
directly.

---

## 2. Where the contribution lives

Not distinct: that a heat-driven poverty gap exists (Doremus et al. 2022; Nock et al. 2022 at
household level), or that ownership affects distributional outcomes (Berhe & Mohapatra).

Distinct, in descending order of strength:

1. **Non-residential load share as a governance-intensity measure.** Nothing in the literature
   uses it. Positive, falsifiable prediction about board capture; continuous variation *within*
   ownership type; nearly free once the panel exists. **This is the most original thing in the
   project and should be built immediately after the baseline, not in November.**
2. **The regulation-versus-governance decomposition.** Berhe & Mohapatra explicitly call their
   mechanism evidence suggestive. Nobody has used within-ownership variation in regulatory
   exposure.
3. **The outcome is a heat *response*, not a burden level.** This is the clean separation from
   Berhe & Mohapatra — climate damage incidence rather than rate design.
4. **The measurement finding.** 861M-based county ownership gives 165 co-op counties; the
   census gives ~2,514. Small co-ops end up inside the IOU *control group*, not as missing
   data. This deserves its own subsection, not a footnote — anyone building county ownership
   from the monthly file has the same error.

---

## 3. What Phases 1 and 2 established — READ THIS

### 3.1 The seminar result did not survive a correct specification

Spec 5 as the seminar ran it omitted the lower-order terms a triple interaction implies
(`D_b × Coop`, `D_b × Muni`, `P × Coop`, `P × Muni`, `P`, `Coop`, `Muni`). Consequences:

| Term | Spec 5 | Saturated | Reading |
|---|---|---|---|
| bin 8 × P × Coop | −0.0248 (0.0082) | −0.0251 (0.0163) | estimate unchanged, SE doubled → **power problem** |
| bin 9 × P × Coop | −0.0377 (0.0097) | −0.0110 (0.0163) | estimate collapsed → **artifact** |

**Do not conflate these.** Bin 9 was produced by the omitted terms. Bin 8 was not — its
confidence interval is [−0.070, 0.015], wide enough to contain effects three times the point
estimate. The honest description is "unresolved in a 160-county sample," not "refuted."

The wild cluster bootstrap on the saturated model returns p = 0.43 for bin 8; none of the six
triples survives. The leave-out table on the saturated spec shows no consistent story.

### 3.2 Why the standard error doubled (diagnosed, not guessed)

Two hypotheses were tested and rejected: thin poverty variation within co-ops (co-op SD 0.092
vs IOU 0.086 — co-ops are *wider*), and collinearity between the triple and its lower-order
term (residualized correlation 0.37, VIF ≈ 1.16).

The actual cause is the **clustering channel**. IID SEs rose only 12% between specs
(0.00163 → 0.00184) while the cluster inflation factor rose from 5.0 to 8.8. Once `D_b × Coop`
absorbs the county-level component, what identifies the triple is `D_b × Coop ×` (poverty
deviations) — and poverty deviations among co-op counties are strongly state-clustered. **λ is
identified mostly off between-state differences in how poor each state's co-op counties are.**
Effective sample ≈ 24 co-op states, not 160 counties.

**Implication for the rebuild:** what buys precision is co-op units at *different poverty
levels within the same state*, plus more co-op states. Compute the within-state SD of poverty
across co-op counties before and after the rebuild — that number predicts whether precision
improves. Required diagnostic, not optional.

### 3.3 The unexplained pattern — treat with suspicion

In the saturated model, `D_b × Coop` and `D_b × Muni` are significant at bins 7 and 9 and null
at bin 8, for **both** ownership types, with bin 8 sitting between them in temperature. No
behavioral story produces that shape twice. Before treating "co-ops and munis use less on hot
days regardless of poverty" as a finding, check the correlations among the six bin×ownership
regressors after demeaning, and the count of co-op counties with days in each bin. It is also
confounded by housing stock — co-op and muni territories differ from IOU territories in
building age, density and AC saturation — which is what the adjacency design is for.

### 3.4 Phase 2 data discoveries (all hard-won; do not relearn)

- **861M has three filename eras:** `f826YYYY.xls` (2015–16), `retail_sales_YYYY.xlsx`
  (2017–20), `sales_ult_cust_YYYY.xlsx` (2021–24). `sales_revenue.xlsx` looks similar but is a
  different, state-level product with no utility ID — a dead end.
- **The 2016 file is served with a `.xls` extension but is xlsx (zip) content.** Sniff and
  rename at download time.
- **Short-form filers ship in a separate `Short_Form_YYYY.xlsx` every year except 2019**, where
  EIA bundled them into `Utility_Data_2019.xlsx` with a flag. Both files must be read and
  combined for every year. Reading `Utility_Data` alone undercounts (~805–830 co-ops instead
  of the true ~875–895).
- **Short-form filers report only a Total customer count, never residential.** Structural limit
  in EIA's data. ~295 of ~2,560 co-op counties (11.5%) are served only by short-form co-ops and
  can never yield a residential rate variable. They get dropped and documented.
- **The territory join needs `(year, Utility Number, State)`.** Joining on utility alone is
  many-to-many for multi-state utilities (e.g. #925 in AR and LA).
- **Any "coverage improves after 2020" statement is wrong.** The detail-filer denominator
  shrank as utilities moved to short-form filing (co-op census customers 17.80M → 16.98M,
  munis 13.72M → 12.56M). The numerator kept rising, so ratios jumped. Coverage did not
  improve. Label denominators `n_utilities_detail`, never `n_utilities_census`.

### 3.5 Feasibility numbers (final)

| Quantity | Value |
|---|---|
| Co-op utilities, full census | ~875–895/year |
| Municipal utilities, full census | ~1,820–1,842/year |
| Counties with ≥1 co-op | ~2,514–2,534/year (seminar's bug: 165) |
| **Co-op utilities in 861M** | **95–97/year, flat across the decade** |
| **Municipal utilities in 861M** | **69/year, flat** |
| 861M residential-customer coverage (vs detail filers) | co-op ~24–27%, muni ~45–51% |

⚠ **Unreconciled:** a later run produced 2,560–2,563 counties-with-co-op rather than
2,514–2,534. Trace which code path produced each and settle it before building on either.

### 3.6 Decisions taken

- **The annual EIA-861 census is the baseline panel.** 861M's 97 co-ops are fewer units than
  the broken legacy panel had, and the sample skews to large utilities — i.e. selected
  *against* the small rural co-ops the governance story is about.
- **861M is reserved for the moratorium event study only**, and that design is in doubt.
  69 munis cannot support the falsification half (both co-op and muni differentials compressing
  under moratoria). A co-op-versus-IOU version may survive. Get the state counts before
  deciding.
- **Federal utilities are kept as their own category**, not dropped.
- **Clustering is by state.** County clustering understates uncertainty badly here; IID is
  worse. See §6.

---

## 4. The estimating object

Unit: **utility × state × year** (annual census panel). Years 2015–2024.

```
log(residential kWh per customer)_ust =
    Σ_b β_b · Bin_b,ust
  + Σ_b γ_b · Bin_b,ust × Pov_us
  + Σ_b Σ_k θ_bk · Bin_b,ust × Own_k,u            ← REQUIRED (see §6.1)
  + Σ_b Σ_k ψ_bk · Bin_b,ust × Pov_us × Own_k,u   ← object of interest
  + ρ · Pov_us + Σ_k η_k · Pov_us × Own_k,u       ← REQUIRED
  + Σ_k ζ_k · Own_k,u                             ← REQUIRED (absorbed by FE if time-invariant)
  + Σ_b Bin_b,ust × Controls_us
  + utility-state FE + year FE
  + ε
```

- `Bin_b` = days in the year in temperature bin b, built at county level then weighted up.
- `Pov` = share below 150% FPL, **fixed at the ACS 2015–19 vintage** (pre-COVID, predetermined).
  Pull all vintages too, for a time-varying robustness check.
- `Own_k` = coop, public, federal (IOU omitted).
- Controls interacted with bins: housing age, electric heating share, renter share, rurality.
  These are the ones with a story for changing the *slope*. Do not interact rate structure —
  it is a mediator.

**Annual-panel caveat to state in the data section:** annual sales cannot be split into summer
and winter, so the outcome mixes cooling and heating response. Keep both hot and cold bins so
the two are separately estimated.

---

## 5. Mechanism tests, re-ranked

1. **Within-co-op governance intensity.** Non-residential share of sales interacted with the
   temperature-poverty term. Needs no regulatory variation, no moratoria, no 861M. Compare
   within state to hold regulation fixed. **Build immediately after the baseline.**
2. **Within-state differential protection coverage.** Many state disconnection protections
   reach only PUC-jurisdictional utilities, so in one state the IOU is bound and the co-op is
   not. Triple difference with state fixed effects: heat × poverty × ownership, interacted with
   whether the state's protection reaches non-jurisdictional utilities. Same *content* as the
   moratorium test, cross-ownership variation instead of time variation, lives in the annual
   panel. **This is the main regulation arm now.**
3. **TVA distributors.** ~150 munis and co-ops whose retail rates TVA sets rather than a state
   PUC. Real within-ownership regulatory variation. Confounded with region/climate — restrict
   to counties near the TVA boundary.
4. **Co-op vs muni where neither is rate-regulated.** Regulation constant by construction, so
   any difference is governance. The sign reversal that started the project, finally estimable.
   Confound: munis serve towns, co-ops serve countryside.
5. **Border pairs.** Adjacent co-op and IOU territories within a state. Doesn't decompose the
   mechanism but makes the baseline credible against the rurality critique.
6. **Moratorium event study.** Needs 861M. May not be feasible. Fallbacks: a co-op-only version
   without the muni falsification; an annual "share of year under moratorium" variable.
7. **Regulated vs unregulated co-ops in MN/IN/TX.** Three treated states — almost certainly
   underpowered. Feasibility count only.

**Rate structure as mediator.** URDB (`usurdb.csv.gz`, keyed on `eiaid`) gives fixed charges.
Co-ops have high fixed charges and low volumetric rates. Under Ito (2014) — households respond
to average, not marginal, price — a high fixed charge raises perceived price and suppresses
consumption. This also reconciles Berhe & Mohapatra's higher-burden finding with lower
consumption. Report total and mediated effects as distinct objects; label the mediated one
descriptive.

---

## 6. Standing econometric rules

### 6.1 Saturate every interaction, and prove it

For every triple `D_b × P × Own` in a model, all lower-order terms must be present: `D_b`,
`P`, `Own`, `D_b × P`, `D_b × Own`, `P × Own`. Otherwise the triple absorbs the others and its
value depends on where `P` is centered.

**The invariance test is mandatory before any triple is reported:**

```r
m_dm  <- fit_spec(add_interactions(panel, "poverty_dm"),  SPEC_sat)
m_raw <- fit_spec(add_interactions(panel, "poverty_raw"), SPEC_sat)
stopifnot(isTRUE(all.equal(coef(m_dm)[TRIPLES], coef(m_raw)[TRIPLES])))
```

If it fails, a term is missing. Check whether the ownership dummies vary within the FE unit —
if they do, they need to be in the formula explicitly.

### 6.2 Inference

- **Default: cluster by state.** Treatment (regulation, protections, moratoria) is assigned at
  state level.
- **Wild cluster bootstrap** (restricted, Rademacher, B = 9,999) for every headline coefficient.
  The t-based and bootstrap p-values diverged sharply in Phase 1 (t-based 0.0003 vs bootstrap
  0.32 for bin 9).
- **Never report IID or county-clustered SEs as the default.** IID is diagnostic only — useful
  for splitting the design-matrix channel from the clustering channel, never for a table.
- `fwildclusterboot` 0.14.3 fails on `fixest` models with FE. Workaround: demean y and X on the
  FE once (`fixest::demean`), fit plain OLS, bootstrap that; verify the t-statistics match
  fixest's state-clustered ones.
- **Report point estimates and confidence intervals, not just stars.** An imprecise estimate is
  not a zero. Say "imprecisely estimated, CI [a, b]" rather than "no effect."
- Leave-one-out over **all** co-op states systematically, not a hand-picked three.

### 6.3 Tables

- State clustering as the default; bootstrap p-values alongside.
- When using `etable(keep = ...)`, state underneath which terms are in the model but suppressed.
  "Not shown" and "not in the model" are different and the difference has already caused
  confusion once.
- Keep significance-code thresholds consistent across all tables in a document.

---

## 7. Repo rules

- **Repo is public.** No keys, no raw data, nothing personal. Keys in `.env` (gitignored).
- **Raw data never committed, never edited.** `data/raw/` is a cache; deleting it must be safe,
  and every file re-creatable by a download script.
- **Hand-coded data IS committed** (`data/handcoded/`). Small, irreplaceable, research
  contributions in their own right. Every row carries a source URL.
- Every download appends to `data/raw/MANIFEST.csv`: source, url, local_path, downloaded_at,
  sha256, notes. EIA revises data; vintage matters.
- Scripts numbered and idempotent (skip download if present unless `--force`).
- Every build script ends with validation assertions and prints a short summary (row counts,
  missing shares, key totals). Fail loudly.
- **Commit at the end of every working session.** Phase 2 produced two different values for the
  same county count because nothing was committed and the code path couldn't be traced.

Layout:

```
thesis/
├── CLAUDE.md
├── README.md                # feasibility numbers and decisions, with reasoning
├── .gitignore               # data/raw, data/intermediate, data/final, .env, *.dta, *.parquet
├── .env.example             # CENSUS_API_KEY=
├── config.R / config.py     # paths, YEARS, POVERTY_BASELINE_VINTAGE=2019, TEMP_BINS
├── data/
│   ├── raw/                 # gitignored + MANIFEST.csv
│   ├── intermediate/        # gitignored
│   ├── final/               # gitignored
│   ├── handcoded/           # COMMITTED
│   └── legacy/              # gitignored — frozen seminar panel
├── scripts/
│   ├── 00_legacy/
│   ├── 01_download/         # p2_01_get_eia.R, p2_02_get_eia861m.R, get_acs, get_nclimgrid, get_rucc
│   ├── 02_build/
│   └── 03_analysis/         # p1_00_setup.R, p1_01..p1_03
├── output/{tables,figures,logs}/
└── notes/
```

---

## 8. Phase 4 — the build

One script per component, parquet intermediates, validations at the end of each.

1. **`build_ownership.R`** — utility × state × year → ownership.
   - Read `Utility_Data_YYYY.xlsx` **and** `Short_Form_YYYY.xlsx` for every year (2019: both
     live inside `Utility_Data` with a flag).
   - Columns: `year, utility_id, state, utility_name, ownership_raw, ownership, short_form,
     tva_distributor`.
   - Mapping: `iou` ← Investor Owned; `coop` ← Cooperative; `public` ← Municipal, Political
     Subdivision, State, Municipal Marketing Authority; `federal` ← Federal (**kept**).
     Drop Retail Power Marketer, Behind the Meter, Facility — but **print their residential
     customer counts before dropping**.
   - Deduplicate `(year, utility_id, state)`, preferring the detail record.
   - Flag every utility whose ownership changes across years and inspect by hand. A handful is
     normal; dozens means a parsing bug.
   - Assertions: 875 ≤ co-ops ≤ 895; 1820 ≤ public ≤ 1842; no duplicate keys; ownership never NA.
   - **⏸ CHECK IN** with: the utilities-and-customers-by-ownership-by-year table, the list of
     ownership switchers, and the dropped categories' customer counts.

2. **`build_territory_fips.R`** — utility × state × year → county FIPS.
   - Service territory lists county *names*. Expect: St./Saint, Louisiana parishes, Virginia
     independent cities, Alaska boroughs and census areas, apostrophes and accents, renamings
     (Shannon → Oglala Lakota, 46113 → 46102; 51515 merged into 51019).
   - Print match rate per state and **every unmatched name**. Target ≥99.5%.
   - **⏸ CHECK IN** with the unmatched list.

3. **`build_sales_annual.R`** — residential kWh, revenue, customers from `Sales_Ult_Cust`.
   - Restructured retail states (TX-ERCOT, PA, OH, IL, MD, NY, MA, NJ, CT, DE, DC, ME, NH, RI,
     partial MI): residential load can split between a retail marketer (energy) and the wires
     IOU (delivery). Build a delivery-based series for wires utilities; flag
     `restructured_state` for robustness.
   - Drop short-form-only utilities; report the count and customer share dropped.
   - Derive `nonres_share = (commercial + industrial MWh) / total MWh` — **the governance
     measure** — and `avg_res_price = res_revenue / res_sales`.

4. **`build_acs_county.R`** — Census API, `https://api.census.gov/data/{YEAR}/acs/acs5`.
   - `C17002` (poverty ratio) → `pov150 = (002+003+004+005)/001`; `B25034` (year built);
     `B25040` (heating fuel); `B25003` (tenure); `B01003` (population); `B19013` (median income).
   - Verify labels against `variables.json` before use.
   - Baseline vintage 2019; also pull 2015–2024 for the robustness check.
   - Watch Connecticut (planning regions from the 2022 vintages) and FIPS changes.

5. **`build_temperature_county.R`** — nClimGrid-Daily county area averages.
   - Prefer the EpiNOAA parquet on the public AWS bucket
     `s3://noaa-nclimgrid-daily-pds/EpiNOAA/v1-0-0/parquet/`; fallback
     `https://www.ncei.noaa.gov/data/nclimgrid-daily/access/averages/`.
   - Final ("scaled") values only. Units °C.
   - Recover the seminar's bin edges from `scripts/00_legacy/` so results are comparable
     (nine 5°C bins, right-closed, reference bin 6 = (15,20]°C). Also compute CDD/HDD and
     days above 25°C.
   - **Annual bin counts** per county-year for this panel. AK and HI are not in nClimGrid.

6. **`build_weights.R`** — county population weights from `B01003`. Document that a county
   served by several utilities contributes fully to each — a measurement-error limitation to
   state in the thesis. Later upgrade: service-territory polygons intersected with block-group
   population (also needed for border pairs).

7. **`aggregate_to_utility.R`** — weighted average of county bin **counts** and characteristics
   up to territories. **Never average temperature across counties and then bin.**
   - Also compute and report: **within-state SD of poverty across co-op utilities** — the
     diagnostic from §3.2 that predicts whether precision improves.

8. **`merge_panel.R`** → `data/final/panel_utility_year.parquet` + `CODEBOOK.md`
   (variable, definition, source, unit).

**Phase 5 — re-estimate.** Baseline saturated from the start, state-clustered, bootstrapped,
alongside the county results in one table with the differences explained (ownership correction
vs aggregation vs sample). Then the governance test.

---

## 9. Hand-coded data — priority order

In `data/handcoded/`, committed, every row with a source URL.

1. **`puc_jurisdiction.csv`** — state × ownership type: does the PUC regulate rates? Fully,
   partially (structure not level), or not? Opt-in/opt-out provisions and dates (MN, IN, TX).
   Sources: NARUC state profiles, state statutes. *Backbone of the regulation arm — nothing
   else works without it.*
2. **`standing_protections.csv`** — permanent disconnection rules: heat-based shutoff bans,
   cold-weather rules, notice requirements, arrears provisions. **Critical column: whether the
   protection reaches non-jurisdictional utilities.** Source: LIHEAP Clearinghouse disconnection
   policy tables, NCLC reports.
3. **`tva_distributors.csv`** — the ~150 munis and co-ops whose retail rates TVA sets, keyed on
   EIA `utility_id`. Without it, "unregulated co-op" is false in seven states.
4. **`moratoria.csv`** — 2020–2022, columns `state, order_start, order_end, applies_iou,
   applies_coop, applies_muni, source_url, notes`. Start with **CRS R46401**, which has a
   utility-level table and may save most of the work; then the Energy Justice Lab dashboard
   (utilitydisconnections.org), then state PUC emergency orders. Only after 1–3.

---

## 10. Literature to position against

- **Doremus, Jacqz & Johnston (2022), JEEM** — the energy poverty gap. Household level.
- **Nock et al. (2022), Nature Communications** — "energy equity gap": low-income households
  delay AC activation by 4.7–7.5°F. ~6,000 households, hourly, **one utility** (Salt River
  Project), so ownership is constant by construction. Establishes the phenomenon; cannot ask
  this question.
- **"A utility-level analysis of residential electricity use: Governance, pricing, and incentive
  programs in the Southeastern U.S." (2026), Energy Policy** — closest in unit and treatment.
  Utility-level from EIA-861, ownership types, GA + NC, 105 utilities, cross-sectional OLS.
  **Finds no significant HDD/CDD relationship**, attributed to insufficient climate variation
  across two adjacent states — the best published argument for a national panel design. Also
  finds energy burden associated with *more* consumption after controlling for income.
- **Berhe & Mohapatra** — ownership shares on Gini and burden, adjacent-PUMA border design.
  Cross-sectional, level burden, mechanism "suggestive."
- **"Utility disconnection protections and the incidence of energy insecurity" (2023), iScience**
  — squarely on the regulation arm. Check whether they distinguish protections reaching
  non-jurisdictional utilities.
- **Ito (2014), AER 104(2)** — average vs marginal price. The mechanism linking high co-op
  fixed charges to curtailment.
- **Peltzman (1971), JLE** — fiscal-political mechanism. Predicts muni compression; silent on
  co-ops. Demote to framing the muni side; let the co-op side rest on governance.
- Methods: Cameron/Gelbach/Miller and Abadie/Athey/Imbens/Wooldridge on clustering;
  Deschênes & Greenstone (2011) and Barreca et al. (2016) on temperature bins;
  Solon/Haider/Wooldridge on weighting; Cinelli/Forney/Pearl on good and bad controls.

---

## 11. How to work with Alia

- Explain each step in plain terms before writing code; short, commented functions she can
  maintain.
- Show the first rows and summary statistics of every new dataset.
- **Ask before:** bin edges, the ownership mapping, weighting rules, dropping any utility
  category, or changing the unit of analysis.
- **Do not redesign the research question.** If a data fact threatens a test, report it and
  propose the smallest fallback.
- When a diagnostic contradicts a stated explanation, say so plainly and measure rather than
  guess. Two mechanism hypotheses were already wrong in Phase 1; the IID-vs-clustered split is
  what actually settled it.
- Commit after each working script with a clear message. Never commit data.

---

## 12. Timeline

**October:** Phase 4 build (budget three weeks — it will run long), then baseline, then the
governance test. Regulatory coding (§9 items 1–3) in parallel, evenings.

**November:** Within-state differential-protection design; border-pair feasibility counts;
leave-one-out across all co-op states; the bin 7/9 puzzle from §3.3.

**December draft:** intro and literature; data section including the ownership measurement
finding, the Short Form limitation and the county-versus-utility comparison; empirical
strategy; baseline at utility-year; within-co-op governance test; whatever regulation arm is
ready.

Not in December, and that's fine: the full border triple-difference, the moratorium event
study, anything with mortality.

If time compresses, cut the moratorium work before the baseline or the governance test.
