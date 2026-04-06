library(tidyverse)
library(sf)
library(tmap)

# РАЙОНЫ

ortsteile <- read_sf("data/Ortsteile.json") |>
  st_transform(crs = 4326)

# ТОЧКИ — OSM + DHL

all_points <- read_sf("data/leipzig_all.geojson") |>
  mutate(category = case_when(
    amenity %in% c("parcel_locker", "parcel_pickup") ~ "Locker / Pickup",
    amenity == "post_office"                          ~ "Post Office",
    brand %in% c("DHL Packstation", "Hermes PaketShop",
                 "DPD Pickup", "GLS ParcelShop")      ~ "Locker / Pickup",
    shop == "parcel"                                  ~ "Locker / Pickup",
    shop == "supermarket"                             ~ "Supermarket",
    shop %in% c("convenience", "greengrocer",
                "butcher", "bakery")                  ~ "Small-scale retail",
    shop == "vacant"                                  ~ "Vacant",
    TRUE                                              ~ "Other"
  )) |>
  filter(category != "Другое") |>
  select(name, category, operator, geometry)

dhl_points <- read_sf("data/dhl_packstations.geojson") |>
  mutate(category = "Locker / Pickup") |>
  select(name, category, operator, geometry)

all_points <- bind_rows(all_points, dhl_points) |>
  distinct(geometry, .keep_all = TRUE)

cat("Всего точек:", nrow(all_points), "\n")


# ПО РАЙОНАМ

points_with_district <- st_join(all_points, ortsteile["Name"])

district_counts <- points_with_district |>
  st_drop_geometry() |>
  count(Name, category) |>
  pivot_wider(
    names_from  = category,
    values_from = n,
    values_fill = 0
  )


# НАСЕЛЕНИЕ

population <- read_csv("data/Bevolkerungsbestand_Einwohner.csv") |>
  filter(Sachmerkmal == "Einwohner insgesamt") |>
  select(Name = Gebiet, population = `2024`) |>
  mutate(population = as.numeric(gsub("[^0-9]", "", population)))

# BODENRICHTWERTE 2024 — стоимость земли
brw <- read_sf("data/BRW_Zonen_2024.json") |>
  st_make_valid() |>
  st_transform(crs = 4326) |>
  filter(!is.na(brw)) |>
  select(brw, entw, nuta, geometry)

cat("BRW zones:", nrow(brw), "\n")

brw_by_district <- st_join(brw, ortsteile["Name"]) |>
  st_drop_geometry() |>
  group_by(Name) |>
  summarise(
    brw_mean   = mean(brw, na.rm = TRUE),
    brw_median = median(brw, na.rm = TRUE),
    brw_max    = max(brw, na.rm = TRUE)
  )

cat("Districts with BRW data:", nrow(brw_by_district), "\n")

# ВМЕСТЕ

ortsteile_stats <- ortsteile |>
  left_join(district_counts, by = "Name") |>
  left_join(population, by = "Name") |>
  left_join(brw_by_district, by = "Name") |>
  mutate(across(where(is.numeric), ~replace_na(., 0))) |>
  mutate(
    area_km2 = as.numeric(st_area(geometry)) / 1000000,
    locker_per_1000     = (`Locker / Pickup` / population) * 1000,
    locker_per_km2      = `Locker / Pickup` / area_km2,
    logistics_retail_ratio = `Locker / Pickup` / (`Small-scale retail` + 1)
  )

cat("Готово. Районов:", nrow(ortsteile_stats), "\n")


# КАРТА 1 — АБСОЛЮТНЫЕ ЧИСЛА

tmap_mode("view")

map1 <- tm_shape(ortsteile_stats) +
  tm_polygons(
    fill = "Locker / Pickup",
    fill.scale = tm_scale_continuous(values = "brewer.yl_or_rd"),
    fill.legend = tm_legend(title = "Lockers(abs.)"),
    col = "white", lwd = 0.5,
    id = "Name",
    popup.vars = c(
      "Locker / Pickup"  = "Locker / Pickup",
      "Small-scale retail"       = "Small-scale retail",
      "Vacant"          = "Vacant"
    )
  ) +
  tm_title("1. Total number of lockers by district")

map1


# КАРТА 2 — НА 1000 ЖИТЕЛЕЙ

map2 <- tm_shape(ortsteile_stats) +
  tm_polygons(
    fill = "locker_per_1000",
    fill.scale = tm_scale_continuous(
      values = "brewer.yl_or_rd",
      value.na = "grey80"
    ),
    fill.legend = tm_legend(title = "Lockers per 1000 inh."),
    col = "white", lwd = 0.5,
    id = "Name",
    popup.vars = c(
      "Population"          = "population",
      "Locker / Pickup"  = "Locker / Pickup",
      "Per 1000 inh"       = "locker_per_1000"
    )
  ) +
  tm_title("2. Lockers per 1.000 inhabitants")

map2


# КАРТА 3 — НА КМ²

map3 <- tm_shape(ortsteile_stats) +
  tm_polygons(
    fill = "locker_per_km2",
    fill.scale = tm_scale_continuous(
      values = "brewer.yl_or_rd",
      value.na = "grey80"
    ),
    fill.legend = tm_legend(title = "Lockers per km²"),
    col = "white", lwd = 0.5,
    id = "Name",
    popup.vars = c(
      "Area km²"        = "area_km2",
      "Locker / Pickup"  = "Locker / Pickup",
      "Per km²"             = "locker_per_km2"
    )
  ) +
  tm_title("3. Density of lockers per km²")

map3


# КАРТА 4 — ИНДЕКС ЛОГИСТИКА vs РИТЕЙЛ

map4 <- tm_shape(ortsteile_stats) +
  tm_polygons(
    fill = "logistics_retail_ratio",
    fill.scale = tm_scale_continuous(
      values   = "brewer.rd_bu",
      midpoint = 1,
      value.na = "grey80"
    ),
    fill.legend = tm_legend(
      title = "Logistics / Retail"
    ),
    col = "white", lwd = 0.5,
    id = "Name",
    popup.vars = c(
      "Locker / Pickup"  = "Locker / Pickup",
      "Small-scale retail"       = "Small-scale retail",
      "Index"             = "logistics_retail_ratio"
    )
  ) +
  tm_title("4. Index: Logistics vs Small Retail")

map4

# КАРТА 5 — СТОИМОСТЬ ЗЕМЛИ
map5 <- tm_shape(ortsteile_stats) +
  tm_polygons(
    fill = "brw_median",
    fill.scale = tm_scale_continuous(
      values   = "brewer.yl_gn_bu",
      value.na = "grey80"
    ),
    fill.legend = tm_legend(title = "Land value\n€/m² (median)"),
    col = "white", lwd = 0.5,
    id = "Name",
    popup.vars = c(
      "Land value median €/m²" = "brw_median",
      "Land value mean €/m²"   = "brw_mean",
      "Locker / Pickup"        = "Locker / Pickup",
      "Small-scale retail"     = "Small-scale retail"
    )
  ) +
  tm_title("5. Land value by district (Bodenrichtwert 2024)")

map5


# СОХРАНЕНИЕ КАРТ

dir.create("plots", showWarnings = FALSE)

tmap_save(map1, "plots/map1_absolute.html")
tmap_save(map2, "plots/map2_per_1000.html")
tmap_save(map3, "plots/map3_per_km2.html")
tmap_save(map4, "plots/map4_index.html")
tmap_save(map5, "plots/map5_land_value.html")

cat("Все карты сохранены в папку plots/\n")


# КОРРЕЛЯЦИЯ: стоимость земли vs логистика

corr_data <- ortsteile_stats |>
  st_drop_geometry() |>
  filter(population > 0, brw_median > 0, `Locker / Pickup` > 0) |>
  select(Name, brw_median, `Locker / Pickup`,
         locker_per_1000, `Small-scale retail`,
         logistics_retail_ratio)

cor_locker_brw <- cor(
  corr_data$brw_median,
  corr_data$`Locker / Pickup`,
  method = "spearman"
)

cor_retail_brw <- cor(
  corr_data$brw_median,
  corr_data$`Small-scale retail`,
  method = "spearman"
)

cat("Корреляция (Spearman):\n")
cat("Land value vs Lockers:", round(cor_locker_brw, 3), "\n")
cat("Land value vs Retail:", round(cor_retail_brw, 3), "\n")

ggplot(corr_data, aes(x = brw_median, y = `Locker / Pickup`)) +
  geom_point(size = 3, color = "#E63946", alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE,
              color = "black", linewidth = 0.8) +
  geom_text(aes(label = Name), size = 2.5,
            vjust = -0.8, check_overlap = TRUE) +
  labs(
    title    = "Land value vs. logistics infrastructure density",
    subtitle = "Leipzig districts, 2024",
    x        = "Median land value (Bodenrichtwert), €/m²",
    y        = "Number of parcel lockers and pickup points",
    caption  = "Sources: Stadtplan Leipzig (BRW 2024), OSM, DHL API"
  ) +
  theme_minimal(base_size = 13)

ggsave("plots/correlation_brw_lockers.png",
       width = 10, height = 7, dpi = 150)