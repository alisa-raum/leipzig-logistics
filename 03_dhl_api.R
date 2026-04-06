library(tidyverse)
library(sf)
library(httr2)

readRenviron(".env")
api_key <- Sys.getenv("DHL_API_KEY")
cat("Длина ключа:", nchar(api_key), "символов\n")

get_dhl_locations <- function(lat, lng, radius = 25000) {
  resp <- request("https://api.dhl.com/location-finder/v1/find-by-geo") |>
    req_headers(
      "DHL-API-Key" = api_key,
      "Accept"      = "application/json"
    ) |>
    req_url_query(
      latitude    = lat,
      longitude   = lng,
      radius      = radius,
      limit       = 50,
      countryCode = "DE",
      locationType = "locker"
    ) |>
    req_perform()
  resp_body_json(resp)
}

points <- tibble(
  name = c("центр", "запад", "восток"),
  lat  = c(51.3397, 51.3397, 51.3397),
  lng  = c(12.3731, 12.2800, 12.4600)
)

all_results <- map2(points$lat, points$lng, function(lat, lng) {
  cat("Запрос из точки:", lat, lng, "\n")
  Sys.sleep(5)
  get_dhl_locations(lat, lng)
})

dhl_points <- map_dfr(all_results, function(result) {
  map_dfr(result$locations, function(loc) {
    tibble(
      name = if (!is.null(loc$name)) loc$name else 
        paste("DHL Packstation", loc$place$address$streetAddress %||% ""),
      address  = paste(
        loc$place$address$streetAddress %||% "",
        loc$place$address$postalCode %||% "",
        loc$place$address$addressLocality %||% ""
      ),
      lat      = loc$place$geo$latitude,
      lng      = loc$place$geo$longitude,
      operator = "DHL"
    )
  })
})

dhl_points <- dhl_points |>
  distinct(lat, lng, .keep_all = TRUE)

cat("Уникальных DHL точек:", nrow(dhl_points), "\n")

dhl_sf <- dhl_points |>
  st_as_sf(coords = c("lng", "lat"), crs = 4326)

st_write(dhl_sf, "data/dhl_packstations.geojson",
         delete_dsn = TRUE)

cat("Сохранено!\n")
