library(tidyverse)
library(broom)
library(MuMIn)
library(dplyr)
library(ggplot2)
library(ggnewscale)
library(scales)

windowsFonts(Arial = windowsFont("Arial"))


############################################## Lead/Lag Group Image



#Import and merge into one dataset
JF_csv <- read_csv("") %>% 
  mutate(LC_Type ="Joint Model")
OF_csv <- read_csv("")%>% 
  mutate(LC_Type ="Open Forest")
CF_csv <- read_csv("")%>% 
  mutate(LC_Type ="Closed Forest")
merged_df <- bind_rows(JF_csv, OF_csv, CF_csv)

#Organize by forest type
merged_df <- merged_df %>%
  mutate(LC_Type = factor(LC_Type, levels = c("Joint Model", "Closed Forest", "Open Forest")))

#Organize weather variables
merged_df <- merged_df %>%
  mutate(term = factor(term, levels = c("t2m_mean", "rh_mean", "tp_mean")))

# Term label updates
var_labels <- c("t2m_mean" = "Temperature", 
                "tp_mean" = "Precipitation", 
                "rh_mean" = "Relative Humidity"
)


aic_3_plots <- ggplot() +
  #----------------------- Joint Model
  ## tiles
  geom_tile( 
    data = filter(merged_df, LC_Type == "Joint Model"),
    aes(x = lag, y = length, fill = aic),
    width = 1, height = 1
  ) +
  scale_fill_viridis_c(
    name = "AIC - Joint Model",
    breaks = pretty_breaks(n = 5),
    labels = comma,
    guide  = guide_colorbar(
      order = 1, title.position = "top", barwidth = 1, barheight = 4
    )) +
  ## points
  geom_point(
    data = filter(merged_df, LC_Type == "Joint Model") %>%
      filter(term != "(Intercept)") %>%
      group_by(LC_Type, term) %>%
      summarize(
        lag = lag[which.min(.data$aic)],
        length = length[which.min(.data$aic)],
        .groups = "drop"
      ),
    aes(x = lag, y = length),
    col = "white", size = 2
  ) +
  ggnewscale::new_scale_fill() +
  
  #----------------------- Open Forest
  ## tiles
  geom_tile( 
    data = filter(merged_df, LC_Type == "Open Forest"),
    aes(x = lag, y = length, fill = aic),
    width = 1, height = 1
  ) +
  scale_fill_viridis_c(
    name = "AIC - Open Forest",
    breaks = pretty_breaks(n = 5),
    labels = comma,
    guide  = guide_colorbar(
      order = 3, title.position = "top",
      barwidth = 1, barheight = 4
    )) +
  ## points
  geom_point(
    data = filter(merged_df, LC_Type == "Open Forest") %>%
      filter(term != "(Intercept)") %>%
      group_by(LC_Type, term) %>%
      summarize(
        lag = lag[which.min(.data$aic)],
        length = length[which.min(.data$aic)],
        .groups = "drop"
      ) ,
    aes(x = lag, y = length),
    col = "white", size = 2
  ) +
  ggnewscale::new_scale_fill() +
  
  #----------------------- Closed Forest
  ## tiles
  geom_tile( 
    data = filter(merged_df, LC_Type == "Closed Forest"),
    aes(x = lag, y = length, fill = aic),
    width = 1, height = 1
  ) +
  scale_fill_viridis_c(
    name = "AIC - Closed Forest",
    breaks = pretty_breaks(n = 5),
    labels = comma,
    guide  = guide_colorbar(
      order = 2, title.position = "top",
      barwidth = 1, barheight = 4
    )) +
  ## points
  geom_point(
    data = filter(merged_df, LC_Type == "Closed Forest") %>%
      filter(term != "(Intercept)") %>%
      group_by(LC_Type, term) %>%
      summarize(
        lag = lag[which.min(.data$aic)],
        length = length[which.min(.data$aic)],
        .groups = "drop"
      ),
    aes(x = lag, y = length),
    col = "white", size = 2
  ) +
  
  
  # Overall theme
  facet_grid(term ~ LC_Type, labeller = labeller(term = var_labels)) +
  scale_x_continuous(expand = c(0, 0)) +
  scale_y_continuous(expand = c(0, 0)) +
  labs(x = "Lag (days)", y = "Window length (days)") + 
  theme_bw() +
  theme(
    text = element_text(family = "Arial", size = 11),
    strip.text = element_text(family = "Arial", size = 10),
    legend.text = element_text(family = "Arial", size = 9),
    legend.title = element_text(family = "Arial", size = 9),
    axis.title = element_text(family = "Arial", size = 11),
    strip.background = element_rect(fill = "grey95"),
    panel.spacing = unit(0.2, "lines"),
    legend.position = "right",
    legend.box = "vertical",
    legend.spacing.y = unit(4, "pt"),
    panel.grid = element_blank(),
    panel.spacing.x = unit(0.05, "lines"),
    aspect.ratio = 0.7
  )

aic_3_plots 


out_dir <- ""
ggsave(file.path(out_dir, paste0("_aic_lag_window.png")),
       aic_3_plots, width = 7.5, height = 5.75, dpi = 300)

