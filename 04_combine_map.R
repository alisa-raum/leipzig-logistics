library(tidyverse)
library(sf)
library(tmap)


all_points <- read_sf("data/leipzig_all.geojson") |>
  mutate(category = case_when(
    amenity %in% c("parcel_locker", "parcel_pickup") ~ "Почтомат / выдача",
    amenity == "post_office"                          ~ "Почтовое отделение",
    brand %in% c("DHL Packstation", "Hermes PaketShop",
                 "DPD Pickup", "GLS ParcelShop")      ~ "Почтомат / выдача",
    shop == "parcel"                                  ~ "Почтомат / выдача",
    shop == "supermarket"                             ~ "Супермаркет",
    shop %in% c("convenience", "greengrocer",
                "butcher", "bakery", "clothes")       ~ "Малый ритейл",
    shop == "vacant"                                  ~ "Пустующее помещение",
    TRUE                                              ~ "Другое"
  )) |>
  filter(category != "Другое") |>

    select(name, category, operator, geometry)

dhl_points <- read_sf("data/dhl_packstations.geojson") |>
  mutate(category = "Почтомат / выдача") |>
  select(name, category, operator, geometry)

combined <- bind_rows(all_points, dhl_points)

cat("Всего точек до дедупликации:", nrow(combined), "\n")

combined <- combined |>
  distinct(geometry, .keep_all = TRUE)

cat("Всего точек после дедупликации:", nrow(combined), "\n")

tmap_mode("view")

tm_shape(combined) +
  tm_dots(
    fill       = "category",
    size       = 0.08,
    id         = "name",
    popup.vars = c(
      "Категория" = "category",
      "Оператор"  = "operator"
    )
  ) +
  tm_title("Логистика и ритейл в Лейпциге — OSM + DHL API")
