library(tidyverse)
library(sf)
library(tmap)
library(googleway)

# ДАННЫЕ


ortsteile <- read_sf("data/Ortsteile.json") |>
  st_transform(crs = 4326)

reviews <- read_csv("data/google_reviews.csv")
places  <- read_sf("data/google_places_full.geojson")

# СРЕДНИЙ РЕЙТИНГ ПО РАЙОНАМ

places_with_district <- st_join(places, ortsteile["Name"])

ratings_by_district <- places_with_district |>
  st_drop_geometry() |>
  group_by(Name, type) |>
  summarise(
    avg_rating    = round(mean(rating, na.rm = TRUE), 2),
    total_reviews = sum(reviews_count, na.rm = TRUE),
    n_places      = n(),
    .groups = "drop"
  )

logistics_ratings <- ratings_by_district |>
  filter(type == "DHL Packstation") |>
  select(Name,
         logistics_avg_rating = avg_rating,
         logistics_reviews    = total_reviews,
         logistics_n          = n_places)

retail_ratings <- ratings_by_district |>
  filter(type == "Small retail") |>
  select(Name,
         retail_avg_rating = avg_rating,
         retail_reviews    = total_reviews,
         retail_n          = n_places)

ortsteile_ratings <- ortsteile |>
  left_join(logistics_ratings, by = "Name") |>
  left_join(retail_ratings, by = "Name")

# карта 5 СРЕДНИЙ РЕЙТИНГ ЛОГИСТИКИ ПО РАЙОНАМ
tmap_mode("view")

map6 <- tm_shape(ortsteile_ratings) +
  tm_polygons(
    fill = "logistics_avg_rating",
    fill.scale = tm_scale_continuous(
      values   = "brewer.rd_yl_gn", 
      limits   = c(1, 5),
      value.na = "grey80"
    ),
    fill.legend = tm_legend(title = "Avg. rating\nDHL Packstation"),
    col = "white", lwd = 0.5,
    id = "Name",
    popup.vars = c(
      "Avg. rating (logistics)" = "logistics_avg_rating",
      "Total reviews"           = "logistics_reviews",
      "N places"                = "logistics_n"
    )
  ) +
  tm_title("6. Average DHL Packstation rating by district")

map6

# Карта 6 СРЕДНИЙ РЕЙТИНГ РИТЕЙЛА ПО РАЙОНАМ

map7 <- tm_shape(ortsteile_ratings) +
  tm_polygons(
    fill = "retail_avg_rating",
    fill.scale = tm_scale_continuous(
      values   = "brewer.rd_yl_gn",
      limits   = c(1, 5),
      value.na = "grey80"
    ),
    fill.legend = tm_legend(title = "Avg. rating\nSmall retail"),
    col = "white", lwd = 0.5,
    id = "Name",
    popup.vars = c(
      "Avg. rating (retail)" = "retail_avg_rating",
      "Total reviews"        = "retail_reviews",
      "N places"             = "retail_n"
    )
  ) +
  tm_title("7. Average small retail rating by district")

map7

# КАРТА 8 — ТОЧКИ С РЕЙТИНГОМ


map8 <- tm_shape(places) +
  tm_dots(
    fill      = "rating",
    fill.scale = tm_scale_continuous(
      values = "brewer.rd_yl_gn",
      limits = c(1, 5)
    ),
    fill.legend = tm_legend(title = "Rating"),
    size = 0.3,
    id   = "name",
    popup.vars = c(
      "Name"          = "name",
      "Rating"        = "rating",
      "Reviews"       = "reviews_count",
      "Type"          = "type"
    )
  ) +
  tm_title("8. Individual place ratings (Google Places)")

map8


# СОХРАНЕНИЕ


tmap_save(map6, "plots/map6_logistics_ratings.html")
tmap_save(map7, "plots/map7_retail_ratings.html")
tmap_save(map8, "plots/map8_point_ratings.html")

cat("Карты 6, 7, 8 сохранены\n")