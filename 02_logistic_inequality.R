library(tidyverse)
library(sf)
library(tmap)

ortsteile <- read_sf("data/Ortsteile.json")
ortsteile <- st_transform(ortsteile, crs = 4326)

cat("Районов:", nrow(ortsteile), "\n")

tmap_mode("view")

tm_shape(ortsteile) +
  tm_borders(col = "black", lwd = 1) +
  tm_text("Name", size = 0.5) +
  tm_title("Районы Лейпцига (Ortsteile)")

all_points <- read_sf("data/leipzig_all.geojson") |>
  mutate(category = case_when(
    amenity %in% c("parcel_locker", "parcel_pickup") ~ "Почтомат / выдача",
    amenity == "post_office"                          ~ "Почтовое отделение",
    brand %in% c("DHL Packstation", "Hermes PaketShop",
                 "DPD Pickup", "GLS ParcelShop")      ~ "Почтомат / выдача",
    shop == "parcel"                                  ~ "Почтомат / выдача",
    shop == "supermarket"                             ~ "Супермаркет",
    shop %in% c("convenience", "greengrocer",
                "butcher", "bakery", "clotes")        ~ "Малый ритейл",
    shop == "vacant"                                  ~ "Пустующее помещение",
    TRUE                                              ~ "Другое"
  )) |>
  filter(category != "Другое")

points_with_district <- st_join(all_points, ortsteile["Name"])

district_counts <- points_with_district |>
  st_drop_geometry() |>
  count(Name, category) |>
  pivot_wider(
    names_from  = category,
    values_from = n,
    values_fill = 0)
    
    print(district_counts)
    
    
    ortsteile_stats <- ortsteile |>
      left_join(district_counts, by = "Name") |>
      
      mutate(across(where(is.numeric), ~replace_na(., 0)))
    
    tmap_mode("view")
    
    tm_shape(ortsteile_stats) +
      tm_polygons(
        fill = "Почтомат / выдача",
        fill.scale = tm_scale_continuous(
          values = "brewer.yl_or_rd"  # жёлтый → красный
        ),
        fill.legend = tm_legend(title = "Почтоматов\nи точек выдачи"),
        col = "white",
        lwd = 0.5,
        id = "Name",
        popup.vars = c(
          "Почтомат / выдача",
          "Малый ритейл",
          "Пустующее помещение",
          "Супермаркет"
        )
      ) +
      tm_title("Плотность логистической инфраструктуры по районам Лейпцига")