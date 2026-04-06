# leipzig-logistics
Mapping last-mile delivery infrastructure and retail inequalities in Leipzig using open data

## Data limitations and reproducibility

This project uses **OpenStreetMap** as its primary data source for 
logistics infrastructure. OSM data is open, citable, and fully 
reproducible — all queries are documented in the scripts.

**DHL Packstation locations** are additionally sourced via the official 
DHL Location Finder API (api.dhl.com/location-finder/v1), which provides 
structured GeoJSON with coordinates, location type, and opening hours. 
A free API key is available at developer.dhl.com.

**Other carriers** (Hermes, Amazon Locker, DPD, GLS) do not provide 
public APIs for location data. Their official locators are web-only tools 
without documented endpoints. Scraping these sources would violate their 
Terms of Service and compromise the reproducibility of the dataset. 
As a result, these carriers are represented in this project only through 
OSM-contributed data, which may be incomplete.

This is a known limitation. A more complete picture of last-mile 
logistics infrastructure would require either official data-sharing 
agreements with carriers, or a systematic OSM mapping campaign 
for Leipzig — both of which are possible directions for future work.