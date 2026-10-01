# Phase 1 summary — legacy diagnostics of the seminar's Spec 5

**Revision note:** this replaces the first version of this file. That version concluded the
co-op result at 25-30C ("bin 8") was robust. It was wrong: Spec 5 as the seminar ran it omits
terms that turn out to matter, and once they're added the whole finding disappears. Section 7
explains why; section 9 has the corrected bottom line. Nothing here should be read as "the
thesis's co-op finding is dead" — it means this particular county-level, 165-county sample
can't support it, which is exactly the case for the utility-level rebuild (Phase 2+).

Scripts: `scripts/03_analysis/p1_00_setup.R` (shared), `p1_01_replicate_spec5.R`,
`p1_02_robustness.R`, `p1_03_wild_bootstrap.R`.
Data: frozen seminar panel `data/legacy/master_panel_monthly_fc.csv` (county x month,
2015-2024). Estimation sample: 333,127 rows, 2,793 counties, 48 states.

## 1. Two models: Spec 5 (seminar) and the corrected version

Spec 5, as the seminar actually ran it:

```
y_cmt = sum_b  beta_b * D_bcmt                                    (b = 1-5, 7-9)
      + sum_{b in {7,8,9}}  gamma_b   * D_bcmt * P_ct
      + sum_{b in {7,8,9}}  lam_coop_b * D_bcmt * P_ct * Coop_c
      + sum_{b in {7,8,9}}  lam_muni_b * D_bcmt * P_ct * Muni_c
      + X_cmt' delta + alpha_c + tau_t + eps_cmt
```

`SPEC5_sat`, the corrected version, adds every lower-order piece the triple interaction implies
(a "saturated" ownership x poverty x heat design):

```
y_cmt = sum_b  beta_b * D_bcmt
      + sum_{b in {7,8,9}}  gamma_b    * D_bcmt * P_ct
      + sum_{b in {7,8,9}}  kappa_coop_b * D_bcmt * Coop_c        (bin x coop, no poverty)
      + sum_{b in {7,8,9}}  kappa_muni_b * D_bcmt * Muni_c
      + rho * P_ct + eta_coop * P_ct * Coop_c + eta_muni * P_ct * Muni_c
      + zeta_coop * Coop_c + zeta_muni * Muni_c
      + sum_{b in {7,8,9}}  lam_coop_b * D_bcmt * P_ct * Coop_c
      + sum_{b in {7,8,9}}  lam_muni_b * D_bcmt * P_ct * Muni_c
      + X_cmt' delta + alpha_c + tau_t + eps_cmt
```

- `y`, `D_b`, `P`, `Coop`/`Muni`, `X`, `alpha_c`, `tau_t` are as before (see the variable
  definitions below). `Coop_c`, `Muni_c` are (almost) time-invariant: only 14 of 2,793 counties
  change `is_coop` and 1 changes `is_muni` over the panel, since ownership is redefined every
  month as "utility with the most residential customers."
- `P` = share of population below 150% of the poverty line (ACS 5-yr, S1701). Two versions
  used: yearly (the seminar's), and each county's ACS 2015-19 value held fixed (`pov19_dm`).
- `zeta_coop`, `zeta_muni` are absorbed by `alpha_c` in the 2,778 counties whose ownership never
  changes; they matter only for the 15 that switch.

**Why the extra terms matter.** `lam_coop_b` is only "the poverty gap in co-op counties" if
`kappa_coop_b` and `eta_coop` are also in the model. Otherwise `lam_coop_b` also captures (a) how
co-op counties respond to heat regardless of poverty, and (b) how poverty affects co-op counties
regardless of heat. Spec 5 has neither, so its `lam_coop_b` is a mixture of three different
things, not a clean poverty-gap estimate.

## 2. Replication of Spec 5 (unchanged, still holds)
Matches the seminar exactly: N = 333,127, 2,793 counties. Co-op triples: bin 8 = -0.0248,
bin 9 = -0.0377; muni bin 9 = +0.0476. Row filter: drop a row missing the outcome, poverty,
precipitation, any bin, or any of the six demographic controls.

## 3. The specification bug, and how it was found
Demeaning `P` by a constant `a` should not change `lam_coop_b` if the model is complete — the
shift is absorbed by whichever lower-order term it multiplies. Spec 5 is missing `D_b x Coop`
and `P x Coop`, so a `P`-recentering leaks into `lam_coop_b` directly. Testing this (shifting
poverty by +0.10, then comparing raw vs demeaned poverty) is what surfaced the missing terms:
Spec 5's co-op triples moved by up to 0.02 under recentering alone — the same size as the
effect being interpreted. After adding `D_b x Coop`, `D_b x Muni`, `P x Coop`, `P x Muni`, `P`,
`Coop`, and `Muni` to the model (`SPEC5_sat`), coefficients became invariant to recentering
(raw vs demeaned poverty, co-op triples, `all.equal` -> `TRUE`).

## 4. The corrected model's full ownership-related coefficient table
`SPEC5_sat`, state-clustered SEs, yearly (seminar) poverty, N = 333,127:

| Term | Estimate | SE | p |
|---|---|---|---|
| bin7 x coop | -0.0059 | 0.0026 | 0.027 |
| bin8 x coop | -0.0012 | 0.0020 | 0.540 |
| bin9 x coop | -0.0075 | 0.0031 | 0.020 |
| bin7 x muni | -0.0067 | 0.0014 | <0.001 |
| bin8 x muni | -0.0009 | 0.0014 | 0.511 |
| bin9 x muni | -0.0048 | 0.0017 | 0.008 |
| P (main effect) | +0.2092 | 0.0587 | 0.001 |
| Coop (main effect) | +0.1001 | 0.0535 | 0.068 |
| Muni (main effect) | +0.1365 | 0.0321 | <0.001 |
| P x Coop | +0.0901 | 0.1378 | 0.517 |
| P x Muni | -0.1268 | 0.2245 | 0.575 |
| **bin7 x P x Coop** | -0.0028 | 0.0160 | 0.862 |
| **bin8 x P x Coop** | -0.0251 | 0.0163 | 0.131 |
| **bin9 x P x Coop** | -0.0110 | 0.0163 | 0.503 |
| **bin7 x P x Muni** | +0.0162 | 0.0144 | 0.265 |
| **bin8 x P x Muni** | -0.0104 | 0.0091 | 0.258 |
| **bin9 x P x Muni** | +0.0200 | 0.0148 | 0.182 |

**None of the six triples (bold) is significant.** Poverty itself is associated with *more*
electricity use per customer (+0.21, p=0.001) — a level effect Spec 5 couldn't show because it
had no `P` main effect. Co-op and municipal counties use *less* extra electricity on the two
coldest-of-the-hot bins (7 and 9, both ownership types), independent of poverty — this is what
Spec 5's missing terms were letting the triples absorb.

## 5. Standard errors and clustering
Errors within a state are likely correlated (shared weather, prices, rate cases, disconnection
rules), so we cluster by state (G=48) rather than county (G=2,793, the seminar's choice, which
assumes independence across counties in the same state and understates uncertainty).

Muni bin 8, `SPEC5_sat`, demeaned poverty — the clustering choice changes the conclusion:

| | Estimate | SE | p |
|---|---|---|---|
| IID (no clustering) | -0.0104 | 0.0031 | **<0.001** |
| Clustered by state | -0.0104 | 0.0091 | **0.258** |

Same coefficient, opposite conclusion. This is the general risk of not clustering by state:
118 municipal counties sit in only 10 states, so IID SEs treat them as far more independent
information than they are.

## 6. Wild cluster bootstrap (48 clusters, B=9,999), `SPEC5_sat`
Same restricted Rademacher bootstrap as before (see the implementation note below), now run on
the corrected model's co-op triples:

| Co-op triple | Estimate | t (state) | Bootstrap p | 95% CI |
|---|---|---|---|---|
| bin 7 | -0.003 | -0.18 | 0.89 | [-0.041, 0.045] |
| bin 8 | -0.025 | -1.54 | 0.43 | [-0.070, 0.015] |
| bin 9 | -0.011 | -0.68 | 0.57 | [-0.260, 0.196] |

None survives. For comparison, under the (incomplete) Spec 5 the same bootstrap gave bin 8
p=0.021 — a result driven by the omitted terms, not by the poverty gap.

*Implementation note:* `fwildclusterboot` 0.14.3 fails on `fixest` models with fixed effects.
By Frisch-Waugh-Lovell, demeaning y and X on the county and year effects once (`fixest::demean`)
and fitting plain OLS gives identical coefficients and t-statistics, so we bootstrap that. The
script checks the demeaned model's t-statistics equal fixest's state-clustered ones directly.

## 7. Leave-out robustness, `SPEC5_sat`, co-op triples (state-clustered SE)

| | All | No TX | No TX,KS | No TN | No TN,KS,TX |
|---|---|---|---|---|---|
| bin 7 | -0.003 (0.016) | 0.000 (0.016) | 0.016 (0.013) | -0.004 (0.015) | 0.011 (0.013) |
| bin 8 | -0.025 (0.016) | -0.028 (0.019) | -0.006 (0.009) | -0.041* (0.012) | -0.016. (0.008) |
| bin 9 | -0.011 (0.016) | -0.052 (0.111) | -0.011 (0.069) | 0.003 (0.008) | 0.095 (0.059) |

No consistent story: bin 8 is significant only when Tennessee is dropped, insignificant
everywhere else including "all states." Bin 9 has no consistent sign at all, unlike the
Spec-5 version (section 5 of the earlier draft), where it was negative in 4 of 5 leave-outs.
The earlier "bin 8 is robust to dropping large states" conclusion was a property of the
incomplete model, not of the data.

## 8. Poverty fixed at 2019, `SPEC5_sat`
`pov19_dm` = each county's ACS 2015-19 poverty share, demeaned, replacing yearly `P_ct`.
`fixest` drops `P` and `P x Muni` automatically ("removed because of collinearity") since
municipal ownership never changes within a county in this sample and 2019 poverty is therefore
collinear with the county fixed effect; `P x Coop` survives because 14 counties switch coop
status. N = 332,847 (280 rows / 11 counties lack a 2019 value).

| Co-op triple | Yearly P | P fixed at 2019 |
|---|---|---|
| bin 7 | -0.0028 (0.0160) | -0.0033 (0.0166) |
| bin 8 | -0.0251 (0.0163) | -0.0254 (0.0171) |
| bin 9 | -0.0110 (0.0163) | -0.0132 (0.0113) |

Barely moves either way: fixing poverty at 2019 doesn't rescue the result, because there was no
significant result to rescue in the corrected model.

## 9. What we can and cannot conclude
- **Does not hold:** a co-op- or muni-specific poverty gap in electricity use on hot days, at
  any bin, under any clustering, leave-out, or poverty-timing choice, once the model includes
  the terms Spec 5 omitted. The seminar's headline number was an artifact of specification, not
  a real effect visible in this data.
- **A different, smaller finding that may be real:** co-op and municipal counties show *less*
  extra electricity use on hot days than IOU counties, *independent of poverty* (bin7/bin9 x
  coop/muni, section 4). This hasn't been stress-tested (no bootstrap, no leave-out) and is a
  different claim from a poverty gap — it says ownership matters for the average household, not
  specifically for poor ones.
- **Mechanical finding, worth keeping:** county-level clustering badly understates uncertainty
  here relative to state clustering, and IID SEs are worse still (section 5). Any table in the
  thesis should show state-clustered (or bootstrapped) SEs as the default, not IID or county.
- **Sample limitation, unchanged:** this is the 165 co-op-dominated / 117 muni-dominated
  counties from the flawed "largest utility by customers" ownership assignment. The rebuild
  (utility-level, full 861 census) is the real test of whether an ownership effect exists —
  this dataset was probably always too thin (few states with co-op or muni variation, see the
  concentration figures in the discarded draft) to answer the question either way.

## 10. Not yet done
- Bootstrap the muni triples (only co-op was bootstrapped).
- County-by-month FE (the write-up's stated version) vs. county FE + month dummies (the code's
  actual version) — still an open discrepancy, untested in `SPEC5_sat`.
- Interact controls (income, race, education, unemployment) with the bins, per CLAUDE.md's
  design.
- Leave-one-out over all co-op/muni states systematically, not just TX/KS/TN.
- Decide whether the "ownership matters independent of poverty" finding (section 9) is worth a
  robustness pass of its own before the December draft, or whether it's set aside until the
  utility-level rebuild.
