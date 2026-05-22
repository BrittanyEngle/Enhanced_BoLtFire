library(sf)
library(ggplot2)
library(dplyr)
library(readr)
library(rnaturalearth)
library(rnaturalearthdata)
library(elevatr)
library(terra)
library(ggnewscale)
library(tidyterra)
library(grid)
library(ragg)

# Colors
col_closed  <- "#45145E"
col_open    <- "#299A87"
col_ocean   <- "#EDF5FB"
col_land    <- "#F8F8F5"
col_boreal  <- "#ECECE4"
col_country <- "#C4C4C4"
col_grat    <- "#E3E3E3"
col_circle  <- "#7A7A7A"

# Settings
sf_use_s2(FALSE)
target_crs <- 3995

# Import spatial data
fires_shp_path  <- ""
boreal_shp_path <- ""
dat_csv_path <- ""
fires <- st_read(fires_shp_path, quiet = TRUE) %>%
  st_make_valid()

boreal_shp <- st_read(boreal_shp_path, quiet = TRUE) %>%
  st_make_valid() %>%
  st_transform(target_crs) %>%
  st_simplify(dTolerance = 5000)

dat_csv <- read_csv(dat_csv_path, show_col_types = FALSE)

# Recode landcover classes
dat_master <- dat_csv %>%
  filter(offset == 0) %>%
  mutate(
    LC_Name = case_when(
      LC_Name %in% c("Grasslands", "Open Shrublands", "Savannas", "Woody Savannas", "Closed Shrublands", "Permanent Wetlands") ~ "Open Forest",
      LC_Name %in% c("Evergreen Needleleaf Forests", "Evergreen Broadleaf Forests", "Deciduous Needleleaf Forests", "Deciduous Broadleaf Forests", "Mixed Forests") ~ "Closed Forest",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(LC_Name)) %>%
  count(FireID, LC_Name, name = "n") %>%
  group_by(FireID) %>%
  arrange(FireID, desc(n), LC_Name) %>%
  slice(1) %>%
  ungroup() %>%
  mutate(LC_Name = factor(LC_Name, levels = c("Open Forest", "Closed Forest"))) %>%
  select(FireID, LC_Name)

# Join class back to fires
fires <- fires %>%
  left_join(dat_master, by = "FireID") %>%
  filter(LC_Name %in% c("Open Forest", "Closed Forest")) %>%
  st_as_sf() %>%
  st_transform(target_crs) %>%
  st_simplify(dTolerance = 1000)

# Base map
world <- ne_countries(scale = "medium", returnclass = "sf") %>%
  st_make_valid()

pole <- st_sfc(st_point(c(0, 0)), crs = target_crs)
arctic_buffer <- st_buffer(pole, dist = 5200000)

land_map <- ne_countries(continent = c("North America", "Europe", "Asia"), scale = "medium", returnclass = "sf") %>%
  st_make_valid() %>%
  st_transform(target_crs) %>%
  summarise()

arctic_land <- st_intersection(land_map, arctic_buffer)
boreal_arctic <- st_intersection(boreal_shp, arctic_buffer)

country_lines <- world %>%
  st_transform(target_crs) %>%
  st_intersection(arctic_buffer) %>%
  st_simplify(dTolerance = 5000)

# Elevation + improved hillshade
arctic_download_ll <- st_sfc(
  st_polygon(list(matrix(c(-179.9, 45, 179.9, 45, 179.9, 89.9, -179.9, 89.9, -179.9, 45), ncol = 2, byrow = TRUE))),
  crs = 4326
) %>%
  st_sf()

elev_raster <- elevatr::get_elev_raster(locations = arctic_download_ll, z = 4, clip = "locations")
elev <- terra::rast(elev_raster) %>%
  terra::project(paste0("EPSG:", target_crs))

arctic_vect <- terra::vect(arctic_buffer)
land_vect <- terra::vect(arctic_land)

elev <- elev %>%
  terra::crop(arctic_vect) %>%
  terra::mask(arctic_vect) %>%
  terra::mask(land_vect) %>%
  terra::aggregate(fact = 2, fun = mean)

slope <- terra::terrain(elev, v = "slope", unit = "radians")
aspect <- terra::terrain(elev, v = "aspect", unit = "radians")

hill <- terra::shade(slope, aspect, angle = 40, direction = 45)
hill_small <- terra::aggregate(hill, fact = 1.5, fun = mean)

qs <- terra::global(hill_small, quantile, probs = c(0.02, 0.98), na.rm = TRUE)
qmin <- qs[1, 1]
qmax <- qs[1, 2]

hill_plot <- terra::clamp(hill_small, lower = qmin, upper = qmax, values = TRUE) %>%
  {. / (qmax - qmin) - qmin / (qmax - qmin)}
names(hill_plot) <- "shade"

# Graticule
grat <- st_graticule(lat = seq(50, 90, by = 10), lon = seq(-180, 180, by = 30), crs = 4326) %>%
  st_transform(target_crs) %>%
  st_intersection(arctic_buffer)

# Plot
p <- ggplot() +
  geom_sf(data = arctic_buffer, fill = col_ocean, color = NA) +
  geom_sf(data = arctic_land, fill = col_land, color = NA) +
  geom_sf(data = boreal_arctic, fill = col_boreal, color = NA, alpha = 0.10) +
  geom_spatraster(data = hill_plot, aes(fill = shade), alpha = 0.42) +
  scale_fill_gradient(low = "grey97", high = "grey22", guide = "none", na.value = "transparent") +
  ggnewscale::new_scale_fill() +
  geom_sf(data = country_lines, fill = NA, color = col_country, linewidth = 0.22) +
  geom_sf(data = grat, fill = NA, color = col_grat, linewidth = 0.18) +
  geom_sf(data = fires, aes(fill = LC_Name, color = LC_Name), linewidth = 0.30, alpha = 0.85) +
  scale_fill_manual(values = c("Open Forest" = col_open, "Closed Forest" = col_closed), name = NULL) +
  scale_color_manual(values = c("Open Forest" = col_open, "Closed Forest" = col_closed), guide = "none") +
  geom_sf(data = arctic_buffer, fill = NA, color = col_circle, linewidth = 0.35) +
  coord_sf(crs = st_crs(target_crs), expand = FALSE) +
  theme_void() +
  theme(
    legend.position = "right",
    legend.text = element_text(size = 11),
    legend.key.size = unit(0.55, "cm"),
    legend.spacing.y = unit(0.15, "cm"),
    legend.background = element_rect(fill = "white", color = NA),
    legend.key = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA)
  )

p

# Save
out_dir <- ""
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

ggsave(
  filename = file.path(out_dir, "plot_pub.png"),
  plot = p,  width = 7.5,  height = 7.5,  dpi = 600,  bg = "white",  device = ragg::agg_png)