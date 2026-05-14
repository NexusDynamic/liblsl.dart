# Reproduces the liblsl.dart latency analysis figure.
# Packages, font files, and raw data are all baked into the image.
# Mount an empty data/ directory at /data to receive extracted TSV files
# and the output figure.
#
# Build:
#   docker build -t liblsl-analysis .
#
# Run (outputs plot_latency.png to data/ on the host):
#   docker run --rm -v "$(pwd)/data:/data" liblsl-analysis
FROM rocker/tidyverse:latest

# System libraries required by showtext / systemfonts
RUN apt-get update && apt-get install -y --no-install-recommends \
        libfreetype6-dev \
        libfontconfig1-dev \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# R packages not bundled with rocker/tidyverse
RUN Rscript -e "install.packages( \
        c('plyr', 'gridExtra', 'conflicted', 'ggprism', 'showtext', 'knitr', 'progress'), \
        repos = 'https://cloud.r-project.org')"

# Font files (GUST Font License — see fonts/LICENSE.txt)
COPY fonts/ /fonts/

# Analysis script, entrypoint, and raw data
COPY latency_analysis.R    /scripts/latency_analysis.R
COPY entrypoint.sh         /scripts/entrypoint.sh
COPY raw_latency_logs.zip  /scripts/raw_latency_logs.zip

RUN chmod +x /scripts/entrypoint.sh

# /data is mounted at runtime; TSV files are extracted there on first run
# and the output figure is written there too.
WORKDIR /data

ENTRYPOINT ["/scripts/entrypoint.sh"]
