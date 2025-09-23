# Required packages
library(plyr)
library(dplyr)
library(tidyverse)
library(jsonlite)
library(gridExtra)
library(conflicted)
library(ggprism)



####### SETUP #######

## Geom split violin from: https://stackoverflow.com/a/47652563/570122

GeomSplitViolin <- ggproto("GeomSplitViolin", GeomViolin,
  draw_group = function(self, data, ..., draw_quantiles = NULL) {
    # Original function by Jan Gleixner (@jan-glx)
    # Adjustments by Wouter van der Bijl (@Axeman)
    data <- transform(data, xminv = x - violinwidth * (x - xmin), xmaxv = x + violinwidth * (xmax - x))
    grp <- data[1, "group"]
    newdata <- plyr::arrange(transform(data, x = if (grp %% 2 == 1) xminv else xmaxv), if (grp %% 2 == 1) y else -y)
    newdata <- rbind(newdata[1, ], newdata, newdata[nrow(newdata), ], newdata[1, ])
    newdata[c(1, nrow(newdata) - 1, nrow(newdata)), "x"] <- round(newdata[1, "x"])
    if (length(draw_quantiles) > 0 & !scales::zero_range(range(data$y))) {
      stopifnot(all(draw_quantiles >= 0), all(draw_quantiles <= 1))
      quantiles <- create_quantile_segment_frame(data, draw_quantiles, split = TRUE, grp = grp)
      aesthetics <- data[rep(1, nrow(quantiles)), setdiff(names(data), c("x", "y")), drop = FALSE]
      aesthetics$alpha <- rep(1, nrow(quantiles))
      both <- cbind(quantiles, aesthetics)
      quantile_grob <- GeomPath$draw_panel(both, ...)
      ggplot2:::ggname("geom_split_violin", grid::grobTree(GeomPolygon$draw_panel(newdata, ...), quantile_grob))
    }
    else {
      ggplot2:::ggname("geom_split_violin", GeomPolygon$draw_panel(newdata, ...))
    }
  }
)

create_quantile_segment_frame <- function(data, draw_quantiles, split = FALSE, grp = NULL) {
  dens <- cumsum(data$density) / sum(data$density)
  ecdf <- stats::approxfun(dens, data$y)
  ys <- ecdf(draw_quantiles)
  violin.xminvs <- (stats::approxfun(data$y, data$xminv))(ys)
  violin.xmaxvs <- (stats::approxfun(data$y, data$xmaxv))(ys)
  violin.xs <- (stats::approxfun(data$y, data$x))(ys)
  if (grp %% 2 == 0) {
    data.frame(
      x = ggplot2:::interleave(violin.xs, violin.xmaxvs),
      y = rep(ys, each = 2), group = rep(ys, each = 2)
    )
  } else {
    data.frame(
      x = ggplot2:::interleave(violin.xminvs, violin.xs),
      y = rep(ys, each = 2), group = rep(ys, each = 2)
    )
  }
}


##### LOAD DATA ######

geom_split_violin <- function(mapping = NULL, data = NULL, stat = "ydensity", position = "identity", ..., 
                              draw_quantiles = NULL, trim = TRUE, scale = "area", na.rm = FALSE, 
                              show.legend = NA, inherit.aes = TRUE) {
  layer(data = data, mapping = mapping, stat = stat, geom = GeomSplitViolin, position = position, 
        show.legend = show.legend, inherit.aes = inherit.aes, 
        params = list(trim = trim, scale = scale, draw_quantiles = draw_quantiles, na.rm = na.rm, ...))
}

# File paths
ipad1_raw_data_path <- "ipad1_lsl_events_1748518428437.tsv"
ipad2_raw_data_path <- "ipad2_lsl_events_1748518473569.tsv"

# Columns
log_colnames <- c(
    "log_timestamp",
    "timestamp",
    "event_id",
    "event_type",
    "lsl_clock",
    "description",
    "metadata"
)

# events in the logs
event_type_levels <- c(
    "EventType.testStarted",
    "EventType.sampleReceived",
    "EventType.sampleSent"
)

# Column definitions
log_coldef <- cols(
    log_timestamp = col_double(),
    timestamp = col_double(),
    event_id = col_character(),
    event_type = col_factor(
        levels = event_type_levels
    ),
    lsl_clock = col_double(),
    description = col_character(),
    metadata = col_character()
)

# read in the raw data
ipad1_raw <- read_tsv(ipad1_raw_data_path,
    col_names = log_colnames,
    col_types = log_coldef,
    skip = 1
)

ipad2_raw <- read_tsv(ipad2_raw_data_path,
    col_names = log_colnames,
    col_types = log_coldef,
    skip = 1
)

# Parse JSON metadata
# sample metadata:
# {
#     "sampleId": "LatencyTest_ipad2_002_45",
#     "counter": 45,
#     "lslTimestamp": 5468.316284458,
#     "lslSent": 5468.3162845,
#     "dartTimestamp": 1748518239092311,
#     "sourceId": "LatencyTest_ipad2_002",
#     "reportingDeviceId": "ipad2_002",
#     "reportingDeviceName": "ipad2",
#     "testType": "",
#     "testId": ""
# }

ipad1_parsed <- ipad1_raw %>%
    dplyr::mutate(
        metadata = map(metadata, ~ fromJSON(.) %>% as_tibble())
    ) %>%
    unnest(cols = c(metadata))

ipad2_parsed <- ipad2_raw %>%
    dplyr::mutate(
        metadata = map(metadata, ~ fromJSON(.) %>% as_tibble())
    ) %>%
    unnest(cols = c(metadata))


# Join the two datasets
combined_data <- bind_rows(ipad1_parsed, ipad2_parsed)

# Filter out testStarted events
sample_data <- combined_data %>%
    dplyr::filter(event_type != "EventType.testStarted")

# Separate sent and received events
sent_events <- sample_data %>%
    dplyr::filter(event_type == "EventType.sampleSent") %>%
    dplyr::arrange(sourceId, counter)

received_events <- sample_data %>%
    dplyr::filter(event_type == "EventType.sampleReceived") %>%
    dplyr::arrange(sourceId, counter, reportingDeviceId)

# Calculate ISI for samples sent from each device
production_isi <- sent_events %>%
    group_by(sourceId) %>%
    dplyr::arrange(counter) %>%
    dplyr::mutate(
        dart_isi = c(NA, diff(dartTimestamp / 1000))  # Convert to milliseconds
    ) %>%
    ungroup()

# Create a lookup table for sent event timestamps
sent_lookup <- sent_events %>%
    dplyr::mutate(raw_sent_dart_timestamp = dartTimestamp / 1000000) %>%  # Raw timestamp in seconds
    select(sampleId,
           raw_sent_dart_timestamp) %>%
    distinct()

same_device_latency <- received_events %>%
    dplyr::filter(str_extract(sourceId, "ipad[12]") == reportingDeviceName) %>%
    left_join(sent_lookup, by = "sampleId") %>%
    dplyr::mutate(
        dart_latency = (timestamp - raw_sent_dart_timestamp) * 1000  # Convert to milliseconds
    )

# Calculate summary statistics
calc_summary <- function(data, metric_name) {
    
    dart_col <- paste0("dart_", metric_name)
    # Filter data that has non-missing values for Dart metric
    dart_data <- data %>%
        dplyr::filter(!is.na(get(dart_col)))

    if (nrow(dart_data) > 0) {
        dart_stats <- dart_data %>%
            dplyr::summarise(
                min = min(get(dart_col), na.rm = TRUE) * 1000,
                max = max(get(dart_col), na.rm = TRUE) * 1000,
                mean = mean(get(dart_col), na.rm = TRUE) * 1000,
                sd = sd(get(dart_col), na.rm = TRUE) * 1000,
                count = n(),
                .groups = "drop"
            ) %>%
            dplyr::mutate(timestamp_type = "Dart", metric = metric_name)
    } else {
        dart_stats <- tibble(
            min = NA_real_, max = NA_real_, mean = NA_real_, sd = NA_real_,
            timestamp_type = "Dart", metric = metric_name
        )
    }

    dart_stats
}


# Within-device latency violin plot
same_device_dart <- same_device_latency %>%
    select(device = reportingDeviceName, dart_latency) %>%
    dplyr::filter(!is.na(dart_latency))

p1 <- ggplot(same_device_dart, aes(x = "iPad 1 | iPad 2", y = dart_latency, fill = device)) +
    geom_split_violin(alpha = 0.7, draw_quantiles = c(0.25,0.50,0.75)) +
    labs(title = "Send-Receieve Latency",
         x = NULL, y = "Latency (ms)") +
     theme_prism(base_size = 16) +
    ylim(0, 2) +
    scale_fill_brewer(type = "qual", palette = "Set1") +
    theme(legend.position = "none")

# ISI production violin plot
production_dart <- production_isi %>%
    select(sourceId, dart_isi) %>%
    dplyr::mutate(device = str_extract(sourceId, "ipad[12]")) %>%
    dplyr::filter(!is.na(dart_isi))

p2 <- ggplot(production_dart, aes(x = "iPad 1 | iPad 2", y = dart_isi, fill = device)) +
    geom_split_violin(alpha = 0.7, draw_quantiles = c(0.25,0.50,0.75)) +
    labs(title = "Sample production ISI",
         x = NULL, y = "Inter-Sample Interval (ms)") +
     theme_prism(base_size = 16) +
    ylim(0, 2) +
    scale_fill_brewer(type = "qual", palette = "Set1") +
    theme(legend.position = "none")



grid.arrange(p1, p2, nrow = 1, widths = c(1, 1))


ipad1_latency_summary <- calc_summary(same_device_dart[same_device_dart$device == "ipad1",], "latency")
ipad2_latency_summary <- calc_summary(same_device_dart[same_device_dart$device == "ipad2",], "latency")

ipad1_isi_summary <- calc_summary(production_dart[production_dart$device == "ipad1",], "isi")
ipad2_isi_summary <- calc_summary(production_dart[production_dart$device == "ipad2",], "isi")
# micro symbol: µ 
figcaption <- paste0(
    "Distribution plots showing latency and inter-sample interval (ISI) for iPad 1 and iPad 2 using Dart timestamps.",
    " iPad 1 Latency (µs): n =",
    ipad1_latency_summary$count,
    " Mean = ",
    round(ipad1_latency_summary$mean, 0),
    ", SD = ",
    round(ipad1_latency_summary$sd, 0),
    " | iPad 2 Latency (µs): n = ",
    ipad2_latency_summary$count,
    ", Mean = ",
    round(ipad2_latency_summary$mean, 0),
    "SD =",
    round(ipad2_latency_summary$sd, 0),
    "; ",
    "iPad 1 ISI (ms): n =",
    ipad1_isi_summary$count,
    ", Mean =",
    round(ipad1_isi_summary$mean, 0),
    "SD =",
    round(ipad1_isi_summary$sd, 0),
    "| iPad 2 ISI (ms): n = ",
    ipad2_isi_summary$count,
    "Mean =",
    round(ipad2_isi_summary$mean, 0),
    "SD =",
    round(ipad2_isi_summary$sd, 0)
)
cat(figcaption)
