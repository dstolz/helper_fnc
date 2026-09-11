# ecm_analysis.R -------------------------------------------------------------
#
# Import the GM6001 ECM (WFA-PV) cortical depth profiles, visualize them, fit
# mixed-effects models, and write a self-describing HTML report.
#
# OUTPUT
#   Everything lands in FIG_DIR (below):
#       ECM_GM6001_report.html   figures + statistics, each with a one-line
#                                description of what it shows and how to read it
#       p1.png ... p7.png        the same figures as standalone images
#   The report links the PNGs relatively, so keep the HTML in the same folder
#   as the images (or copy the whole folder) when sharing it. The console
#   transcript is unchanged: every number in the report is also printed there.
#
# A NOTE ON THE INPUT FILE
#   The source of truth is "ECM Projects - GM6001 - full.mat": an 85 x 52 table
#   that nests a 1148 x 2 (Distance, Intensity) profile table inside a cell on
#   every row. R cannot read it -- R.matlab handles numeric MAT variables but
#   not MATLAB table objects -- and neither can a single CSV, because no flat
#   format holds that nesting. Exporting it with writetable does not error; it
#   silently writes 1148 empty fields per row and shifts every column after
#   Profile out of alignment with the header, losing all 110762 samples.
#
#   So run the companion exporter once, in MATLAB:
#       ecm_export_for_r()
#   It unnests the profiles and writes the two plain CSVs this script reads:
#       ECM Projects - GM6001 - profiles.csv   110762 rows, one per sample
#       ECM Projects - GM6001 - sections.csv       85 rows, one per section
#   check_flat_csv() below refuses a flattened export if one turns up anyway.
#
# DESIGN
#   10 subjects x 2 hemispheres, 3-5 sections each (85 total), atlas plates
#   27-33. Trained subjects got GM6001 in one hemisphere and Vehicle in the
#   other; control subjects got neither (Treatment "Control L"/"Control R").
#   Treatment is therefore partly confounded with Hemisphere.
#
#   CannulaDist is the section plate minus that hemisphere's cannula plate, but
#   read the QC before using it: control animals were never implanted, yet they
#   carry a CannulaDist anyway -- there it is simply AtlasPlate - 30, perfectly
#   collinear with a term already in the model. has_cannula separates the
#   sections where the number means what its name says from the ones where it
#   does not. Both issues are handled explicitly below.
#
# TWO BANDS
#   Each profile carries a bright superficial WFA band peaking a few hundred
#   microns below pia, and a smaller second band around 1200-1400 um. They are
#   quantified separately -- PEAK_WINDOW and DEEP_WINDOW below -- because the
#   deep one sits near the far end of the ROI: it exists only for the sections
#   whose aligned depth reaches that far, so every deep-band number is
#   restricted to those sections and says so.
# ----------------------------------------------------------------------------

# 1. Setup -------------------------------------------------------------------

required <- c("readr", "dplyr", "tidyr", "ggplot2", "scales",
              "lme4", "lmerTest", "emmeans", "splines")
missing_pkgs <- setdiff(required, rownames(installed.packages()))
if (length(missing_pkgs)) {
  stop("Install first:  install.packages(c(",
       paste0(dQuote(missing_pkgs, FALSE), collapse = ", "), "))")
}

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr); library(ggplot2)
  library(scales); library(lme4); library(lmerTest); library(emmeans)
  library(splines)
})

DATA_DIR <- "D:/GM6001_HISTOLOGY"
FIG_DIR  <- file.path(DATA_DIR, "R_figures")
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)

REPORT_PATH <- file.path(FIG_DIR, "ECM_GM6001_report.html")

profiles_csv <- file.path(DATA_DIR, "ECM Projects - GM6001 - profiles.csv")
sections_csv <- file.path(DATA_DIR, "ECM Projects - GM6001 - sections.csv")
if (!file.exists(profiles_csv)) {
  stop("Missing ", profiles_csv,
       "\nRun ecm_export_for_r() in MATLAB first (see header).")
}

# Guard against being handed the wide "full" export by mistake. A flattened
# nested-table CSV parses without complaint but is silently unusable, so check
# the header against the first data row rather than trusting the file name.
check_flat_csv <- function(path) {
  # readLines rather than an open connection: scanning a connection and then
  # erroring out of it can take the R session down.
  two <- readLines(path, n = 2, warn = FALSE)
  fields <- function(s) length(scan(text = s, what = "", sep = ",",
                                    quiet = TRUE, quote = "\""))
  hdr <- scan(text = two[1], what = "", sep = ",", quiet = TRUE, quote = "\"")
  row <- fields(two[2])
  if (row != length(hdr)) {
    stop(basename(path), " has ", length(hdr), " column names but ",
         row, " fields in its first data row.\n",
         "This is the flattened nested-Profile export -- the profile samples ",
         "are gone and the\ntrailing metadata columns are shifted. ",
         "Re-export with ecm_export_for_r().")
  }
  if (!all(c("Distance", "Intensity") %in% hdr)) {
    stop(basename(path), " has no Distance/Intensity columns; it is not the ",
         "long profile export.\nRe-export with ecm_export_for_r().")
  }
  invisible(TRUE)
}
check_flat_csv(profiles_csv)

theme_set(theme_bw(base_size = 11) +
          theme(panel.grid.minor = element_blank(),
                strip.background = element_rect(fill = "grey92", color = NA)))

# Treatment palette: the two infused arms warm/cool, the two control arms grey.
tx_colors <- c("Vehicle"   = "#2E86AB", "GM6001"    = "#C0392B",
               "Control L" = "#9AA5B1", "Control R" = "#5D6D7E")

# 1b. Report machinery -------------------------------------------------------
#
# Three helpers collect the run into an HTML document while leaving the console
# transcript intact:
#   sec(title, desc)          a section heading with a short description
#   stat(title, desc, expr)   run expr, echo whatever it prints, and file that
#                             text under a captioned block in the report
#   fig(name, plot, ...)      save a PNG beside the report and embed it
# Nothing downstream has to know about the report: strip these three wrappers
# and the script still runs and prints exactly the same numbers.

.rep <- new.env(parent = emptyenv())
.rep$body <- character()   # HTML fragments, in order
.rep$toc  <- character()   # table-of-contents entries
.rep$nfig <- 0L
.rep$ntab <- 0L

esc_html <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;",  x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}
rp <- function(...) .rep$body <- c(.rep$body, ...)

# Wrap prose at the console the way the rest of the script's output reads.
say <- function(txt) cat(paste(strwrap(txt, width = 78), collapse = "\n"), "\n")

sec <- function(title, desc = NULL) {
  id <- sprintf("sec%d", length(.rep$toc) + 1L)
  .rep$toc <- c(.rep$toc, sprintf('<li><a href="#%s">%s</a></li>',
                                  id, esc_html(title)))
  rp(sprintf('<h2 id="%s">%s</h2>', id, esc_html(title)))
  if (!is.null(desc)) rp(sprintf('<p class="desc">%s</p>', esc_html(desc)))
  cat(sprintf("\n\n================ %s ================\n", title))
  if (!is.null(desc)) say(desc)
  invisible(NULL)
}

# Evaluate expr once, capture what it prints, and put it in the report under a
# caption and a description. withVisible() reproduces top-level behavior: a
# visible result is printed, a cat()-only block is not double-printed with a
# trailing NULL. Warnings and messages are muffled and appended to the block,
# so notes like "boundary (singular) fit" travel with the model they came from.
stat <- function(title, desc, expr) {
  notes <- character()
  out <- withCallingHandlers(
    capture.output({
      v <- withVisible(expr)
      if (v$visible) print(v$value)
    }),
    warning = function(w) {
      notes <<- c(notes, paste("Warning:", conditionMessage(w)))
      invokeRestart("muffleWarning")
    },
    message = function(m) {
      notes <<- c(notes, sub("\n$", "", conditionMessage(m)))
      invokeRestart("muffleMessage")
    })
  .rep$ntab <- .rep$ntab + 1L
  lab <- sprintf("Output %d. %s", .rep$ntab, title)
  txt <- paste(c(out, if (length(notes)) c("", notes)), collapse = "\n")
  rp(sprintf(paste0('<div class="block"><p class="lab">%s</p>',
                    '<p class="desc">%s</p><pre>%s</pre></div>'),
             esc_html(lab), esc_html(desc), esc_html(txt)))
  cat(sprintf("\n-- %s --\n", lab)); say(desc); cat(txt, "\n", sep = "")
  invisible(out)
}

fig <- function(name, plot, title, desc, w = 9, h = 5.5) {
  path <- file.path(FIG_DIR, paste0(name, ".png"))
  suppressMessages(ggsave(path, plot, width = w, height = h, dpi = 200))
  .rep$nfig <- .rep$nfig + 1L
  lab <- sprintf("Figure %d. %s", .rep$nfig, title)
  rp(sprintf(paste0('<figure><img src="%s" alt="%s">',
                    '<figcaption><span class="lab">%s</span> %s</figcaption>',
                    '</figure>'),
             basename(path), esc_html(title), esc_html(lab), esc_html(desc)))
  cat(sprintf("\n[%s -> %s]\n", lab, basename(path))); say(desc)
  invisible(path)
}

report_write <- function(n_sections, n_subjects) {
  css <- "
body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
     max-width:1080px;margin:2.5rem auto;padding:0 1.25rem;color:#1b1f23;
     line-height:1.5;background:#fff}
h1{font-size:1.6rem;margin-bottom:.2rem}
h2{font-size:1.15rem;margin-top:2.4rem;padding-bottom:.25rem;
   border-bottom:2px solid #d8dee4}
p.sub{color:#57606a;margin-top:0}
p.desc{color:#3a4149;margin:.35rem 0 .6rem;max-width:78ch}
p.lab{font-weight:600;color:#57606a;margin:0}
span.lab{font-weight:600}
.block{margin:1.1rem 0 1.6rem}
pre{background:#f6f8fa;border:1px solid #d8dee4;border-radius:5px;
    padding:.7rem .85rem;overflow-x:auto;font-size:.8rem;line-height:1.35;
    font-family:Consolas,Menlo,monospace}
figure{margin:1.2rem 0 1.8rem}
figure img{width:100%;border:1px solid #d8dee4;border-radius:5px}
figcaption{color:#3a4149;font-size:.9rem;margin-top:.45rem;max-width:88ch}
nav ol{columns:2;font-size:.92rem}
nav a{color:#0a58ca;text-decoration:none}
footer{margin-top:3rem;border-top:1px solid #d8dee4;padding-top:.8rem;
       color:#57606a;font-size:.82rem}
@media print{body{max-width:none;margin:0}pre{font-size:.7rem}
  figure,.block{break-inside:avoid}}
"
  html <- c(
    '<!doctype html><html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>GM6001 ECM (WFA-PV) depth profiles</title>',
    sprintf('<style>%s</style></head><body>', css),
    '<h1>GM6001 ECM (WFA-PV) cortical depth profiles</h1>',
    sprintf('<p class="sub">%s &middot; %d sections, %d subjects &middot; %s</p>',
            format(Sys.time(), "%Y-%m-%d %H:%M"), n_sections, n_subjects,
            esc_html(DATA_DIR)),
    paste0('<p class="desc">Generated by ecm_analysis.R. The line above each ',
           'block says what it shows and how to read it; figures are also ',
           'written as PNGs beside this file.</p>'),
    '<nav><h2 style="border:none;margin-top:1.4rem">Contents</h2><ol>',
    .rep$toc, '</ol></nav>',
    .rep$body,
    sprintf(paste0('<footer>ecm_analysis.R &middot; %s &middot; lme4 %s, ',
                   'lmerTest %s, emmeans %s</footer>'),
            R.version.string,
            as.character(packageVersion("lme4")),
            as.character(packageVersion("lmerTest")),
            as.character(packageVersion("emmeans"))),
    '</body></html>')
  writeLines(html, REPORT_PATH)
  invisible(REPORT_PATH)
}

# 2. Import ------------------------------------------------------------------

# Column types are given explicitly: SectionID ("1A") and Slide would otherwise
# be guessed inconsistently, and IncludeInAnalysis arrives as literal
# TRUE/FALSE strings.
prof <- read_csv(
  profiles_csv,
  col_types = cols_only(
    Stem              = col_character(),
    SubjectID         = col_character(),
    Hemisphere        = col_character(),
    SectionID         = col_character(),
    SampleID          = col_character(),
    AtlasPlate        = col_double(),
    Treatment         = col_character(),
    Condition         = col_character(),
    Sex               = col_character(),
    CannulaDist       = col_double(),
    LeftCannulaPlate  = col_double(),
    RightCannulaPlate = col_double(),
    InfusionQuality   = col_character(),
    IncludeInAnalysis = col_logical(),
    PixelSize         = col_double(),
    RoiWidth          = col_double(),
    RoiLength         = col_double(),
    NSamples          = col_integer(),
    SampleIndex       = col_integer(),
    Distance          = col_double(),
    Intensity         = col_double()
  ),
  progress = FALSE
) |>
  rename(distance_um = Distance, intensity = Intensity) |>
  mutate(
    SubjectID  = factor(SubjectID),
    Hemisphere = factor(Hemisphere, levels = c("L", "R")),
    Condition  = factor(Condition,  levels = c("Control", "Trained")),
    Sex        = factor(Sex),
    # Vehicle is the reference: it is the within-animal counterpart to GM6001.
    Treatment  = factor(Treatment,
                        levels = c("Vehicle", "GM6001", "Control L", "Control R")),
    # One id per imaged section, and one per hemisphere within subject. The
    # latter is the grouping the random-effects structure actually needs.
    section_id = factor(Stem),
    subj_hemi  = factor(paste(SubjectID, Hemisphere, sep = "_")),
    # Center the continuous fixed effects so the intercept sits mid-range for
    # plate, and at the cannula plate itself for distance.
    AtlasPlate_c  = AtlasPlate - 30,
    CannulaDist_c = CannulaDist,
    # The cannula plate for THIS hemisphere, and whether one exists at all.
    # CannulaDist is populated for control sections too, but those animals were
    # never implanted (both plate columns are NA), so there it is a nominal
    # offset from plate 30 rather than a distance from anything. See the QC
    # below -- this flag is what separates the two meanings.
    cannula_plate = if_else(Hemisphere == "L", LeftCannulaPlate, RightCannulaPlate),
    has_cannula   = !is.na(cannula_plate)
  )

sections <- read_csv(sections_csv, col_types = cols(.default = col_guess()),
                     progress = FALSE)

# 2b. Surface alignment ------------------------------------------------------

# Distance is microns along the line ROI, and the ROI is drawn from OUTSIDE the
# section inward -- so every profile opens on a few hundred microns of
# background at intensity ~0, and raw distance is not depth. Sections differ in
# how much background they carry, so they have to be aligned on the tissue edge
# before any of them are averaged together.
#
# This is the "threshold" rule from ecm_prepare_analysis_data.m and uses the
# same defaults: the surface is the LAST sample below SURFACE_THRESHOLD inside
# the first SURFACE_SEARCH microns, i.e. the last background sample before the
# tissue starts. Change these here and in the MATLAB call together, or the two
# pipelines will disagree.
SURFACE_THRESHOLD <- 1     # intensity counted as background
SURFACE_SEARCH    <- 500   # um from the start of the profile to search within

prof <- prof |>
  group_by(section_id) |>
  arrange(distance_um, .by_group = TRUE) |>
  mutate(
    surface_um = {
      w <- which(distance_um - first(distance_um) <= SURFACE_SEARCH &
                   intensity < SURFACE_THRESHOLD)
      # No sub-threshold sample means no detectable edge: fall back to the
      # first sample, which is the MATLAB "first" fallback.
      if (length(w)) distance_um[max(w)] else first(distance_um)
    },
    depth_um = distance_um - surface_um
  ) |>
  ungroup()

surf <- prof |> distinct(section_id, surface_um)

# Everything downstream is on aligned depth; the pre-surface samples are
# background and are dropped.
prof <- prof |> filter(depth_um >= 0)

# 3. QC and design summary ---------------------------------------------------

sec("Data, alignment and QC",
    paste("What was read in, where each profile's pial surface was placed, and",
          "whether the design variables mean what their names say. Read this",
          "before the models: two of the checks below constrain which terms",
          "can legally go in the same model."))

stat("Import and depth range",
     paste0("Sample, section and subject counts after import, and the span of ",
            "aligned depth and raw intensity. Depth is measured from the ",
            "detected pial surface, so it starts at 0 by construction."),
     {
       cat(sprintf("%d samples across %d sections, %d subjects\n",
                   nrow(prof), nlevels(prof$section_id), nlevels(prof$SubjectID)))
       cat(sprintf("aligned depth %.0f-%.0f um, intensity %.1f-%.1f\n",
                   min(prof$depth_um), max(prof$depth_um),
                   min(prof$intensity), max(prof$intensity)))
     })

stat("Surface offsets",
     paste0("How much background each ROI carried before the tissue edge (the ",
            "last sample below intensity ", SURFACE_THRESHOLD, " within the ",
            "first ", SURFACE_SEARCH, " um). More than a handful of sections ",
            "at 0 means the edge rule is failing and profiles are being ",
            "averaged misaligned."),
     cat(sprintf("median %.0f um, range %.0f-%.0f um, %d of %d at 0\n",
                 median(surf$surface_um), min(surf$surface_um),
                 max(surf$surface_um), sum(surf$surface_um == 0), nrow(surf))))

stat("Sections per Treatment x Hemisphere",
     paste0("The design, and the confound: each trained animal contributes ",
            "GM6001 in one hemisphere and Vehicle in the other, while the two ",
            "control arms are defined by hemisphere. Treatment is therefore ",
            "only partly separable from Hemisphere between animals -- but ",
            "fully separable within a trained animal."),
     print(sections |> count(Treatment, Hemisphere) |>
             pivot_wider(names_from = Hemisphere, values_from = n,
                         values_fill = 0)))

cannula_qc <- prof |>
  distinct(section_id, Condition, Treatment, AtlasPlate, CannulaDist,
           cannula_plate, has_cannula) |>
  group_by(Condition, Treatment) |>
  summarise(n = n(),
            n_implanted = sum(has_cannula),
            n_missing_dist = sum(is.na(CannulaDist)),
            dist_range = if (all(is.na(CannulaDist))) "-" else
              sprintf("%g to %g", min(CannulaDist, na.rm = TRUE),
                      max(CannulaDist, na.rm = TRUE)),
            # If CannulaDist is just AtlasPlate shifted by a constant, that
            # constant is the same for every section in the group.
            implied_ref = {
              r <- unique(AtlasPlate - CannulaDist)
              if (length(r) == 1 && !is.na(r)) as.character(r) else "varies"
            },
            .groups = "drop")

stat("CannulaDist: is it backed by an actual cannula?",
     paste0("n_implanted counts the sections whose hemisphere has a cannula ",
            "plate on record. Where it is 0 but a CannulaDist exists, that ",
            "number is a nominal offset from the implied_ref plate, not a ",
            "distance from an infusion site -- and a single implied_ref value ",
            "means it is AtlasPlate minus a constant, i.e. the same variable."),
     {
       print(cannula_qc)
       if (any(cannula_qc$n_implanted == 0 & cannula_qc$n_missing_dist == 0)) {
         cat("\nWARNING: some groups carry a CannulaDist with no cannula plate\n",
             "behind it. Do not fit AtlasPlate and CannulaDist together over\n",
             "all sections; see Models 1, 1b and 2 below.\n", sep = "")
       }
     })

stat("cor(AtlasPlate, CannulaDist) by condition",
     paste0("The size of that collinearity. r = 1 in controls confirms the two ",
            "are one variable there; the trained value shows how much ",
            "independent information CannulaDist carries where a cannula ",
            "actually exists."),
     print(prof |>
             distinct(section_id, Condition, AtlasPlate, CannulaDist) |>
             filter(!is.na(CannulaDist)) |>
             group_by(Condition) |>
             summarise(n = n(), r = round(cor(AtlasPlate, CannulaDist), 3),
                       .groups = "drop")))

# 4. Per-section summaries ---------------------------------------------------

# Profiles are noisy sample to sample, so the peak is taken from a centered
# rolling mean rather than the raw trace. stats::filter keeps this dependency
# free; it returns NA at both ends, which na.rm drops from the peak search.
roll_mean <- function(x, k = 25) {
  as.numeric(stats::filter(x, rep(1 / k, k), sides = 2))
}

# Extreme of a (smoothed) trace inside a depth window, returned as the value
# and the depth it occurs at. NA rather than -Inf when the window holds no
# usable sample: the deep window sits at the far end of the ROI, where a
# section that ran out of tissue has nothing at all, and max() over an empty
# vector would quietly turn a truncation into a data point. Passing which.min
# finds the trough between the two bands instead.
band_at <- function(y, x, lo, hi, f = which.max) {
  w <- which(x >= lo & x <= hi & !is.na(y))
  if (!length(w)) return(c(val = NA_real_, at = NA_real_))
  i <- w[f(y[w])]
  c(val = y[i], at = x[i])
}

PEAK_WINDOW   <- c(0, 800)      # um, where the superficial WFA band sits
DEEP_WINDOW   <- c(1200, 1400)  # um, the smaller second band deeper in the
                                # column. On aligned depth, like everything
                                # else here, so move it as one piece if the
                                # feature sits elsewhere in a future dataset.
TROUGH_WINDOW <- c(PEAK_WINDOW[2], DEEP_WINDOW[1])  # the dip between the two
DEPTH_WINDOW  <- c(0, 1200)  # um retained for mean / AUC and for the
                             # depth-resolved model: past this, coverage thins
                             # as sections run out of tissue. The deep band is
                             # analyzed separately, on the sections that do
                             # reach it, rather than by extending this.

prof <- prof |>
  group_by(section_id) |>
  arrange(depth_um, .by_group = TRUE) |>
  mutate(intensity_s = roll_mean(intensity, 25)) |>
  ungroup()

sect <- prof |>
  group_by(section_id, SubjectID, Hemisphere, subj_hemi, SectionID, SampleID,
           Treatment, Condition, Sex, AtlasPlate, AtlasPlate_c,
           CannulaDist, CannulaDist_c, cannula_plate, has_cannula,
           InfusionQuality, IncludeInAnalysis) |>
  summarise(
    n_samples  = n(),
    # How far this section's aligned depth actually reaches, which is what
    # decides whether the deep band was imaged at all.
    max_depth  = max(depth_um),
    peak_int   = band_at(intensity_s, depth_um,
                         PEAK_WINDOW[1], PEAK_WINDOW[2])[["val"]],
    peak_depth = band_at(intensity_s, depth_um,
                         PEAK_WINDOW[1], PEAK_WINDOW[2])[["at"]],
    # The same two numbers for the second, smaller band, plus the dip between
    # them: a bump is only a peak if it rises out of a trough, and
    # deep_prominence below is what makes that testable rather than asserted.
    deep_peak_int   = band_at(intensity_s, depth_um,
                              DEEP_WINDOW[1], DEEP_WINDOW[2])[["val"]],
    deep_peak_depth = band_at(intensity_s, depth_um,
                              DEEP_WINDOW[1], DEEP_WINDOW[2])[["at"]],
    trough_int      = band_at(intensity_s, depth_um, TROUGH_WINDOW[1],
                              TROUGH_WINDOW[2], which.min)[["val"]],
    trough_depth    = band_at(intensity_s, depth_um, TROUGH_WINDOW[1],
                              TROUGH_WINDOW[2], which.min)[["at"]],
    mean_int   = mean(intensity[depth_um <= DEPTH_WINDOW[2]], na.rm = TRUE),
    # Trapezoid over the retained depth, in intensity*um, scaled per 1000 um so
    # it reads on the same order as the intensities themselves.
    auc        = {
      w <- which(depth_um <= DEPTH_WINDOW[2])
      d <- depth_um[w]; y <- intensity[w]
      sum(diff(d) * (head(y, -1) + tail(y, -1)) / 2) / 1000
    },
    .groups = "drop"
  ) |>
  mutate(
    covers_deep = max_depth >= DEEP_WINDOW[2],
    # A section whose ROI stops inside the deep window would report its last
    # sample as a "peak". Blank the deep metrics there rather than letting the
    # end of the ROI masquerade as a feature of the tissue.
    deep_peak_int   = if_else(covers_deep, deep_peak_int,   NA_real_),
    deep_peak_depth = if_else(covers_deep, deep_peak_depth, NA_real_),
    trough_int      = if_else(covers_deep, trough_int,      NA_real_),
    trough_depth    = if_else(covers_deep, trough_depth,    NA_real_),
    # How far the second band rises above the dip preceding it, and its size
    # relative to the superficial band. The ratio is the one that separates a
    # laminar redistribution from a whole-profile scaling.
    deep_prominence = deep_peak_int - trough_int,
    deep_ratio      = deep_peak_int / peak_int,
    # A maximum pinned to either edge of the window is a shoulder or a
    # truncation, not a peak; this counts the sections where it is genuinely
    # interior.
    deep_interior   = covers_deep & deep_peak_depth > DEEP_WINDOW[1] &
                        deep_peak_depth < DEEP_WINDOW[2]
  )

sec("Section-level summaries",
    paste0("Each section is reduced to a handful of numbers before modeling. ",
           "For the superficial band: the peak of a 25-sample rolling mean ",
           "within ", PEAK_WINDOW[1], "-", PEAK_WINDOW[2], " um and the depth ",
           "at which it occurs, plus the mean and trapezoidal AUC over ",
           DEPTH_WINDOW[1], "-", DEPTH_WINDOW[2], " um. peak_int is the ",
           "response in Models 1 and 2. The second band at ", DEEP_WINDOW[1],
           "-", DEEP_WINDOW[2], " um gets the same peak treatment, plus the ",
           "trough between the bands and the resulting prominence; those feed ",
           "the deep-band section further down."))

stat("Section summaries by treatment",
     paste0("Group means of the four section-level measures (n = sections, not ",
            "animals). This is the descriptive version of the treatment ",
            "effect; the models below add plate, distance and the ",
            "subject/hemisphere structure that these raw means ignore."),
     print(sect |> group_by(Treatment) |>
             summarise(n = n(), peak = mean(peak_int),
                       peak_depth = mean(peak_depth),
                       mean_int = mean(mean_int), auc = mean(auc)) |>
             mutate(across(where(is.numeric), \(x) round(x, 1)))))

stat("Deep-band coverage",
     paste0("The deep window sits near the end of the ROI, so it is only ",
            "measurable where the aligned depth reaches ", DEEP_WINDOW[2],
            " um -- sections that fall short are excluded from every ",
            "deep-band number rather than contributing a truncated one. If ",
            "the covered count is small, or few peaks are interior, lower ",
            "DEEP_WINDOW rather than reading the models below."),
     {
       cat(sprintf("max aligned depth: median %.0f um, range %.0f-%.0f um\n",
                   median(sect$max_depth), min(sect$max_depth),
                   max(sect$max_depth)))
       cat(sprintf("%d of %d sections reach %g um and carry deep-band metrics\n",
                   sum(sect$covers_deep), nrow(sect), DEEP_WINDOW[2]))
       cat(sprintf("of those, %d have the deep maximum strictly inside the window\n",
                   sum(sect$deep_interior)))
       if (any(sect$covers_deep)) {
         print(sect |> filter(covers_deep) |>
                 count(Treatment, Hemisphere, name = "n_covered") |>
                 pivot_wider(names_from = Hemisphere, values_from = n_covered,
                             values_fill = 0))
       }
     })

# Depth-binned long table for the depth-resolved model and the ribbon plots.
BIN <- 25  # um
binned <- prof |>
  filter(depth_um <= DEPTH_WINDOW[2]) |>
  mutate(depth_bin = floor(depth_um / BIN) * BIN + BIN / 2) |>
  group_by(section_id, SubjectID, Hemisphere, subj_hemi, Treatment, Condition,
           Sex, AtlasPlate, AtlasPlate_c, CannulaDist, CannulaDist_c,
           has_cannula, depth_bin) |>
  summarise(intensity = mean(intensity, na.rm = TRUE), .groups = "drop")

# The same binning carried out to the far edge of the deep window, restricted
# to the sections that reach it. Kept separate from `binned` so that averaging
# over a shrinking set of sections stays confined to the deep-band material:
# everything built on `binned` -- Figures 1, 3, 6 and Model 3 -- keeps a fixed
# section set at every depth it plots.
binned_deep <- prof |>
  filter(depth_um <= DEEP_WINDOW[2],
         section_id %in% sect$section_id[sect$covers_deep]) |>
  mutate(depth_bin = floor(depth_um / BIN) * BIN + BIN / 2) |>
  group_by(section_id, SubjectID, Hemisphere, subj_hemi, Treatment, Condition,
           Sex, AtlasPlate, AtlasPlate_c, CannulaDist, CannulaDist_c,
           has_cannula, depth_bin) |>
  summarise(intensity = mean(intensity, na.rm = TRUE), .groups = "drop")

# 5. Visualization -----------------------------------------------------------

sec("Figures",
    paste0("Descriptive views, in the order they should be read: the group ",
           "means, then the individual sections behind them, then the two ",
           "things that could produce a group difference on their own -- ",
           "distance from the cannula, and anterior-posterior position."))

# 5a. The headline plot: mean depth profile per treatment, SEM ribbon over
#     sections, split by hemisphere so the Treatment/Hemisphere confound stays
#     visible instead of being averaged away.
p1_dat <- binned |>
  group_by(Treatment, Hemisphere, depth_bin) |>
  summarise(m = mean(intensity), se = sd(intensity) / sqrt(n()), n = n(),
            .groups = "drop")

p1 <- ggplot(p1_dat, aes(depth_bin, m, color = Treatment, fill = Treatment)) +
  geom_ribbon(aes(ymin = m - se, ymax = m + se), alpha = 0.20, color = NA) +
  geom_line(linewidth = 0.8) +
  facet_wrap(~ Hemisphere,
             labeller = labeller(Hemisphere = c(L = "Left", R = "Right"))) +
  scale_color_manual(values = tx_colors) +
  scale_fill_manual(values = tx_colors) +
  labs(title = "WFA-PV intensity across cortical depth",
       subtitle = "Mean +/- SEM across sections; auditory cortex ROI",
       x = "Depth below pial surface (um)", y = "Mean intensity (a.u.)") +
  theme(legend.position = "bottom")

fig("p1", p1, "Mean depth profile by treatment",
    paste0("Mean +/- SEM across sections, on surface-aligned depth. Split by ",
           "hemisphere so the Treatment/Hemisphere confound stays visible ",
           "rather than being averaged away: compare GM6001 with Vehicle ",
           "across the panels, not the two control arms with each other."))

# 5a2. The same mean profile carried past the 1200-um analysis cutoff, so both
#      bands are on one axis and the windows that measure them are drawn where
#      the reader can see what they enclose.
if (nrow(binned_deep)) {
  p1b_dat <- binned_deep |>
    group_by(Treatment, depth_bin) |>
    summarise(m = mean(intensity), se = sd(intensity) / sqrt(n()),
              .groups = "drop")

  band_rect <- function(w, fill) {
    annotate("rect", xmin = w[1], xmax = w[2], ymin = -Inf, ymax = Inf,
             fill = fill, alpha = 0.5)
  }
  p1b <- ggplot(p1b_dat, aes(depth_bin, m, color = Treatment,
                             fill = Treatment)) +
    band_rect(PEAK_WINDOW, "grey88") +
    band_rect(DEEP_WINDOW, "grey78") +
    geom_ribbon(aes(ymin = m - se, ymax = m + se), alpha = 0.20, color = NA) +
    geom_line(linewidth = 0.8) +
    annotate("text", x = mean(PEAK_WINDOW), y = Inf, label = "superficial band",
             vjust = 1.6, size = 3, color = "grey25") +
    annotate("text", x = mean(DEEP_WINDOW), y = Inf, label = "deep band",
             vjust = 1.6, size = 3, color = "grey25") +
    scale_color_manual(values = tx_colors) +
    scale_fill_manual(values = tx_colors) +
    labs(title = "Both WFA-PV bands across the full imaged depth",
         subtitle = sprintf("Mean +/- SEM across the %d sections reaching %g um",
                            sum(sect$covers_deep), DEEP_WINDOW[2]),
         x = "Depth below pial surface (um)", y = "Mean intensity (a.u.)") +
    theme(legend.position = "bottom")

  fig("p1b", p1b, "Both bands on one axis",
      paste0("The superficial peak and the smaller second peak at ",
             DEEP_WINDOW[1], "-", DEEP_WINDOW[2], " um, with the two ",
             "measurement windows shaded. Restricted to the sections whose ",
             "aligned depth reaches ", DEEP_WINDOW[2], " um, so the section ",
             "set is the same at every depth rather than thinning out to the ",
             "right. The gap between the shaded bands is the trough that ",
             "deep_prominence is measured from."), w = 9, h = 5)
} else {
  stat("Full-depth profile skipped",
       "There is nothing to plot past the analysis cutoff.",
       cat(sprintf("no section reaches %g um of aligned depth\n",
                   DEEP_WINDOW[2])))
}

# 5b. Every section as its own trace, so section-to-section spread and any
#     mis-detected surface show up instead of hiding inside the mean.
p2 <- ggplot(binned, aes(depth_bin, intensity, group = section_id,
                         color = SubjectID)) +
  geom_line(alpha = 0.65, linewidth = 0.4) +
  facet_grid(Hemisphere ~ Treatment) +
  scale_color_viridis_d(option = "turbo", guide = guide_legend(ncol = 1)) +
  labs(title = "Individual section profiles",
       subtitle = "One line per section, colored by subject",
       x = "Depth below pial surface (um)", y = "Intensity (a.u.)",
       color = "Subject") +
  theme(legend.key.height = unit(9, "pt"))

fig("p2", p2, "Every section, colored by subject",
    paste0("The spread behind Figure 1. Lines of one color clustering together ",
           "is the subject-level variance the models absorb; a trace that ",
           "starts high at depth 0 is a missed surface detection and should be ",
           "checked against the offsets reported above."))

# 5c. The dose-distance question: does the effect fall off with distance from
#     the cannula plate? Trained animals only, since controls have no cannula.
p3 <- sect |>
  filter(has_cannula) |>
  ggplot(aes(CannulaDist, peak_int, color = Treatment)) +
  geom_smooth(method = "lm", formula = y ~ x, se = TRUE, alpha = 0.15,
              linewidth = 0.8) +
  geom_point(aes(shape = Hemisphere), size = 2.4, alpha = 0.85) +
  scale_color_manual(values = tx_colors) +
  labs(title = "Peak WFA-PV intensity vs. distance from the cannula plate",
       subtitle = "Trained animals; 0 = the section at the cannula, units are atlas plates",
       x = "CannulaDist (plates from cannula)",
       y = "Peak intensity, 0-800 um (a.u.)")

fig("p3", p3, "Peak intensity vs. distance from the cannula",
    paste0("Implanted hemispheres only. If GM6001 acts locally, its line should ",
           "rise away from 0 while Vehicle stays flat; parallel lines mean no ",
           "dose-distance relationship. Tested formally in Model 2."))

# 5d. Section-level distribution with subject means joined, so the paired
#     within-animal GM6001 vs Vehicle comparison is legible.
subj_means <- sect |>
  group_by(SubjectID, Condition, Treatment) |>
  summarise(peak_int = mean(peak_int), .groups = "drop")

p4 <- ggplot(sect, aes(Treatment, peak_int, color = Treatment)) +
  geom_boxplot(outlier.shape = NA, width = 0.55, fill = NA, linewidth = 0.6) +
  geom_jitter(width = 0.12, height = 0, size = 1.6, alpha = 0.45) +
  geom_line(data = subj_means, aes(group = SubjectID), color = "grey40",
            linewidth = 0.4, alpha = 0.7) +
  geom_point(data = subj_means, size = 3, shape = 21, fill = "white",
             stroke = 1) +
  scale_color_manual(values = tx_colors, guide = "none") +
  labs(title = "Peak intensity by treatment",
       subtitle = "Small points: sections. Large points joined by line: subject means",
       x = NULL, y = "Peak intensity, 0-800 um (a.u.)")

fig("p4", p4, "Peak intensity by treatment, paired within animal",
    paste0("Small points are sections, large points subject means, and each ",
           "grey line joins the two hemispheres of one animal. The slope of ",
           "those lines between Vehicle and GM6001 is the within-animal ",
           "contrast the models estimate; the boxes also carry between-animal ",
           "variance and will look noisier."), w = 8, h = 5.5)

# 5e. Depth x atlas plate as a raster, to check that a treatment effect is not
#     just an anterior-posterior gradient across the sampled plates.
p5 <- binned |>
  group_by(Treatment, AtlasPlate, depth_bin) |>
  summarise(m = mean(intensity), .groups = "drop") |>
  ggplot(aes(AtlasPlate, depth_bin, fill = m)) +
  geom_raster(interpolate = TRUE) +
  facet_wrap(~ Treatment, nrow = 1) +
  scale_y_reverse() +
  scale_fill_viridis_c(option = "magma") +
  labs(title = "Intensity by atlas plate and depth",
       x = "Atlas plate", y = "Depth below pial surface (um)",
       fill = "Intensity")

fig("p5", p5, "Depth by atlas plate",
    paste0("Intensity as a function of anterior-posterior position and depth. ",
           "A band that shifts systematically left to right within a panel is ",
           "an A-P gradient, which AtlasPlate_c is in the models to absorb; ",
           "panels differing in overall brightness is the treatment effect."),
    w = 10, h = 4.5)

# 5f. The same individual-section traces as p2, but organized by atlas
#     plate (anterior to posterior, left to right) instead of hemisphere. The
#     four arms go into two figures of two rows each: the within-animal pair
#     (Vehicle over GM6001) and the two control hemispheres. Depth and
#     intensity axes and the subject color scale are fixed identically across
#     both figures, so a plate or a subject can be compared directly across
#     rows and across figures.
subj_levels <- levels(prof$SubjectID)
y_rng <- range(binned$intensity, na.rm = TRUE)
plate_labeller <- as_labeller(\(x) paste("Plate", x))

tx_pairs <- list(
  VehicleGM6001 = list(tx = c("Vehicle", "GM6001"),
                       who = "trained animals, Vehicle and GM6001 hemispheres",
                       note = paste0("Each trained animal contributes one ",
                                     "hemisphere to each row, so a color ",
                                     "that appears in both rows is the same ",
                                     "animal's two hemispheres.")),
  Control       = list(tx = c("Control L", "Control R"),
                       who = "control animals, left and right hemispheres",
                       note = paste0("Neither hemisphere was infused, so any ",
                                     "row-to-row difference here is a ",
                                     "hemisphere difference, not a ",
                                     "treatment one.")))

for (nm in names(tx_pairs)) {
  pr  <- tx_pairs[[nm]]
  dat <- binned |> filter(Treatment %in% pr$tx)
  if (!nrow(dat)) next

  p5c <- ggplot(dat, aes(depth_bin, intensity, group = section_id,
                         color = SubjectID)) +
    geom_line(alpha = 0.75, linewidth = 0.5) +
    facet_grid(Treatment ~ AtlasPlate,
               labeller = labeller(AtlasPlate = plate_labeller)) +
    # limits pins each subject's color across both figures; breaks keeps the
    # legend to the subjects actually drawn here.
    scale_color_viridis_d(option = "turbo", limits = subj_levels,
                          breaks = levels(droplevels(dat$SubjectID)),
                          guide = guide_legend(ncol = 1)) +
    coord_cartesian(ylim = y_rng) +
    labs(title = sprintf("WFA-PV intensity by depth and atlas plate -- %s",
                         paste(pr$tx, collapse = " and ")),
         subtitle = "One line per section, colored by subject",
         x = "Depth below pial surface (um)", y = "Intensity (a.u.)",
         color = "Subject") +
    theme(legend.key.height = unit(9, "pt"))

  fig(paste0("p5c_", nm), p5c,
      sprintf("Depth by atlas plate, %s", paste(pr$tx, collapse = " vs ")),
      paste0("Every section from the ", pr$who, ", one row per arm and one ",
             "column per atlas plate (anterior to posterior, left to right), ",
             "one line per section colored by subject. ", pr$note, " Depth, ",
             "intensity and the subject color scale are the same in both ",
             "paired figures. An empty panel means that arm has no section ",
             "at that plate; a subject missing from the legend has no ",
             "section in either row."),
      w = 12, h = 7)
}

cat("\nFigures written to ", FIG_DIR, "\n", sep = "")

# 6. Mixed-effects models ----------------------------------------------------

# Random effects. Hemisphere has exactly two levels, so (1 | Hemisphere) on its
# own is not estimable in any useful sense -- two groups carry no information
# about a variance, and lme4 will either return ~0 or fail to converge. What
# this design calls for is hemisphere nested in subject: each animal
# contributes two hemispheres, and sections repeat within them.
#     (1 | SubjectID/Hemisphere)  ==  (1 | SubjectID) + (1 | SubjectID:Hemisphere)
# giving 10 and 20 grouping levels respectively. A systematic left/right
# difference, if one is of interest, belongs in the fixed part -- and for the
# controls Treatment already carries it.
#
# In this dataset the nested term lands on zero (a singular fit): once subject
# is accounted for, the two hemispheres of an animal are no more alike than two
# sections of one hemisphere. That is a result, not a failure, but it does mean
# the nested term is buying nothing, so each fit below is reported alongside
# the reduced (1 | SubjectID) model for comparison.

# Report the variance components, flag a singular fit, and refit without the
# nested hemisphere term when it has collapsed to zero.
check_re <- function(m, label) {
  vc <- as.data.frame(VarCorr(m))
  cat(sprintf("-- %s: random effects --\n", label))
  print(vc[, c("grp", "vcov", "sdcor")], row.names = FALSE)
  if (isSingular(m, tol = 1e-4)) {
    cat("   Singular fit: at least one variance is ~0.\n")
    m_red <- update(m, . ~ . - (1 | SubjectID/Hemisphere) + (1 | SubjectID))
    cat("   Refit without the nested hemisphere term:\n")
    print(anova(update(m, REML = FALSE), update(m_red, REML = FALSE)))
    return(invisible(m_red))
  }
  invisible(m)
}

RE_DESC <- paste0("Variance components. A hemisphere-within-subject variance ",
                  "at ~0 (a singular fit) says the two hemispheres of an animal ",
                  "are no more alike than two sections of one hemisphere; the ",
                  "likelihood-ratio test that follows compares the nested model ",
                  "with the reduced (1 | SubjectID) one, and a non-significant ",
                  "result means the nested term is buying nothing.")

sec("Model 1: all sections",
    paste0("peak_int ~ Treatment + AtlasPlate_c + (1 | SubjectID/Hemisphere), ",
           "over all sections. CannulaDist is deliberately absent: for ",
           "controls it is AtlasPlate - 30 (see the QC), so fitting both would ",
           "be degenerate and neither coefficient would mean what its name ",
           "suggests. The distance effect is estimated in Model 2 instead, on ",
           "the animals that actually have a cannula."))

m1 <- lmer(peak_int ~ Treatment + AtlasPlate_c + (1 | SubjectID/Hemisphere),
           data = sect, REML = TRUE)

stat("Model 1 summary",
     paste0("Fixed effects are contrasts against Vehicle, the within-animal ",
            "counterpart to GM6001; TreatmentGM6001 is the effect of interest, ",
            "while the two Control terms are between-animal comparisons that ",
            "carry the hemisphere confound. AtlasPlate_c is centered on plate ",
            "30, so the intercept is Vehicle at mid-range."),
     print(summary(m1)))
stat("Model 1 random effects", RE_DESC, check_re(m1, "Model 1"))
stat("Model 1 estimated marginal means",
     paste0("Treatment means adjusted to a common plate, with SEs and df from ",
            "the mixed model rather than from the raw section counts."),
     print(emmeans(m1, ~ Treatment)))
stat("Model 1 pairwise contrasts (Tukey)",
     paste0("All six treatment pairs, p adjusted for multiplicity. ",
            "GM6001 - Vehicle is the within-animal contrast; anything ",
            "involving a Control arm is between animals and confounded with ",
            "hemisphere."),
     print(pairs(emmeans(m1, ~ Treatment))))

sec("Model 1b: CannulaDist as a common recentered axis",
    paste0("CannulaDist was populated for controls on purpose: read as one ",
           "variable it is the plate coordinate recentered per hemisphere -- ",
           "on the actual cannula for trained animals, on a nominal plate 30 ",
           "for controls. That makes it usable across all sections, but only ",
           "INSTEAD OF AtlasPlate, never alongside it. Two caveats on the ",
           "Treatment terms here: CannulaDist_c = 0 is not the same anatomical ",
           "location in both groups, and the recentering is itself a function ",
           "of group. The GM6001-vs-Vehicle contrast, being within-animal, is ",
           "unaffected by both."))

sect_cd <- sect |> filter(!is.na(CannulaDist)) |> droplevels()

stat("Sections retained",
     "How many sections carry a CannulaDist value at all.",
     cat(sprintf("n = %d of %d sections, %d subjects (%d dropped, no CannulaDist)\n",
                 nrow(sect_cd), nrow(sect), nlevels(sect_cd$SubjectID),
                 nrow(sect) - nrow(sect_cd))))

m1b <- lmer(peak_int ~ Treatment + CannulaDist_c + (1 | SubjectID/Hemisphere),
            data = sect_cd, REML = TRUE)

stat("Model 1b summary",
     paste0("The same structure as Model 1 with the position term swapped. ",
            "Compare TreatmentGM6001 against Model 1: if it moves materially, ",
            "the choice of position axis is doing the work."),
     print(summary(m1b)))
stat("Model 1b random effects", RE_DESC, check_re(m1b, "Model 1b"))
stat("Model 1b Type III ANOVA",
     paste0("Omnibus F tests with Satterthwaite df: whether Treatment as a ",
            "whole, and position, explain variance beyond the rest of the ",
            "model."),
     print(anova(m1b)))
stat("Model 1b estimated marginal means",
     "Treatment means on the recentered axis, for comparison with Model 1.",
     print(emmeans(m1b, ~ Treatment)))

# Same question Model 1 answered with AtlasPlate, now on the recentered axis:
# if the two disagree, the axis choice is doing the work, not the biology.
m1_plate <- lmer(peak_int ~ Treatment + AtlasPlate_c + (1 | SubjectID/Hemisphere),
                 data = sect_cd, REML = TRUE)

stat("AtlasPlate vs CannulaDist as the single position term",
     paste0("The two position axes fit to an identical set of sections, so the ",
            "AICs are comparable. Similar estimates and AIC mean the axis ",
            "choice is immaterial; a large AIC gap means one axis genuinely ",
            "describes the A-P trend better."),
     for (nm in c("m1_plate", "m1b")) {
       co <- summary(get(nm))$coefficients
       pos <- setdiff(rownames(co), c("(Intercept)",
                                      grep("^Treatment", rownames(co),
                                           value = TRUE)))
       cat(sprintf("%-9s %-14s = %7.2f (SE %5.2f, p = %.2e)   AIC %7.1f\n",
                   nm, pos, co[pos, "Estimate"], co[pos, "Std. Error"],
                   co[pos, "Pr(>|t|)"], AIC(get(nm))))
     })

sec("Model 2: trained animals, with CannulaDist",
    paste0("The model as specified: fixed Treatment, AtlasPlate_c and ",
           "CannulaDist_c, random subject with hemisphere nested. Restricted ",
           "to trained animals, where GM6001 and Vehicle are the two ",
           "hemispheres of the same subject, so the treatment contrast is ",
           "entirely within-animal and free of the hemisphere confound. The ",
           "filter is has_cannula, not !is.na(CannulaDist): the latter would ",
           "also let through the nominal control values."))

sect_tr <- sect |>
  filter(Condition == "Trained", has_cannula) |>
  droplevels()
dropped <- setdiff(levels(droplevels(filter(sect, Condition == "Trained")$SubjectID)),
                   levels(sect_tr$SubjectID))

stat("Sections retained",
     "The trained subset, and any animal excluded for lacking a cannula plate.",
     {
       cat(sprintf("n = %d sections, %d subjects\n",
                   nrow(sect_tr), nlevels(sect_tr$SubjectID)))
       if (length(dropped)) {
         cat("Dropped for having no cannula plate on record: ",
             paste(dropped, collapse = ", "), "\n", sep = "")
       }
     })

# CannulaDist is AtlasPlate minus that hemisphere's cannula plate, and the
# cannula plate only ever takes the values 29, 30 or 31. The two predictors are
# therefore very nearly the same variable shifted by a near-constant. Check
# before trusting either coefficient: with a variance inflation factor in the
# double digits neither is separately identifiable, whatever the p-values say.
vif_fixed <- function(m) {
  v <- as.matrix(vcov(m))
  v <- v[-1, -1, drop = FALSE]              # drop the intercept
  d <- 1 / sqrt(diag(v))
  r <- v * outer(d, d)
  setNames(diag(solve(r)), colnames(v))
}

stat("Variance inflation factors",
     paste0("Cannula plates only ever take the values 29-31, so AtlasPlate and ",
            "CannulaDist are nearly the same variable shifted by a constant. A ",
            "VIF much above 5 means the two position coefficients are not ",
            "separately identifiable whatever their p-values say; the ",
            "Treatment estimate is unaffected as long as its own VIF stays ",
            "near 1."),
     print(round(vif_fixed(lmer(peak_int ~ Treatment + AtlasPlate_c +
                                  CannulaDist_c + (1 | SubjectID),
                                data = sect_tr)), 2)))

m2 <- lmer(peak_int ~ Treatment + AtlasPlate_c + CannulaDist_c +
             (1 | SubjectID/Hemisphere),
           data = sect_tr, REML = TRUE)

stat("Model 2 summary",
     paste0("TreatmentGM6001 is the within-animal GM6001 - Vehicle difference ",
            "in peak intensity, adjusted for plate and cannula distance. Read ",
            "the two position coefficients with the VIFs above in mind."),
     print(summary(m2)))
stat("Model 2 random effects", RE_DESC, check_re(m2, "Model 2"))
stat("Model 2 Type III ANOVA (Satterthwaite df)",
     "Omnibus test for each fixed term with the others held in the model.",
     print(anova(m2)))

# Because of that collinearity, also fit each distance term on its own. If the
# two agree on the sign and size of the treatment effect, the treatment
# conclusion does not hinge on which one is in the model.
m2_plate <- lmer(peak_int ~ Treatment + AtlasPlate_c + (1 | SubjectID/Hemisphere),
                 data = sect_tr, REML = TRUE)
m2_cann  <- lmer(peak_int ~ Treatment + CannulaDist_c + (1 | SubjectID/Hemisphere),
                 data = sect_tr, REML = TRUE)

stat("Treatment effect with only one distance term at a time",
     paste0("A robustness check against the collinearity above: the same ",
            "contrast from the full model and from each single-position model. ",
            "Agreement in sign and magnitude means the treatment conclusion ",
            "does not depend on which position term is in the model; ",
            "disagreement means it does, and neither version should then be ",
            "quoted on its own."),
     for (nm in c("m2", "m2_plate", "m2_cann")) {
       co <- summary(get(nm))$coefficients
       cat(sprintf("%-9s GM6001 - Vehicle = %7.2f (SE %5.2f, p = %.3f)\n",
                   nm, co["TreatmentGM6001", "Estimate"],
                   co["TreatmentGM6001", "Std. Error"],
                   co["TreatmentGM6001", "Pr(>|t|)"]))
     })

m2_int <- lmer(peak_int ~ Treatment * CannulaDist_c + AtlasPlate_c +
                 (1 | SubjectID/Hemisphere),
               data = sect_tr, REML = FALSE)
m2_ml <- update(m2, REML = FALSE)

stat("Does the treatment effect depend on cannula distance?",
     paste0("Likelihood-ratio test (ML fits) for adding Treatment x ",
            "CannulaDist_c. A significant result is the dose-distance ",
            "signature -- the GM6001 effect shrinking with distance from the ",
            "infusion site; a null result says the effect, if present, is ",
            "uniform across the sampled plates."),
     print(anova(m2_ml, m2_int)))

stat("Treatment slopes over CannulaDist",
     paste0("The per-arm slope, in intensity per atlas plate away from the ",
            "cannula. Compare the two intervals: a Vehicle slope overlapping ",
            "zero with a non-zero GM6001 slope is the pattern Figure 3 shows ",
            "graphically."),
     print(emtrends(m2_int, ~ Treatment, var = "CannulaDist_c")))

sec("Model 3: depth-resolved, binned samples",
    paste0("Moves from one number per section to the whole ", BIN,
           "-um binned profile. Depth enters as a natural spline (df = 4) so ",
           "the laminar shape is not forced linear, and Treatment x depth asks ",
           "whether the profiles differ in shape rather than only in level. ",
           "Section gets its own intercept because bins within a section are ",
           "nowhere near independent. Like the rest of the binned material it ",
           "stops at ", DEPTH_WINDOW[2], " um, so it says nothing about the ",
           "deep band -- that is the section immediately below."))

binned_tr <- binned |>
  filter(Condition == "Trained", has_cannula) |>
  droplevels()

m3 <- lmer(intensity ~ Treatment * ns(depth_bin, df = 4) +
             AtlasPlate_c + CannulaDist_c +
             (1 | SubjectID/Hemisphere) + (1 | section_id),
           data = binned_tr, REML = TRUE,
           control = lmerControl(optimizer = "bobyqa"))

stat("Model 3 random effects",
     paste0(RE_DESC, " The section-level variance should be substantial here: ",
            "it is what keeps the ", BIN, "-um bins from being counted as ",
            "independent observations."),
     check_re(m3, "Model 3"))
stat("Model 3 Type III ANOVA",
     paste0("The row to read is Treatment:ns(depth_bin): significant means the ",
            "two arms differ in the SHAPE of the laminar profile, not just in ",
            "its overall level."),
     print(anova(m3)))
stat("GM6001 - Vehicle at selected depths",
     paste0("The interaction unpacked: the treatment difference evaluated ",
            "every 200 um through the cortical depth, so the layers where the ",
            "arms diverge can be named. p values are per depth and unadjusted ",
            "across the six."),
     print(pairs(emmeans(m3, ~ Treatment | depth_bin,
                         at = list(depth_bin = c(100, 300, 500, 700, 900,
                                                 1100))))))

# Model-implied depth curves.
pred <- as.data.frame(
  emmeans(m3, ~ Treatment | depth_bin,
          at = list(depth_bin = seq(12.5, 1187.5, by = 25))))
p6 <- ggplot(pred, aes(depth_bin, emmean, color = Treatment, fill = Treatment)) +
  geom_ribbon(aes(ymin = lower.CL, ymax = upper.CL), alpha = 0.18, color = NA) +
  geom_line(linewidth = 0.9) +
  scale_color_manual(values = tx_colors) +
  scale_fill_manual(values = tx_colors) +
  labs(title = "Model 3: fitted depth profiles",
       subtitle = "Estimated marginal means +/- 95% CI, trained animals",
       x = "Depth below pial surface (um)", y = "Intensity (a.u.)")

fig("p6", p6, "Model-implied depth profiles",
    paste0("Model 3's fitted curves with 95% CIs, adjusted for plate and ",
           "cannula distance and for the subject / hemisphere / section ",
           "structure. This is the model-based counterpart to Figure 1: the ",
           "depths where the ribbons separate are the ones tested in the ",
           "contrast table above."),
    w = 8, h = 5)

# 6b. The deep band ----------------------------------------------------------

sec(sprintf("Deep band: the second peak (%g-%g um)",
            DEEP_WINDOW[1], DEEP_WINDOW[2]),
    paste0("The smaller band deeper in the column, given the same treatment as ",
           "the superficial one. Everything here is restricted to the ",
           "sections whose aligned depth reaches ", DEEP_WINDOW[2], " um (see ",
           "the coverage check above), which is a different -- and smaller -- ",
           "set of sections than Models 1-3 used, so the counts will not ",
           "match. Read the descriptive block first: if the band has no ",
           "prominence above the trough, the models are fitting a shoulder."))

sect_deep <- sect |> filter(covers_deep) |> droplevels()

# The deep band lives at the edge of what was imaged, so how much of the design
# survives the coverage filter is not knowable in advance. Check that there is
# a design left to fit before fitting one, and let a fit that fails anyway
# report itself instead of taking the report down at the last section.
deep_ok <- nrow(sect_deep) >= 10 && nlevels(sect_deep$SubjectID) >= 4 &&
  n_distinct(sect_deep$Treatment) >= 2
sect_deep_tr <- sect_deep |>
  filter(Condition == "Trained", has_cannula) |>
  droplevels()
deep_tr_ok <- nrow(sect_deep_tr) >= 8 && nlevels(sect_deep_tr$SubjectID) >= 3 &&
  n_distinct(sect_deep_tr$Treatment) == 2

# A deep-band fit that fails should say so, not take the whole report down at
# the second-to-last section. The lmer() calls below stay inline rather than
# going through a fitting helper: check_re() refits with update(), which
# re-evaluates the recorded call, and a helper would record "data = data" for
# it to resolve to the data() function.
fit_failed <- function(label) function(e) {
  cat(label, ": fit failed -- ", conditionMessage(e), "\n", sep = ""); NULL
}

stat("Deep band by treatment",
     paste0("deep_peak is the peak of the same smoothed trace inside ",
            DEEP_WINDOW[1], "-", DEEP_WINDOW[2], " um and deep_depth where it ",
            "falls; trough is the minimum between the bands, and prominence ",
            "the rise from it. A prominence near zero, or a deep_depth sitting ",
            "on a window edge, means the feature is a shoulder on the decline ",
            "rather than a second peak. ratio is deep_peak / peak: below 1 by ",
            "construction here, and it is the quantity that separates a ",
            "laminar redistribution from a uniform change in level."),
     {
       if (!nrow(sect_deep)) {
         cat(sprintf("no section reaches %g um; nothing to summarize\n",
                     DEEP_WINDOW[2]))
       } else {
         print(sect_deep |> group_by(Treatment) |>
                 summarise(n = n(), deep_peak = mean(deep_peak_int),
                           deep_depth = mean(deep_peak_depth),
                           trough = mean(trough_int),
                           prominence = mean(deep_prominence),
                           ratio = mean(deep_ratio), .groups = "drop") |>
                 mutate(across(where(is.numeric), \(x) round(x, 2))))
         cat(sprintf("\n%d of %d covered sections rise at least 1 a.u. above the trough\n",
                     sum(sect_deep$deep_prominence >= 1), nrow(sect_deep)))
       }
     })

if (nrow(sect_deep)) {
  deep_subj <- sect_deep |>
    group_by(SubjectID, Condition, Treatment) |>
    summarise(deep_peak_int = mean(deep_peak_int), .groups = "drop")

  p8 <- ggplot(sect_deep, aes(Treatment, deep_peak_int, color = Treatment)) +
    geom_boxplot(outlier.shape = NA, width = 0.55, fill = NA, linewidth = 0.6) +
    geom_jitter(width = 0.12, height = 0, size = 1.6, alpha = 0.45) +
    geom_line(data = deep_subj, aes(group = SubjectID), color = "grey40",
              linewidth = 0.4, alpha = 0.7) +
    geom_point(data = deep_subj, size = 3, shape = 21, fill = "white",
               stroke = 1) +
    scale_color_manual(values = tx_colors, guide = "none") +
    labs(title = "Deep-band peak intensity by treatment",
         subtitle = "Small points: sections. Large points joined by line: subject means",
         x = NULL, y = sprintf("Deep peak, %g-%g um (a.u.)",
                               DEEP_WINDOW[1], DEEP_WINDOW[2]))

  fig("p8", p8, "Deep-band peak by treatment, paired within animal",
      paste0("Figure 5 for the second band, on the covered sections only. The ",
             "grey lines are the within-animal GM6001 - Vehicle differences ",
             "that Model 4b estimates; an animal with only one hemisphere ",
             "reaching ", DEEP_WINDOW[2], " um contributes a point but no ",
             "line."), w = 8, h = 5.5)
}

m4 <- if (deep_ok) {
  tryCatch(lmer(deep_peak_int ~ Treatment + AtlasPlate_c +
                  (1 | SubjectID/Hemisphere),
                data = sect_deep, REML = TRUE),
           error = fit_failed("Model 4"))
} else NULL

if (!deep_ok) {
  stat("Deep-band models skipped",
       paste0("Too little of the design survives the coverage filter to fit ",
              "anything meaningful. Lower DEEP_WINDOW, or treat the band as ",
              "descriptive only."),
       cat(sprintf("%d sections, %d subjects, %d treatment arms cover the window\n",
                   nrow(sect_deep), nlevels(sect_deep$SubjectID),
                   n_distinct(sect_deep$Treatment))))
}

if (!is.null(m4)) {
  stat("Model 4: deep peak, all covered sections",
       paste0("The Model 1 specification with the deep peak as the response: ",
              "deep_peak_int ~ Treatment + AtlasPlate_c + ",
              "(1 | SubjectID/Hemisphere). TreatmentGM6001 is again the ",
              "contrast of interest, and the Control terms again carry the ",
              "hemisphere confound."),
       print(summary(m4)))
  stat("Model 4 random effects", RE_DESC, check_re(m4, "Model 4"))
  stat("Model 4 pairwise contrasts (Tukey)",
       paste0("Treatment pairs on the deep band, p adjusted for multiplicity. ",
              "Compare the direction against Model 1's table: the same sign in ",
              "both bands is a whole-profile shift, opposite signs are a ",
              "redistribution across depth."),
       print(pairs(emmeans(m4, ~ Treatment))))
}

m4b <- if (deep_tr_ok) {
  tryCatch(lmer(deep_peak_int ~ Treatment + AtlasPlate_c + CannulaDist_c +
                  (1 | SubjectID/Hemisphere),
                data = sect_deep_tr, REML = TRUE),
           error = fit_failed("Model 4b"))
} else NULL

if (!is.null(m4b)) {
  stat("Model 4b: deep peak, trained animals",
       paste0("The Model 2 specification on the deep band: trained animals ",
              "with a cannula, so GM6001 and Vehicle are the two hemispheres ",
              "of one subject and the contrast is within-animal. This is the ",
              "deep-band number to quote. n = ", nrow(sect_deep_tr),
              " sections, ", nlevels(sect_deep_tr$SubjectID), " subjects."),
       print(summary(m4b)))
} else if (deep_ok) {
  stat("Model 4b skipped",
       paste0("The within-animal deep-band contrast needs trained sections ",
              "from both hemispheres reaching ", DEEP_WINDOW[2], " um."),
       cat(sprintf("%d trained sections with a cannula cover the window, %d subjects\n",
                   nrow(sect_deep_tr), nlevels(sect_deep_tr$SubjectID))))
}

m4r <- if (deep_ok) {
  tryCatch(lmer(deep_ratio ~ Treatment + AtlasPlate_c +
                  (1 | SubjectID/Hemisphere),
                data = sect_deep, REML = TRUE),
           error = fit_failed("Model 4r"))
} else NULL

if (!is.null(m4r)) {
  stat("Model 4r: deep / superficial ratio",
       paste0("The same model on deep_peak / peak. A treatment effect here ",
              "means the two bands moved by different amounts -- the profile ",
              "changed shape across depth. No effect here alongside effects in ",
              "Models 1 and 4 means both bands moved together and the ",
              "laminar pattern is intact."),
       print(anova(m4r)))
}

# 7. Diagnostics -------------------------------------------------------------

sec("Diagnostics",
    paste0("Whether the fits above are trustworthy: residual scale and ",
           "normality, and the fitted-vs-residual plot for the main ",
           "within-animal model."))

stat("Residual diagnostics",
     paste0("Per model: residual SD, the largest scaled residual (above ~3 ",
            "flags an outlying section), a Shapiro-Wilk test of residual ",
            "normality (on a 5000-point subsample where needed), and the ",
            "variance components again for context. A small Shapiro p over ",
            "thousands of binned samples is expected and not by itself a ",
            "problem."),
     for (nm in c("m1", "m2", "m3")) {
       m <- get(nm)
       r <- resid(m, scaled = TRUE)
       rs <- if (length(r) <= 5000) r else sample(r, 5000)
       cat(sprintf("\n%s: sigma = %.3f, max |scaled resid| = %.2f, Shapiro p = %.3g\n",
                   nm, sigma(m), max(abs(r)), shapiro.test(rs)$p.value))
       print(as.data.frame(VarCorr(m))[, c("grp", "vcov", "sdcor")])
     })

diag_df <- data.frame(fitted = fitted(m2), resid = resid(m2, scaled = TRUE),
                      Treatment = sect_tr$Treatment)
p7 <- ggplot(diag_df, aes(fitted, resid, color = Treatment)) +
  geom_hline(yintercept = 0, color = "grey60") +
  geom_point(size = 2, alpha = 0.8) +
  scale_color_manual(values = tx_colors) +
  labs(title = "Model 2 residuals", x = "Fitted", y = "Scaled residual")

fig("p7", p7, "Model 2 residuals vs. fitted",
    paste0("Should be a formless band around zero. A funnel opening to the ",
           "right means variance grows with intensity and argues for a log ",
           "response; one arm sitting systematically off zero means a ",
           "treatment effect the fixed part has not captured."),
    w = 7, h = 4.5)

# 8. Headline numbers --------------------------------------------------------

sec("Summary: GM6001 - Vehicle across specifications",
    paste0("The one contrast the experiment is about, taken from every model ",
           "that estimates it. Positive means higher peak WFA-PV intensity in ",
           "the GM6001 hemisphere. The specifications differ in which sections ",
           "are included and which position term is used, so agreement across ",
           "the rows is the evidence that the effect is not an artifact of one ",
           "modeling choice. The superficial band comes first, then the deep ",
           "one on its smaller set of sections."))

key <- function(m) {
  co <- summary(m)$coefficients
  if (!"TreatmentGM6001" %in% rownames(co)) return(c(est = NA, se = NA, p = NA))
  c(est = unname(co["TreatmentGM6001", "Estimate"]),
    se  = unname(co["TreatmentGM6001", "Std. Error"]),
    p   = unname(co["TreatmentGM6001", "Pr(>|t|)"]))
}

headline <- rbind(
  "M1  all sections, plate"        = key(m1),
  "M1b all sections, cannula axis" = key(m1b),
  "M2  trained, plate + cannula"   = key(m2),
  "M2  trained, plate only"        = key(m2_plate),
  "M2  trained, cannula only"      = key(m2_cann)) |>
  as.data.frame() |>
  mutate(est = round(est, 2), se = round(se, 2), p = signif(p, 3),
         sig = ifelse(!is.na(p) & p < 0.05, "*", ""))

stat("GM6001 - Vehicle, peak intensity (0-800 um)",
     paste0("Estimate, standard error and p for the TreatmentGM6001 ",
            "coefficient in each model. The first two rows include the control ",
            "animals and estimate the contrast partly between subjects; the ",
            "last three are trained animals only, where it is entirely within ",
            "subject and is the number to quote."),
     print(headline))

deep_rows <- list()
if (!is.null(m4))  deep_rows[["M4  deep peak, all covered"]]   <- key(m4)
if (!is.null(m4b)) deep_rows[["M4b deep peak, trained"]]       <- key(m4b)
if (!is.null(m4r)) deep_rows[["M4r deep / superficial ratio"]] <- key(m4r)

stat(sprintf("GM6001 - Vehicle, deep band (%g-%g um)",
             DEEP_WINDOW[1], DEEP_WINDOW[2]),
     paste0("The same contrast for the second band, on the sections that ",
            "reach it. The first two rows are in intensity units and compare ",
            "directly with the table above; the ratio row is unitless and ",
            "asks the different question of whether the two bands moved by ",
            "different amounts."),
     {
       if (!length(deep_rows)) {
         cat("no deep-band model was fit; see the coverage check above\n")
       } else {
         print(do.call(rbind, deep_rows) |>
                 as.data.frame() |>
                 mutate(est = round(est, 3), se = round(se, 3),
                        p = signif(p, 3),
                        sig = ifelse(!is.na(p) & p < 0.05, "*", "")))
       }
     })

stat("Depth-resolved effect (Model 3)",
     paste0("Where in the cortical column the difference lives: the depth at ",
            "which the two arms are furthest apart, and every 100-um depth at ",
            "which they differ at p < 0.05 (unadjusted)."),
     {
       dp <- as.data.frame(pairs(emmeans(m3, ~ Treatment | depth_bin,
                                         at = list(depth_bin = seq(100, 1100,
                                                                   by = 100)))))
       # pairs() orders the contrast Vehicle - GM6001 (Vehicle is the reference
       # level), so flip the sign to report it the way the table above does.
       i <- which.max(abs(dp$estimate))
       cat(sprintf("largest |GM6001 - Vehicle| at %g um: %.2f (SE %.2f, p = %.3g)\n",
                   dp$depth_bin[i], -dp$estimate[i], dp$SE[i], dp$p.value[i]))
       cat(sprintf("depths with p < 0.05: %s\n",
                   if (any(dp$p.value < 0.05))
                     paste(dp$depth_bin[dp$p.value < 0.05], collapse = ", ")
                   else "none"))
     })

report_write(nlevels(sect$section_id), nlevels(sect$SubjectID))
cat("\nDone.\n")
cat("Report:  ", REPORT_PATH, "\n", sep = "")
cat("Figures: ", FIG_DIR, "\n", sep = "")
if (interactive()) try(utils::browseURL(REPORT_PATH), silent = TRUE)
