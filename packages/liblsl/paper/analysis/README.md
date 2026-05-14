# Latency Analysis - liblsl.dart JOSS paper

This directory contains the R script and raw data needed to reproduce the latency figure in the liblsl.dart JOSS paper.

**Output:** The figure in the paper: `plot_latency.png` and a Markdown summary table printed to the console.

There are two ways to run this:

- Docker (recommended if you do not have R installed or if you already have Docker installed)
- Local R (if you have R set up and prefer to run it directly)

---

## Run with Docker

The Docker image is self-contained: all R packages, the font files, and the raw data zip are baked in. A `data/` directory is mounted at runtime; the container extracts the TSV files there on first run and writes the output figure back to the same location.

### 1. Install Docker

Follow the official instructions for your operating system:
<https://docs.docker.com/get-started/get-docker/>

### 2. Build the image

From this directory:

```bash
docker build -t r-paper-analysis .
```

This step installs all R packages and embeds the font files and data. It only needs to be done once; subsequent runs use the cached image.

### 3. Run the analysis

```bash
docker run --name r-paper-analysis --rm -t -v "./data:/data" r-paper-analysis
```

The container extracts the raw TSV files into `data/` (if not already present) and writes `plot_latency.png` there. The `data/` directory is excluded from version control via `.gitignore`.

#### Stopping or interrupting the analysis docker container

If for any reason you need to stop the container while it's running, you can do so from a different terminal window with:

```bash
docker kill r-paper-analysis
```

---

## Run on local R

### Prerequisites

**Data** — extract the raw log files from `raw_latency_logs.zip` into this directory:

```bash
unzip raw_latency_logs.zip
```

Three TSV files should now be present alongside the script:
- `ipad1_lsl_events_1759406662174.tsv`
- `ipad2_lsl_events_1759406625793.tsv`
- `pixel_events_1760093831497.tsv`

**Font** — the font files are included in the `fonts/` subdirectory (`NewCMSans10-Book.otf` and `NewCMSans10-Bold.otf`, licensed under the [GUST Font License](fonts/LICENSE.txt)).

### 1. Install R

Download and install R (≥ 4.3 recommended) from the official CRAN website:
<https://cran.r-project.org/mirrors.html>

Optionally install [RStudio](https://posit.co/download/rstudio-desktop/) as a graphical IDE.

### 2. Install required packages

Open an R session in this directory and run:

```r
install.packages(c(
  "plyr", "dplyr", "tidyverse", "jsonlite", "progress",
  "gridExtra", "conflicted", "ggprism", "showtext", "knitr"
))
```

### 3. Run the script

From an R session:

```r
setwd("/path/to/analysis")   # directory containing this README
source("latency_analysis.R")
```

Or from a terminal:

```bash
Rscript latency_analysis.R
```

`plot_latency.png` is written to the working directory.

---

## File overview

| File/Directory | Description |
|----------------|-------------|
| `latency_analysis.R` | Main analysis script |
| `raw_latency_logs.zip` | Raw TSV event logs from test devices |
| `fonts/` | NewComputerModernSans10 OTF files + license |
| `data/` | Working directory for extracted data and output figures (not version-controlled) |
| `Dockerfile` | Docker image definition |
| `entrypoint.sh` | Docker entrypoint: extracts data then runs the R script |
