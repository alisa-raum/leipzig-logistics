library(tidyverse)
library(osmdata)
library(sf)

leipzig_bb <- getbb("Leipzig, Germany")

print(leipzig_bb)

library(tidyverse)
library(sf)
library(tmap)

all_points <- read_sf("data/leipzig_all.geojson")

glimpse(all_points)

cat("Всего объектов:", nrow(all_points), "\n")
cat("Типы геометрии:", paste(unique(st_geometry_type(all_points)), collapse = ", "), "\n")

names(all_points)


all_points <- all_points |>
  mutate(category = case_when(
    amenity %in% c("parcel_locker", "parcel_pickup") ~ "Почтомат / выдача",
    amenity == "post_office"                          ~ "Почтовое отделение",
    brand %in% c("DHL Packstation", "Hermes PaketShop",
                 "DPD Pickup", "GLS ParcelShop")      ~ "Почтомат / выдача",
    shop == "parcel"                                  ~ "Почтомат / выдача",
    shop == "supermarket"                             ~ "Супермаркет",
    shop %in% c("convenience", "greengrocer",
                "butcher", "bakery")                  ~ "Малый ритейл",
    shop == "clothes"                                 ~ "Одежда",
    shop == "vacant"                                  ~ "Пустующее помещение",
    TRUE ~ "Другое"  
  ))

all_points |>
  st_drop_geometry() |>  
  count(category, sort = TRUE)

points_clean <- all_points |>
  filter(category != "Другое")

tmap_mode("view")  

tm_shape(points_clean) +
  tm_dots(
    fill = "category",
    size = 0.3,
    id = "name",        
    popup.vars = c("Категория" = "category",
                   "Название" = "name",
                   "Оператор" = "operator",
                   "Адрес" = "addr:street")
  ) +
  tm_title("Логистическая инфраструктура и ритейл в Лейпциге")
