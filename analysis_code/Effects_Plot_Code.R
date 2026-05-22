library(tidyverse)
library(tibble)
windowsFonts(Arial = windowsFont("Arial"))

#Import and merge into one dataset
JF_csv <- read_csv("") %>% 
  mutate(LC_Type ="Joint Model") 
OF_csv <- read_csv("")%>% 
  mutate(LC_Type ="Open Forest")
CF_csv <- read_csv("")%>% 
  mutate(LC_Type ="Closed Forest")
merged_df <- bind_rows(JF_csv, OF_csv, CF_csv)

#Organize Models
merged_df <- merged_df %>%
  mutate(LC_Type = factor(LC_Type, levels = c("Joint Model", "Closed Forest", "Open Forest")))

# Create data conversion table from our csv coloumns -> how we want it to look -> type
data_conversion <- tribble(
  ~pred_var, ~var_name, ~var_type,
  "t2m_mean_ztrans","Temperature (°C)","Weather",
  "tp_mean_ztrans","Total Precipitation (mm)", "Weather",
  "t2m_mean_ztrans:tp_mean_ztrans", "Temp × Precipitation","Weather", 
  "rh_mean_ztrans", "Relative Humidity (%)","Weather",
  "ws_mean_ztrans", "Wind Speed (ms-1)","Weather",
  "dry_lightningTRUE",  "Dry Lightning (True)","Lightning",
  "multiplicity_mean_ztrans","Multiplicity", "Lightning",
  "peakcurrent_mean_ztrans","Peak Current (amp)","Lightning",
  "polarity_mean1",  "Polarity (Positive)","Lightning",
  "duration_mean_ztrans", "Duration (ms)", "Lightning",
  "NPP_ztrans","NPP (kg*C/m^2)", "Fuel"
)
#head(data_conversion)

plot_df <- merged_df %>%
  inner_join(data_conversion, by = c("term" = "pred_var")) %>%
  transmute(
    LC_Type,
    var_type,
    var_name,
    effect = or_estimate - 1,
    xmin   = or_conf.low - 1,
    xmax   = or_conf.high - 1
  ) %>%
  mutate(
    significant = (xmin > 0 | xmax < 0), # significance
    Forest = LC_Type,
    var_type = factor(var_type, levels = c("Weather", "Lightning", "Fuel")),
    var_name = factor(
      var_name,
      levels = c("Temperature (°C)", "Total Precipitation (mm)","Temp × Precipitation", "Relative Humidity (%)",
                 "Wind Speed (ms-1)","Dry Lightning (True)","Multiplicity","Peak Current (amp)",  "Polarity (Positive)",
                 "Duration (ms)", "NPP (kg*C/m^2)")))


p_effects <- ggplot(plot_df, aes(x = effect, y = var_name, color = var_type)) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.9, color = "black") +
  geom_errorbarh(aes(xmin = xmin, xmax = xmax), height = 0.15, linewidth = 0.8) +
  
  #add halo to points
  geom_point(
    data = subset(plot_df, significant),
    size = 7,           
    alpha = 0.25,       
    show.legend = FALSE
  ) +
  
  # add points
  geom_point(size = 3) +
  facet_wrap(~ Forest, nrow = 1) +
  scale_y_discrete(limits = rev(levels(plot_df$var_name))) +
  scale_color_manual(
    name = "Variable Type",
    values = c(
      "Weather"   = "#3B1F70",
      "Lightning" = "#1C8C8C",
      "Fuel"      = "#7AD63A"
    )
  ) +
  labs(x = "Effects (Odds Ratio - 1)", y = NULL) +
  theme_bw() +
  theme(
    strip.background = element_rect(fill = "grey90", color = "black"),
    strip.text = element_text(size = 11),
    axis.text.y = element_text(size = 11),
    axis.text.x = element_text(size = 11),
    axis.title.x = element_text(size = 11),
    legend.title = element_text(size = 11),
    legend.text = element_text(size = 11),
    legend.position = "right",
    panel.grid.major.y = element_line(color = "grey85"),
    panel.grid.minor = element_blank()
  )

p_effects

# ---- Save ----
out_dir <- "" #out directory here
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

ggsave(
  file.path(out_dir, "effects_plot.png"),
  p_effects,
  width = 7.5, height = 5.5, dpi = 300
)
