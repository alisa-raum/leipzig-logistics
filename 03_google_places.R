library(tidyverse)
library(sf)
library(googleway)

# ЗАГРУЗКА


ortsteile <- read_sf("data/Ortsteile.json") |>
  st_transform(crs = 4326)

readRenviron(".env")
google_key <- Sys.getenv("GOOGLE_API_KEY")
cat("Длина ключа:", nchar(google_key), "символов\n")

# СЕТКА ТОЧЕК ПО ВСЕМУ ЛЕЙПЦИГУ

grid_points <- tibble(
  lat = c(51.39, 51.39, 51.39,
          51.34, 51.34, 51.34,
          51.29, 51.29, 51.29),
  lng = c(12.28, 12.37, 12.47,
          12.28, 12.37, 12.47,
          12.28, 12.37, 12.47)
)

# СБОР ПО СЕТКЕ

get_all_places <- function(keyword, type_label) {
  map_dfr(1:nrow(grid_points), function(i) {
    cat("Запрос", i, "из", nrow(grid_points),
        "— точка", grid_points$lat[i], grid_points$lng[i], "\n")
    Sys.sleep(2)
    
    result <- google_places(
      search_string = keyword,
      location      = c(grid_points$lat[i], grid_points$lng[i]),
      radius        = 8000,
      key           = google_key,
      language      = "de"
    )
    
    if (result$status != "OK" || nrow(result$results) == 0) {
      cat("  Нет результатов\n")
      return(tibble())
    }
    
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


# ВСЕ МЕСТА


cat("Собираем DHL Packstation по всему городу...\n")
all_packstation <- get_all_places("DHL Packstation Leipzig", "DHL Packstation")

cat("Собираем Paketshop по всему городу...\n")
all_paketshop <- get_all_places("Paketshop Leipzig", "Paketshop")

cat("Собираем малый ритейл по всему городу...\n")
all_retail <- get_all_places("Lebensmittel Laden Leipzig", "Small retail")

places_full <- bind_rows(all_packstation, all_paketshop, all_retail) |>
  filter(!is.na(rating)) |>
  distinct(place_id, .keep_all = TRUE)  # дедупликация по place_id

cat("Итого уникальных мест:", nrow(places_full), "\n")

# ОТЗЫВЫ ДЛЯ ВСЕХ МЕСТ

get_reviews <- function(place_id) {
  Sys.sleep(0.5)
  
  result <- google_place_details(
    place_id = place_id,
    key      = google_key,
    language = "de"
  )
  
  if (result$status != "OK") return(tibble())
  
  place_name    <- result$result$name
  place_address <- result$result$formatted_address %||% NA
  place_rating  <- result$result$rating %||% NA
  place_lat     <- result$result$geometry$location$lat
  place_lng     <- result$result$geometry$location$lng
  place_type    <- places_full$type[places_full$place_id == place_id][1]
  
  if (is.null(result$result$reviews)) {
    return(tibble(
      place_id      = place_id,
      name          = place_name,
      address       = place_address,
      rating        = place_rating,
      lat           = place_lat,
      lng           = place_lng,
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
    name          = place_name,
    address       = place_address,
    rating        = place_rating,
    lat           = place_lat,
    lng           = place_lng,
    type          = place_type,
    review_text   = reviews$text,
    review_rating = reviews$rating,
    review_time   = reviews$relative_time_description,
    review_author = reviews$author_name
  )
}

cat("Собираем отзывы для", nrow(places_full), "мест...\n")
cat("Это займёт около", round(nrow(places_full) * 0.5 / 60, 1), "минут\n")

all_reviews <- map_dfr(places_full$place_id, get_reviews)

cat("Всего отзывов:", nrow(all_reviews), "\n")
cat("Мест с отзывами:", n_distinct(all_reviews$place_id), "\n")

# СОХРАНИТЬ

places_sf <- places_full |>
  st_as_sf(coords = c("lng", "lat"), crs = 4326)

st_write(places_sf, "data/google_places_full.geojson",
         delete_dsn = TRUE)

write_csv(all_reviews, "data/google_reviews.csv")

cat("Сохранено:\n")
cat("  data/google_places_full.geojson —", nrow(places_full), "мест\n")
cat("  data/google_reviews.csv —", nrow(all_reviews), "отзывов\n")

all_reviews |>
  filter(!is.na(review_text)) |>
  count(type)