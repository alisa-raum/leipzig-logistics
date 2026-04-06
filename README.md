# Leipzig Logistics
### Mapping last-mile delivery infrastructure and retail inequalities in Leipzig

---

## Research question

The growth of e-commerce and platform-based delivery is reshaping 
urban space in ways that planning frameworks have yet to fully address. 
This project asks: **who gains and who loses when "convenience" 
infrastructures arrive?**

Using open data from multiple sources, I map the spatial distribution 
of parcel lockers, pickup points, and small-scale retail across 
Leipzig's 63 districts — and examine whether logistics infrastructure 
reinforces or disrupts existing socio-spatial inequalities.

Preliminary findings suggest that logistics density correlates 
moderately with land value (Spearman r = 0.52), but the relationship 
is non-linear: high-density working-class districts attract logistics 
infrastructure through demand volume, not prestige. Meanwhile, 
peripheral districts remain underserved by both logistics and retail.

This project accompanies a paper presented at the **Mobility conference, 
Vienna, 2025**.

---

## Data sources

| Dataset | Source | Coverage | Script |
|---|---|---|---|
| Parcel lockers, pickup points, retail, vacant shops | OpenStreetMap via Overpass API | Leipzig, 2024 | `01_osm_logistics.R` |
| DHL Packstation locations | DHL Location Finder API | Leipzig, 2024 | `02_dhl_api.R` |
| Place ratings and user reviews | Google Places API | Leipzig, 2024 | `03_google_places.R` |
| District boundaries (Ortsteile) | Stadtplan Leipzig / opendata.leipzig.de | 2024 | `02_logistic_inequality.R` |
| Population by district | Stadtplan Leipzig (Einwohner Jahreszahlen) | 2000–2024 | `02_logistic_inequality.R` |
| Land value by zone | Bodenrichtwerte 2024, Stadt Leipzig | 2024 | `02_logistic_inequality.R` |
---

## Scripts

| File | What it does |
|---|---|
| `01_osm_logistics.R` | Downloads logistics and retail points from OSM via Overpass API; basic point map |
| `02_logistic_inequality.R` | District-level analysis: counts by category, normalisation by population and area, land value correlation, maps 1–5 |
| `03_dhl_api.R` | Queries DHL Location Finder API for Packstation locations across Leipzig |
| `03_google_places.R` | Collects place ratings and user reviews via Google Places API across a 9-point grid |
| `04_combine_map.R` | Combines OSM and DHL data into a single unified point map |
| `05_ratings_map.R` | Maps 6–8: average ratings by district and individual point ratings from Google Places |
---

## Key findings

- Leipzig has **148 DHL Packstations** and over **136 additional pickup 
  points** documented in OSM — a dense logistics network concentrated 
  in central and gentrifying districts
- **113 vacant retail units** are recorded in OSM — nearly matching 
  the number of logistics points, suggesting a structural substitution 
  dynamic
- Land value correlates moderately with logistics density 
  (Spearman r = **0.52**) and retail density (r = **0.57**) — 
  infrastructure follows purchasing power, but not exclusively
- Outliers like Eutritzsch and Paunsdorf show high logistics density 
  despite low land value, driven by residential population density
- DHL Packstation ratings are uniformly high across districts (avg. 4.0–4.5), 
  with no clear spatial pattern — quality of logistics infrastructure 
  does not vary significantly by neighbourhood

---

## Maps (interactive HTML)

All maps are saved in `/plots` as interactive HTML files:

| File | Description |
|---|---|
| `map1_absolute.html` | Total number of lockers by district |
| `map2_per_1000.html` | Lockers per 1,000 inhabitants |
| `map3_per_km2.html` | Locker density per km² |
| `map4_index.html` | Logistics vs. retail index |
| `map5_land_value.html` | Land value by district (Bodenrichtwert 2024) |
| `map6_logistics_ratings.html` | Average DHL Packstation rating by district |
| `map7_retail_ratings.html` | Average small retail rating by district |
| `map8_point_ratings.html` | Individual place ratings (Google Places) |

---

## Data limitations

**OpenStreetMap** data quality varies by district. OSM coverage is 
generally strong in central Leipzig but may underrepresent peripheral 
areas. Vacant retail units in particular are likely undercounted — 
OSM contributors do not systematically track closures.

**Other carriers** (Hermes, Amazon Locker, DPD, GLS) do not provide 
public APIs. Their locators are web-only tools without documented 
endpoints. Scraping would violate their Terms of Service and compromise 
reproducibility. These carriers appear in the dataset only through 
OSM-contributed data.

**Google Places API** returns a maximum of 20 results per query. 
Coverage of small retail is partial — the search term 
`"Lebensmittel Laden"` captures only a subset of food retail. 
A systematic coverage would require a broader set of search terms 
and queries.

A more complete picture would require official data-sharing agreements 
with carriers, or a systematic OSM mapping campaign — both possible 
directions for future work.

---

## Reproducibility

All data collection scripts are documented and reproducible. 
API keys (DHL, Google) are stored locally in `.env` and excluded 
from the repository via `.gitignore`.

To reproduce:
1. Clone the repository
2. Add your API keys to `.env`
3. Run scripts in order: `01_osm_logistics` → `03_dhl_api` → `03_google_places` → `02_logistic_inequality` → `04_combine_map` → `05_ratings_map`
R version: 4.5.3. Key packages: `tidyverse`, `sf`, `tmap`, `httr2`, 
`osmdata`, `googleway`.

---

## About

This is a learning project in R and open data analysis,  
developed as part of building a computational social science portfolio.  
Conducted in Leipzig, 2025–2026.

Part of a broader research interest in platform economies, urban 
logistics, and spatial justice.

Feedback and collaboration welcome.