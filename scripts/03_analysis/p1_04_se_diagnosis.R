# Phase 1, step 5: why did the bin8 co-op triple's SE roughly double going from
# SPEC5 to SPEC5_sat? Two hypotheses tested and rejected, then the actual cause
# (the clustering channel, not the design-matrix channel) confirmed directly.
# See CLAUDE.md section 3.2 for the written-up conclusion this reproduces.

source("scripts/03_analysis/p1_00_setup.R")

panel <- load_panel()
df    <- add_interactions(panel, "poverty_dm")
TRIPLE <- "bin8_25to30_x_pov_coop"

# ---- Hypothesis 1: thin poverty variation within co-ops? --------------------
# If co-ops had a narrower spread of poverty than IOUs, the triple would be
# poorly identified for a trivial reason. Rejected if co-op SD >= IOU SD.
pov_sd <- df[, .(poverty_sd = round(sd(poverty_dm), 4)),
             by = .(group = fifelse(is_coop == 1, "coop",
                             fifelse(is_muni == 1, "muni", "iou")))]
cat("==== H1: poverty SD by ownership (rejected if coop >= iou) ====\n")
print(pov_sd)

# ---- Hypothesis 2: collinear with its own lower-order term? -----------------
# Correlation between the triple and bin8 x coop, AFTER removing the FIPS and
# year fixed effects (the within-variation that actually identifies both).
X  <- as.matrix(df[, .(triple = get(TRIPLE), lower = bin8_25to30_x_coop)])
Xd <- demean(X, df[, .(FIPS, year)])
r   <- cor(Xd[, "triple"], Xd[, "lower"])
vif <- 1 / (1 - r^2)
cat("\n==== H2: triple vs. its lower-order term, within FE (rejected if VIF ~ 1) ====\n")
cat("Correlation:", round(r, 3), "| VIF:", round(vif, 3), "\n")

# ---- The actual cause: the clustering channel -------------------------------
# Same coefficient, both specs, both an IID and a state-clustered vcov. If the
# design matrix itself were the problem, IID SEs would blow up similarly going
# from SPEC5 to SPEC5_sat. They barely move; only the clustered SE does --
# i.e. once D_b x Coop is in the model, what's left to identify the triple is
# concentrated in something that covaries mostly BETWEEN states.
m5     <- fit_spec(df, SPEC5)
m5_sat <- fit_spec(df, SPEC5_sat)

se_iid    <- c(SPEC5 = se(m5, vcov = "iid")[TRIPLE],  SPEC5_sat = se(m5_sat, vcov = "iid")[TRIPLE])
se_state  <- c(SPEC5 = se(m5, vcov = ~state)[TRIPLE], SPEC5_sat = se(m5_sat, vcov = ~state)[TRIPLE])
inflation <- se_state / se_iid

cat("\n==== The clustering channel ====\n")
print(round(rbind(IID_SE = se_iid, state_clustered_SE = se_state,
                  cluster_inflation_factor = inflation), 5))
cat("\nIID SE change, SPEC5 -> SPEC5_sat:",
    sprintf("%+.1f%%", 100 * (unname(se_iid[2]) / unname(se_iid[1]) - 1)), "\n")
cat("Cluster inflation factor change:",
    round(unname(inflation[1]), 2), "->", round(unname(inflation[2]), 2), "\n")

# ---- Complementary: how state-clustered is co-op poverty, concretely? -------
# Share of co-op counties' poverty_dm variance explained by state alone
# (one-way ANOVA / R-squared on state dummies), and the number of co-op
# states in THIS (legacy, flawed-ownership) panel specifically.
coop_df <- df[is_coop == 1]
icc_fit <- lm(poverty_dm ~ factor(state), data = coop_df)
cat("\n==== Complementary: how state-clustered is co-op poverty here? ====\n")
cat("Co-op counties' poverty_dm variance explained by state dummies (R2):",
    round(summary(icc_fit)$r.squared, 3), "\n")
cat("Number of states with >=1 co-op county in this legacy panel:", uniqueN(coop_df$state), "\n")
