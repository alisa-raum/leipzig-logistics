library(tidyverse)
library(osmdata)
library(sf)
library(tmap)

all_points <- read_sf("data/leipzig_all.geojson")
cat("All objects:", nrow(all_points), "\n")


all_points <- all_points |>
  mutate(category = case_when(
    amenity %in% c("parcel_locker",
                   "parcel_pickup")       ~ "Locker / PikUp",
    amenity == "post_office"              ~ "Post office",
    brand %in% c("DHL Packstation",
                 "Hermes PaketShop",
                 "DPD Pickup",
                 "GLS ParcelShop")        ~ "Locker / PikUp",
    shop == "parcel"                      ~ "Locker / PikUp",
    shop == "supermarket"                 ~ "Supermarket",
    shop %in% c("convenience",
                "greengrocer",
                "butcher",
                "bakery", "clothes")      ~ "Small-scale retail",
    shop == "vacant"                      ~ "Vacant",
    TRUE                                  ~ "Other"
  ))

all_points |>
  st_drop_geometry() |>  
  count(category, sort = TRUE)

points_clean <- all_points |>
  filter(category != "Other")

tmap_mode("view")  
tm_shape(points_clean) +
  tm_dots(
    fill        = "category",
    size        = 0.3,
    id          = "name",
    popup.vars  = c(
      "Category" = "category",
      "Name"  = "name",
      "Operator"  = "operator",
      "Adress"     = "addr:street"
    )
  ) +
  tm_title("Logistics infrastructure and retail in Leipzig")
