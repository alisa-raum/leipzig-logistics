library(tidyverse)
library(sf)
library(tmap)
library(httr2)
library(googleway)

sf_use_s2(FALSE) 

# ДАННЫЕ БЕРЛИН

berlin_points <- read_sf("data/berlin_all.geojson") |>
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
  filter(category != "Other") |>
  select(name, category, operator, geometry)

cat("Берлин — всего точек:", nrow(berlin_points), "\n")


# DHL ДАННЫЕ ДЛЯ БЕРЛИНА

readRenviron(".env")
api_key <- Sys.getenv("DHL_API_KEY")

berlin_grid <- tibble(
  lat = c(52.57, 52.57, 52.57,
          52.52, 52.52, 52.52,
          52.47, 52.47, 52.47),
  lng = c(13.33, 13.41, 13.49,
          13.33, 13.41, 13.49,
          13.33, 13.41, 13.49)
)

get_dhl_locations <- function(lat, lng, radius = 25000) {
  resp <- request("https://api.dhl.com/location-finder/v1/find-by-geo") |>
    req_headers("DHL-API-Key" = api_key, "Accept" = "application/json") |>
    req_url_query(latitude = lat, longitude = lng, radius = radius,
                  limit = 50, countryCode = "DE", locationType = "locker") |>
    req_perform()
  resp_body_json(resp)
}

cat("Запрашиваем DHL по Берлину...\n")
berlin_dhl_results <- map2(berlin_grid$lat, berlin_grid$lng, function(lat, lng) {
  cat("Точка:", lat, lng, "\n")
  Sys.sleep(5)
  get_dhl_locations(lat, lng)
})

berlin_dhl_points <- map_dfr(berlin_dhl_results, function(result) {
  map_dfr(result$locations, function(loc) {
    tibble(
      name     = loc$name %||% NA,
      lat      = loc$place$geo$latitude,
      lng      = loc$place$geo$longitude,
      category = "Locker / Pickup",
      operator = "DHL"
    )
  })
}) |> distinct(lat, lng, .keep_all = TRUE)

cat("DHL точек в Берлине:", nrow(berlin_dhl_points), "\n")

# OSM + DHL
berlin_dhl_sf <- berlin_dhl_points |>
  st_as_sf(coords = c("lng", "lat"), crs = 4326) |>
  select(name, category, operator, geometry)

berlin_points <- bind_rows(berlin_points, berlin_dhl_sf) |>
  distinct(geometry, .keep_all = TRUE)

cat("Всего точек после объединения:", nrow(berlin_points), "\n")

# ГРАНИЦЫ РАЙОНОВ

berlin_bezirke <- read_sf("data/berlin_bezirke.geojson") |>
  st_make_valid() |>
  st_transform(crs = 4326)

cat("Районов Берлина:", nrow(berlin_bezirke), "\n")

# СЧИТАЕМ ПО РАЙОНАМ

points_with_bezirk <- st_join(berlin_points, berlin_bezirke["Gemeinde_name"])

district_counts_berlin <- points_with_bezirk |>
  st_drop_geometry() |>
  count(Gemeinde_name, category) |>
  pivot_wider(
    names_from  = category,
    values_from = n,
    values_fill = 0
  )

# НАСЕЛЕНИЕ БЕРЛИНА ПО BEZIRKEN

berlin_pop_raw <- read_csv2("data/berlin_population.csv")

# Агрегация
berlin_population <- berlin_pop_raw |>
  group_by(BEZ) |>
  summarise(population = sum(E_E, na.rm = TRUE)) |>

    mutate(Gemeinde_name = case_when(
    BEZ == "01" ~ "Mitte",
    BEZ == "02" ~ "Friedrichshain-Kreuzberg",
    BEZ == "03" ~ "Pankow",
    BEZ == "04" ~ "Charlottenburg-Wilmersdorf",
    BEZ == "05" ~ "Spandau",
    BEZ == "06" ~ "Steglitz-Zehlendorf",
    BEZ == "07" ~ "Tempelhof-Schöneberg",
    BEZ == "08" ~ "Neukölln",
    BEZ == "09" ~ "Treptow-Köpenick",
    BEZ == "10" ~ "Marzahn-Hellersdorf",
    BEZ == "11" ~ "Lichtenberg",
    BEZ == "12" ~ "Reinickendorf",
    TRUE ~ NA_character_
  ))

cat("Районов с данными о населении:", nrow(berlin_population), "\n")
print(berlin_population |> select(Gemeinde_name, population))

# BODENRICHTWERTE БЕРЛИНА

berlin_brw <- read_csv("data/berlin_brw.csv") |>
  filter(!is.na(brw)) |>
  group_by(bezirk) |>
  summarise(
    brw_mean   = mean(brw, na.rm = TRUE),
    brw_median = median(brw, na.rm = TRUE),
    brw_max    = max(brw, na.rm = TRUE)
  ) |>
  rename(Gemeinde_name = bezirk)

cat("Районов с BRW:", nrow(berlin_brw), "\n")
print(berlin_brw)

# ПРИСОЕДИНЯЕМ ВСЁ ВМЕСТЕ

berlin_stats <- berlin_bezirke |>
  left_join(district_counts_berlin, by = "Gemeinde_name") |>
  left_join(berlin_population |> select(Gemeinde_name, population),
            by = "Gemeinde_name") |>
  left_join(berlin_brw, by = "Gemeinde_name") |>
  mutate(across(where(is.numeric), ~replace_na(., 0))) |>
  mutate(
    area_km2               = as.numeric(st_area(geometry)) / 1000000,
    locker_per_km2         = `Locker / Pickup` / area_km2,
    locker_per_1000        = (`Locker / Pickup` / population) * 1000,
    logistics_retail_ratio = `Locker / Pickup` / (`Small-scale retail` + 1)
  )

cat("Готово. Районов:", nrow(berlin_stats), "\n")

# КОРРЕЛЯЦИЯ: BRW vs логистика

corr_berlin <- berlin_stats |>
  st_drop_geometry() |>
  filter(population > 0, brw_median > 0, `Locker / Pickup` > 0) |>
  select(
    Name                 = Gemeinde_name,
    brw_median,
    locker_per_km2,
    locker_per_1000,
    retail               = `Small-scale retail`,
    logistics_retail_ratio
  )

cor_berlin_brw <- cor(
  corr_berlin$brw_median,
  corr_berlin$`locker_per_km2`,
  method = "spearman"
)

cor_berlin_retail <- cor(
  corr_berlin$brw_median,
  corr_berlin$retail,
  method = "spearman"
)

cat("Берлин — корреляция BRW vs locker/km²:", round(cor_berlin_brw, 3), "\n")
cat("Берлин — корреляция BRW vs retail:", round(cor_berlin_retail, 3), "\n")

# Scatter plot
ggplot(corr_berlin, aes(x = brw_median, y = locker_per_km2)) +
  geom_point(size = 3, color = "#E63946", alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE,
              color = "black", linewidth = 0.8) +
  geom_text(aes(label = Name), size = 2.5,
            vjust = -0.8, check_overlap = TRUE) +
  labs(
    title    = "Land value vs. logistics density — Berlin",
    subtitle = "Berlin Bezirke, 2025–2026",
    x        = "Median land value (Bodenrichtwert), €/m²",
    y        = "Parcel lockers per km²",
    caption  = "Sources: OSM, DHL API, Senatsverwaltung Berlin (BRW 2026)"
  ) +
  theme_minimal(base_size = 13)

ggsave("plots/berlin/correlation_berlin_brw.png",
       width = 10, height = 7, dpi = 150)


# КАРТА 1 — АБСОЛЮТНЫЕ ЧИСЛА

tmap_mode("view")

map_berlin_1 <- tm_shape(berlin_stats) +
  tm_polygons(
    fill = "Locker / Pickup",
    fill.scale = tm_scale_continuous(values = "brewer.yl_or_rd"),
    fill.legend = tm_legend(title = "Lockers (abs.)"),
    col = "white", lwd = 0.5,
    id = "Gemeinde_name",
    popup.vars = c(
      "Locker / Pickup"    = "Locker / Pickup",
      "Small-scale retail" = "Small-scale retail",
      "Vacant"             = "Vacant",
      "Per km²"            = "locker_per_km2"
    )
  ) +
  tm_title("Berlin — Locker / Pickup points by Bezirk")

map_berlin_1


# КАРТА 2 — ПЛОТНОСТЬ НА КМ²


map_berlin_2 <- tm_shape(berlin_stats) +
  tm_polygons(
    fill = "locker_per_km2",
    fill.scale = tm_scale_continuous(values = "brewer.yl_or_rd"),
    fill.legend = tm_legend(title = "Lockers per km²"),
    col = "white", lwd = 0.5,
    id = "Gemeinde_name",
    popup.vars = c(
      "Locker / Pickup" = "Locker / Pickup",
      "Area km²"        = "area_km2",
      "Per km²"         = "locker_per_km2"
    )
  ) +
  tm_title("Berlin — Locker density per km²")

map_berlin_2

# КАРТА 2б — НА 1000 ЖИТЕЛЕЙ
map_berlin_2b <- tm_shape(berlin_stats) +
  tm_polygons(
    fill = "locker_per_1000",
    fill.scale = tm_scale_continuous(values = "brewer.yl_or_rd"),
    fill.legend = tm_legend(title = "Lockers per\n1,000 inh."),
    col = "white", lwd = 0.5,
    id = "Gemeinde_name",
    popup.vars = c(
      "Population"         = "population",
      "Locker / Pickup"    = "Locker / Pickup",
      "Per 1,000 inh."     = "locker_per_1000"
    )
  ) +
  tm_title("Berlin — Lockers per 1,000 inhabitants")

map_berlin_2b


# КАРТА 3 — ИНДЕКС ЛОГИСТИКА vs РИТЕЙЛ

map_berlin_3 <- tm_shape(berlin_stats) +
  tm_polygons(
    fill = "logistics_retail_ratio",
    fill.scale = tm_scale_continuous(
      values   = "brewer.rd_bu",
      midpoint = 1,
      value.na = "grey80"
    ),
    fill.legend = tm_legend(title = "Logistics / Retail"),
    col = "white", lwd = 0.5,
    id = "Gemeinde_name",
    popup.vars = c(
      "Locker / Pickup"    = "Locker / Pickup",
      "Small-scale retail" = "Small-scale retail",
      "Index"              = "logistics_retail_ratio"
    )
  ) +
  tm_title("Berlin — Logistics vs retail index")

map_berlin_3

# КАРТА — СТОИМОСТЬ ЗЕМЛИ БЕРЛИН
map_berlin_brw <- tm_shape(berlin_stats) +
  tm_polygons(
    fill = "brw_median",
    fill.scale = tm_scale_continuous(
      values   = "brewer.yl_gn_bu",
      value.na = "grey80"
    ),
    fill.legend = tm_legend(title = "Land value\n€/m² (median)"),
    col = "white", lwd = 0.5,
    id = "Gemeinde_name",
    popup.vars = c(
      "Land value median €/m²" = "brw_median",
      "Land value mean €/m²"   = "brw_mean",
      "Locker / Pickup"        = "Locker / Pickup",
      "Small-scale retail"     = "Small-scale retail"
    )
  ) +
  tm_title("Berlin — Land value by Bezirk (Bodenrichtwert 2026)")

map_berlin_brw


# СОХРАНЕНИЕ

dir.create("plots/berlin", showWarnings = FALSE, recursive = TRUE)

tmap_save(map_berlin_1, "plots/berlin/berlin_map1_absolute.html")
tmap_save(map_berlin_2, "plots/berlin/berlin_map2_per_km2.html")
tmap_save(map_berlin_3, "plots/berlin/berlin_map3_index.html")
tmap_save(map_berlin_2b, "plots/berlin/berlin_map2b_per_1000.html")
tmap_save(map_berlin_brw, "plots/berlin/berlin_map_land_value.html")


cat("Берлинские карты сохранены\n")


# GOOGLE PLACES — БЕРЛИН

readRenviron(".env")
google_key <- Sys.getenv("GOOGLE_API_KEY")

berlin_google_grid <- tibble(
  lat = c(52.57, 52.57, 52.57,
          52.52, 52.52, 52.52,
          52.47, 52.47, 52.47),
  lng = c(13.33, 13.41, 13.49,
          13.33, 13.41, 13.49,
          13.33, 13.41, 13.49)
)

get_all_places_berlin <- function(keyword, type_label) {
  map_dfr(1:nrow(berlin_google_grid), function(i) {
    cat("Запрос", i, "из", nrow(berlin_google_grid), "\n")
    Sys.sleep(2)
    result <- google_places(
      search_string = keyword,
      location      = c(berlin_google_grid$lat[i],
                        berlin_google_grid$lng[i]),
      radius        = 8000,
      key           = google_key,
      language      = "de"
    )
    if (result$status != "OK" || nrow(result$results) == 0) return(tibble())
    tibble(
      name          = result$results$name,
      place_id      = result$results$place_id,
      rating        = result$results$rating,
      reviews_count = result$results$user_ratings_total,
      lat           = result$results$geometry$location$lat,
      lng           = result$results$geometry$location$lng,
      type          = type_label
    )
  })
}

cat("Собираем DHL Packstation по Берлину...\n")
berlin_packstation <- get_all_places_berlin(
  "DHL Packstation Berlin", "DHL Packstation"
)

cat("Собираем малый ритейл по Берлину...\n")
berlin_retail_places <- get_all_places_berlin(
  "Lebensmittel Laden Berlin", "Small retail"
)

berlin_places_full <- bind_rows(berlin_packstation, berlin_retail_places) |>
  filter(!is.na(rating)) |>
  distinct(place_id, .keep_all = TRUE)

cat("Итого мест:", nrow(berlin_places_full), "\n")


# ОТЗЫВЫ


get_reviews <- function(place_id) {
  Sys.sleep(0.5)
  result <- google_place_details(
    place_id = place_id,
    key      = google_key,
    language = "de"
  )
  if (result$status != "OK") return(tibble())
  place_type <- berlin_places_full$type[
    berlin_places_full$place_id == place_id
  ][1]
  if (is.null(result$result$reviews)) {
    return(tibble(
      place_id      = place_id,
      name          = result$result$name,
      rating        = result$result$rating %||% NA,
      lat           = result$result$geometry$location$lat,
      lng           = result$result$geometry$location$lng,
      type          = place_type,
      review_text   = NA,
      review_rating = NA,
      review_time   = NA,
      review_author = NA
    ))
  }
  reviews <- result$result$reviews
  tibble(
    place_id      = place_id,
    name          = result$result$name,
    rating        = result$result$rating %||% NA,
    lat           = result$result$geometry$location$lat,
    lng           = result$result$geometry$location$lng,
    type          = place_type,
    review_text   = reviews$text,
    review_rating = reviews$rating,
    review_time   = reviews$relative_time_description,
    review_author = reviews$author_name
  )
}

cat("Собираем отзывы...\n")
berlin_reviews <- map_dfr(berlin_places_full$place_id, get_reviews)

cat("Отзывов собрано:", nrow(berlin_reviews), "\n")

write_csv(berlin_reviews, "data/berlin_google_reviews.csv")
cat("Сохранено в data/berlin_google_reviews.csv\n")


# КАРТЫ РЕЙТИНГОВ БЕРЛИН


berlin_places_sf <- berlin_places_full |>
  st_as_sf(coords = c("lng", "lat"), crs = 4326)

berlin_places_with_bezirk <- st_join(
  berlin_places_sf, berlin_bezirke["Gemeinde_name"]
)

berlin_ratings_by_district <- berlin_places_with_bezirk |>
  st_drop_geometry() |>
  group_by(Gemeinde_name, type) |>
  summarise(
    avg_rating    = round(mean(rating, na.rm = TRUE), 2),
    total_reviews = sum(reviews_count, na.rm = TRUE),
    n_places      = n(),
    .groups = "drop"
  )

berlin_logistics_ratings <- berlin_ratings_by_district |>
  filter(type == "DHL Packstation") |>
  select(Gemeinde_name,
         logistics_avg_rating = avg_rating,
         logistics_reviews    = total_reviews,
         logistics_n          = n_places)

berlin_retail_ratings <- berlin_ratings_by_district |>
  filter(type == "Small retail") |>
  select(Gemeinde_name,
         retail_avg_rating = avg_rating,
         retail_reviews    = total_reviews,
         retail_n          = n_places)

berlin_bezirke_ratings <- berlin_bezirke |>
  left_join(berlin_logistics_ratings, by = "Gemeinde_name") |>
  left_join(berlin_retail_ratings,    by = "Gemeinde_name")

# КАРТА 6 — рейтинг логистики по районам
map_berlin_ratings_log <- tm_shape(berlin_bezirke_ratings) +
  tm_polygons(
    fill = "logistics_avg_rating",
    fill.scale = tm_scale_continuous(
      values   = "brewer.rd_yl_gn",
      limits   = c(1, 5),
      value.na = "grey80"
    ),
    fill.legend = tm_legend(title = "Avg. rating\nDHL Packstation"),
    col = "white", lwd = 0.5,
    id = "Gemeinde_name",
    popup.vars = c(
      "Avg. rating" = "logistics_avg_rating",
      "Reviews"     = "logistics_reviews",
      "N places"    = "logistics_n"
    )
  ) +
  tm_title("Berlin — Average DHL Packstation rating by Bezirk")

map_berlin_ratings_log

# КАРТА 7 — рейтинг ритейла по районам
map_berlin_ratings_ret <- tm_shape(berlin_bezirke_ratings) +
  tm_polygons(
    fill = "retail_avg_rating",
    fill.scale = tm_scale_continuous(
      values   = "brewer.rd_yl_gn",
      limits   = c(1, 5),
      value.na = "grey80"
    ),
    fill.legend = tm_legend(title = "Avg. rating\nSmall retail"),
    col = "white", lwd = 0.5,
    id = "Gemeinde_name",
    popup.vars = c(
      "Avg. rating" = "retail_avg_rating",
      "Reviews"     = "retail_reviews",
      "N places"    = "retail_n"
    )
  ) +
  tm_title("Berlin — Average small retail rating by Bezirk")

map_berlin_ratings_ret

# КАРТА 8 — точки с рейтингом
map_berlin_points <- tm_shape(berlin_places_sf) +
  tm_dots(
    fill = "rating",
    fill.scale = tm_scale_continuous(
      values = "brewer.rd_yl_gn",
      limits = c(1, 5)
    ),
    fill.legend = tm_legend(title = "Rating"),
    size = 0.15,
    id   = "name",
    popup.vars = c(
      "Name"    = "name",
      "Rating"  = "rating",
      "Reviews" = "reviews_count",
      "Type"    = "type"
    )
  ) +
  tm_title("Berlin — Individual place ratings (Google Places)")

map_berlin_points

# СОХРАНЕНИЕ
tmap_save(map_berlin_ratings_log, "plots/berlin/berlin_map_ratings_logistics.html")
tmap_save(map_berlin_ratings_ret, "plots/berlin/berlin_map_ratings_retail.html")
tmap_save(map_berlin_points,      "plots/berlin/berlin_map_point_ratings.html")

cat("Карты рейтингов Берлина сохранены\n")


# СРАВНИТЕЛЬНЫЙ ГРАФИК ЛЕЙПЦИГ vs БЕРЛИН


berlin_corr <- berlin_stats |>
  st_drop_geometry() |>
  filter(`Locker / Pickup` > 0) |>
  select(Name = Gemeinde_name, locker_per_km2) |>
  mutate(city = "Berlin")

# Лейпцигские данные
leipzig_points <- read_sf("data/leipzig_all.geojson") |>
  mutate(category = case_when(
    amenity %in% c("parcel_locker", "parcel_pickup") ~ "Locker / Pickup",
    brand %in% c("DHL Packstation", "Hermes PaketShop") ~ "Locker / Pickup",
    shop == "parcel"                                  ~ "Locker / Pickup",
    TRUE ~ "Other"
  )) |>
  filter(category == "Locker / Pickup")

leipzig_ortsteile <- read_sf("data/Ortsteile.json") |>
  st_transform(crs = 4326)

leipzig_counts <- st_join(leipzig_points, leipzig_ortsteile["Name"]) |>
  st_drop_geometry() |>
  count(Name) |>
  rename(lockers = n)

leipzig_corr <- leipzig_ortsteile |>
  left_join(leipzig_counts, by = "Name") |>
  mutate(
    lockers    = replace_na(lockers, 0),
    area_km2   = as.numeric(st_area(geometry)) / 1000000,
    locker_per_km2 = lockers / area_km2
  ) |>
  st_drop_geometry() |>
  filter(lockers > 0) |>
  select(Name, locker_per_km2) |>
  mutate(city = "Leipzig")

combined_corr <- bind_rows(leipzig_corr, berlin_corr)

ggplot(combined_corr, aes(x = city, y = locker_per_km2, fill = city)) +
  geom_boxplot(alpha = 0.7, outlier.shape = 16) +
  geom_jitter(width = 0.15, size = 2, alpha = 0.5) +
  scale_fill_manual(values = c("Leipzig" = "#457B9D",
                               "Berlin"  = "#E63946")) +
  labs(
    title    = "Parcel locker density: Leipzig vs Berlin",
    subtitle = "Distribution across districts",
    x        = NULL,
    y        = "Lockers per km²",
    caption  = "Sources: OSM, DHL API"
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "none")

ggsave("plots/berlin/comparison_leipzig_berlin.png",
       width = 8, height = 6, dpi = 150)
