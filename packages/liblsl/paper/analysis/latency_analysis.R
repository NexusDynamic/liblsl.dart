# Required packages
library(plyr)
library(dplyr)
library(tidyverse)
library(jsonlite)
library(gridExtra)
library(conflicted)
library(ggprism)
library(showtext)

####### SETUP #######
# install the New Computer Modern Sans font from:
# https://download.gnu.org.ua/release/newcm/
jossFont <- "NewComputerModernSans10"
jossFontFileName <- "NewCMSans10-Book.otf"
jossFontFileNameBold <- "NewCMSans10-Bold.otf"


font_add(
    family = jossFont,
    regular = jossFontFileName,
    bold = jossFontFileNameBold,
)
showtext_auto() 

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
ipad1_raw_data_path <- "ipad1_lsl_events_1759406662174.tsv"
ipad2_raw_data_path <- "ipad2_lsl_events_1759406625793.tsv"
pixel_raw_data_path <- "pixel_events_1759241635843.tsv"

# Ipad 1 -> networked to ipad 2
device_1_id <- "ipad1_001"
device_2_id <- "ipad2_002"
# Pixel 7a -> no networking, only self latency
device_3_id <- "127_DID"

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
    "EventType.sampleSent",
    "EventType.markerReceived"
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

pixel_raw <- read_tsv(pixel_raw_data_path,
    col_names = log_colnames,
    col_types = log_coldef,
    skip = 1
)

# Parse JSON metadata
# sample metadata:
# {
#     "sampleId": "LatencyTest_pixel_002_45",
#     "counter": 45,
#     "lslTimestamp": 5468.316284458,
#     "lslSent": 5468.3162845,
#     "dartTimestamp": 1748518239092311,
#     "sourceId": "LatencyTest_pixel_002",
#     "reportingDeviceId": "pixel_002",
#     "reportingDeviceName": "ipad2",
#     "testType": "",
#     "testId": ""
# }

ipad_parsed <- ipad1_raw %>%
    dplyr::mutate(
        metadata = map(metadata, ~ {
            json_data <- fromJSON(.)
            # Convert NULL values to NA and ensure all elements are vectors
            json_data[sapply(json_data, is.null)] <- NA
            as_tibble(json_data)
        })
    ) %>%
    unnest(cols = c(metadata))

ipad2_parsed <- ipad2_raw %>%
    dplyr::mutate(
        metadata = map(metadata, ~ {
            json_data <- fromJSON(.)
            json_data[sapply(json_data, is.null)] <- NA
            as_tibble(json_data)
        })
    ) %>%
    unnest(cols = c(metadata))

pixel_parsed <- pixel_raw %>%
    dplyr::mutate(
        metadata = map(metadata, ~ {
            json_data <- fromJSON(.)
            json_data[sapply(json_data, is.null)] <- NA
            as_tibble(json_data)
        })
    ) %>%
    unnest(cols = c(metadata))

# Join the two datasets
combined_data <- bind_rows(ipad_parsed, ipad2_parsed, pixel_parsed)

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

# Create a lookup table for sent event timestamps
sent_lookup <- sent_events %>%
    dplyr::mutate(raw_sent_dart_timestamp = dartTimestamp / 1000000) %>%  # Raw timestamp in seconds
    select(sampleId,
           raw_sent_dart_timestamp) %>%
    distinct()

same_device_latency <- received_events %>%
    dplyr::filter(str_extract(sourceId, paste0("(", device_1_id, "|", device_3_id, ")"), group = 1) == reportingDeviceId) %>%
    inner_join(sent_lookup, by = "sampleId") %>%
    dplyr::mutate(
        dart_latency = (timestamp - raw_sent_dart_timestamp) * 1000,  # Convert to milliseconds
        lsl_latency = (lslReceived - (lslTimestamp + lslTimeCorrection)) * 1000,  # Convert to milliseconds
        sampleId = as.numeric(str_extract(sampleId, "[^_]+$"))
    )

# between-device latency (if applicable, i.e. run simultaneously on the network)

between_device_latency <- received_events %>%
    dplyr::filter(str_extract(sourceId, paste0("(", device_1_id, "|", device_2_id, ")"), group = 1) != reportingDeviceId) %>%
    inner_join(sent_lookup, by = "sampleId") %>%
    dplyr::mutate(
        dart_latency = (timestamp - raw_sent_dart_timestamp) * 1000,  # Convert to milliseconds
        lsl_latency = (lslReceived - (lslTimestamp + lslTimeCorrection)) * 1000,   # Convert to milliseconds
        # get sample id (last number after last underscore)
        sampleId = as.numeric(str_extract(sampleId, "[^_]+$"))
    )

# Calculate summary statistics
calc_summary <- function(data, metric_name) {
    
    dart_col <- paste0("dart_", metric_name)
    lsl_col <- paste0("lsl_", metric_name)
    # Filter data that has non-missing values for Dart metric
    dart_data <- data %>%
        dplyr::filter(!is.na(dart_col))

    if (nrow(dart_data) > 0) {
        dart_stats <- dart_data %>%
            dplyr::summarise(
                min = min(get(dart_col), na.rm = TRUE) * 1000,
                lsl_min = min(get(lsl_col), na.rm = TRUE) * 1000,
                max = max(get(dart_col), na.rm = TRUE) * 1000,
                lsl_max = max(get(lsl_col), na.rm = TRUE) * 1000,
                mean = mean(get(dart_col), na.rm = TRUE) * 1000,
                lsl_mean = mean(get(lsl_col), na.rm = TRUE) * 1000,
                sd = sd(get(dart_col), na.rm = TRUE) * 1000,
                lsl_sd = sd(get(lsl_col), na.rm = TRUE) * 1000,
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
same_device_plot_df <- same_device_latency %>%
    select(device = reportingDeviceId, dart_latency, lsl_latency, sampleId) %>%
    dplyr::filter(
        !is.na(lsl_latency) &
        device %in% c(device_1_id, device_3_id)) %>%
        # sort by device
        dplyr::arrange(device, sampleId)

same_device_plot_df$device <- factor(same_device_plot_df$device,
    levels = c(device_1_id, device_3_id),
    labels = c("iPad", "Pixel 7a")
)

local_outliers_over_500us <- nrow(same_device_plot_df[same_device_plot_df$lsl_latency > 0.5,])
median.quartile <- function(x){
  out <- quantile(x, probs = c(0.25,0.5,0.75))
  names(out) <- c("25","50","75")
  return(out) 
}
local_quartiles_dev1 <- median.quartile(same_device_plot_df[same_device_plot_df$device == "iPad",]$lsl_latency)
local_quartiles_dev2 <- median.quartile(same_device_plot_df[same_device_plot_df$device == "Pixel 7a",]$lsl_latency)

p1 <- ggplot(same_device_plot_df[same_device_plot_df$lsl_latency <= 0.5,], aes(x = "iPad1 | Pixel", y = lsl_latency, fill = device)) +
    geom_split_violin(alpha = 0.7, linewidth=0.2, na.rm = TRUE) +
    labs(title = "A) API latency",
         x = NULL, y = "Latency (ms)") +
    theme_prism(base_size = 12, base_family = jossFont, base_fontface = "plain") +
    geom_segment(aes(y=local_quartiles_dev1["25"], x=0.572, xend=1), linetype = "dashed", color = "#000000", linewidth=0.2) +
    geom_segment(aes(y=local_quartiles_dev1["50"], x=0.597, xend=1), linetype = "solid", color = "#000000", linewidth=0.2) +
    geom_segment(aes(y=local_quartiles_dev1["75"], x=0.829, xend=1), linetype = "dashed", color = "#000000", linewidth=0.2) +
    geom_segment(aes(y=local_quartiles_dev2["25"], x=1, xend=1.122), linetype = "dashed", color = "#000000", linewidth=0.2) +
    geom_segment(aes(y=local_quartiles_dev2["50"], x=1, xend=1.138), linetype = "solid", color = "#000000", linewidth=0.2) +
    geom_segment(aes(y=local_quartiles_dev2["75"], x=1, xend=1.063), linetype = "dashed", color = "#000000", linewidth=0.2) +
    scale_y_continuous(
        limits = c(0, 0.5),
        breaks = seq(0, 0.5, by = 0.1),
        minor_breaks = seq(0, 0.5, by = 0.02),
        guide = "prism_offset_minor"
    ) +
    scale_x_discrete(expand = c(-0.5, 0.5)) +
    scale_fill_brewer(type = "qual", palette = "Set1") +
    theme(legend.position = "none",
          plot.title = element_text(size = 13, face = "bold"))

# between-device latency plot
between_device_plot_df <- between_device_latency %>%
    select(device = reportingDeviceId, sourceId, dart_latency, lsl_latency, sampleId) %>%
    dplyr::filter(
        !is.na(lsl_latency) &
        device %in% c(device_1_id)) %>%
        # sort by device
        dplyr::arrange(device, sampleId)

between_device_plot_df$device <- factor(between_device_plot_df$device,
    levels = c(device_1_id),
    labels = c("iPad1")
)

net_outliers_over_500us <- nrow(between_device_plot_df[between_device_plot_df$lsl_latency > 0.5,])

net_quartiles_dev1 <- median.quartile(between_device_plot_df$lsl_latency)

p2 <- ggplot(between_device_plot_df[between_device_plot_df$lsl_latency <= 0.5,], aes(x = "iPad 2 <-> iPad 1", y = lsl_latency, fill = device)) +
    geom_violin(alpha = 0.7, linewidth=0.2, na.rm = TRUE) +
    labs(title = "B) API + Network latency",
         x = NULL, y = "Latency (ms)") +
     theme_prism(base_size = 12, base_family = jossFont, base_fontface = "plain") +
    scale_y_continuous(
        limits = c(0, 0.5),
        breaks = seq(0, 0.5, by = 0.1),
        minor_breaks = seq(0, 0.5, by = 0.02),
        guide = "prism_offset_minor"
    ) +
    geom_segment(aes(y=net_quartiles_dev1["25"], x=0.6, xend=1.4), linetype = "dashed", color = "#000000", linewidth=0.2) +
    geom_segment(aes(y=net_quartiles_dev1["50"], x=0.553, xend=1.447), linetype = "solid", color = "#000000", linewidth=0.2) +
    geom_segment(aes(y=net_quartiles_dev1["75"], x=0.68, xend=1.32), linetype = "dashed", color = "#000000", linewidth=0.2) +
    scale_fill_brewer(type = "qual", palette = "Set1") +
    theme(legend.position = "none",
          plot.title = element_text(size = 13, face = "bold"))



plot.out <- grid.arrange(p1, p2, nrow = 1, widths = c(1, 1))
ggsave("plot_latency.png", plot.out, width = 7, height = 4, dpi = 300)


ipad_latency_summary <- calc_summary(same_device_plot_df[same_device_plot_df$device == "iPad",], "latency")
pixel_latency_summary <- calc_summary(same_device_plot_df[same_device_plot_df$device == "Pixel 7a",], "latency")

# do a between-device latency summary
between_device_lsl <- between_device_plot_df %>%
    select(device, dart_latency, lsl_latency) %>%
    dplyr::filter(!is.na(dart_latency))

between_device_latency_summary <- calc_summary(between_device_lsl, "latency")
figcaption <- paste0(
    "Figure 1. Dart liblsl API latency plots. Panel A shows latency ",
    "for an iPad and a Pixel 7a, each producing and consuming their own 1000 Hz ",
    "data stream with 16 channels of float data. ",
    "iPad Latency: n = ", ipad_latency_summary$count,
    ", Mean = ", round(ipad_latency_summary$lsl_mean, 0),
    "µs, SD = ", round(ipad_latency_summary$lsl_sd, 0),
    "µs | Pixel Latency: n = ", pixel_latency_summary$count,
    ", Mean = ", round(pixel_latency_summary$lsl_mean, 0),
    "µs, SD = ", round(pixel_latency_summary$lsl_sd, 0),
    "µs; ",
    "Panel B shows latency for two iPads producing and consuming each other's 1000 Hz ",
    "data stream with 16 channels of float data over a local wired 1Gbps network. ",
    "iPad (between-device) Latency: n = ", between_device_latency_summary$count,
    ", Mean = ", round(between_device_latency_summary$lsl_mean, 0),
    "µs, SD = ", round(between_device_latency_summary$lsl_sd, 0),
    "µs. ",
    "Note: Dashed lines represent the 1st and 3rd quartiles, solid line represents the median. ",
    "Outliers > 500 ms not shown, but are included in the summary statistics calcultation. "
)
cat(figcaption)
