library(tidyverse)
library(sf)
library(googleway)

ortsteile <- read_sf("data/Ortsteile.json") |>
  st_transform(crs = 4326)

# КЛЮЧ

readRenviron(".env")
google_key <- Sys.getenv("GOOGLE_API_KEY")
cat("Длина ключа:", nchar(google_key), "символов\n")


# ЗАПРОС

get_places <- function(keyword, lat, lng, radius = 15000) {
  result <- google_places(
    search_string = keyword,
    location      = c(lat, lng),
    radius        = radius,
    key           = google_key,
    language      = "de"
  )
  Sys.sleep(2)
  result
}

# ЛЕЙПЦИГ

packstation <- get_places("DHL Packstation Leipzig", 51.3397, 12.3731)
cat("Status:", packstation$status, "\n")

cat("Запрашиваем Packstation...\n")
packstation <- get_places("DHL Packstation Leipzig", 51.3397, 12.3731)

cat("Запрашиваем Paketshop...\n")
paketshop <- get_places("Paketshop Leipzig", 51.3397, 12.3731)

cat("Запрашиваем малый ритейл север...\n")
retail_north <- get_places("Lebensmittel Laden Leipzig Nord", 51.3900, 12.3731)

cat("Запрашиваем малый ритейл юг...\n")
retail_south <- get_places("Lebensmittel Laden Leipzig Süd", 51.2900, 12.3731)


# ДАННЫЕ

extract_places <- function(result, type_label) {
  if (is.null(result$results) || nrow(result$results) == 0) {
    cat("Нет результатов для:", type_label, "\n")
    return(NULL)
  }
  
  tibble(
    name         = result$results$name,
    rating       = result$results$rating,
    reviews_count = result$results$user_ratings_total,
    lat          = result$results$geometry$location$lat,
    lng          = result$results$geometry$location$lng,
    type         = type_label
  )
}

places_data <- bind_rows(
  extract_places(packstation, "DHL Packstation"),
  extract_places(paketshop,   "Paketshop"),
  extract_places(retail_north, "Small retail"),
  extract_places(retail_south, "Small retail")
) |>
  distinct(lat, lng, .keep_all = TRUE) |>
  filter(!is.na(rating))

cat("Всего мест с рейтингом:", nrow(places_data), "\n")
print(places_data)


# СОХРАНЯЕМ И ПРИСОЕДИНЯЕМ

places_sf <- places_data |>
  st_as_sf(coords = c("lng", "lat"), crs = 4326)

st_write(places_sf, "data/google_places.geojson",
         delete_dsn = TRUE)

cat("Сохранено в data/google_places.geojson\n")

places_with_district <- st_join(places_sf, ortsteile["Name"])

ratings_by_district <- places_with_district |>
  st_drop_geometry() |>
  group_by(Name, type) |>
  summarise(
    avg_rating    = round(mean(rating, na.rm = TRUE), 2),
    total_reviews = sum(reviews_count, na.rm = TRUE),
    n_places      = n(),
    .groups = "drop"
  )

print(ratings_by_district)

#  ОТЗЫВЫ

all_place_ids <- c(
  packstation$results$place_id,
  paketshop$results$place_id,
  retail_north$results$place_id,
  retail_south$results$place_id
) |> unique()

cat("Всего уникальных мест:", length(all_place_ids), "\n")

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
  
  if (is.null(result$result$reviews)) {
    return(tibble(
      place_id      = place_id,
      name          = place_name,
      address       = place_address,
      rating        = place_rating,
      lat           = place_lat,
      lng           = place_lng,
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
    review_text   = reviews$text,
    review_rating = reviews$rating,
    review_time   = reviews$relative_time_description,
    review_author = reviews$author_name
  )
}

cat("Запрашиваем отзывы... это займёт около минуты\n")

all_reviews <- map_dfr(all_place_ids, get_reviews)

cat("Всего отзывов собрано:", nrow(all_reviews), "\n")
cat("Мест с отзывами:", n_distinct(all_reviews$place_id), "\n")


write_csv(all_reviews, "data/google_reviews.csv")

cat("Сохранено в data/google_reviews.csv\n")

all_reviews |>
  filter(!is.na(review_text)) |>
  select(name, rating, review_rating, review_text) |>
  head(10) |>
  print()