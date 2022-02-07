#### Preamble ####
# Purpose: Read ward boundaries and energy consumption data from opendatatoronto.
#          Use osm to geocode buildings and find which wards they are in.
# Author: William Gerecke
# Email: wlgfour@gmail.com
# Date: 1/26/2022
# Prerequisites: An older version required a Google Maps API key, but osm allows
#                free API calls so the only prerequisites are the packages
#                loaded below.
# Notes: This script will geocode 2509 addresses at 1 API call per second.
#        This means that the script will take at least 43 minutes to run.

library(sf)
library(tidygeocoder)
library(dplyr)
library(tidyverse)
library(opendatatoronto)
library(janitor)
library(stringr)

# download and unzip shapefile from opendatatoronto
shp_url <- "https://ckan0.cf.opendata.inter.prod-toronto.ca/download_resource/586930e7-4178-42a1-a159-ce1da526ad6c"
shp_zip <- tempfile()  #"data/25-ward-model-december-2018-wgs84-latitude-longitude-1.zip"

download.file(shp_url, shp_zip, mode='wb')
unzip(shp_zip, exdir="./inputs/data/wards_dir")
unlink(shp_zip)

# read the data file
shp_file <- "inputs/data/wards_dir/WARD_WGS84.shp"
wards <- st_read(shp_file)
ward_tbl <- wards %>%
  st_drop_geometry()
save(ward_tbl, file='outputs/ward_tbl.RData')

# plot the map
ggplot(wards) +
  geom_sf(aes(fill=X))

# function to clean columns
col_names <- c("Operation Name", "Operation Type", "Address", "City",
               "Postal Code", "Total Floor Area", "Unit", "Avg hrs/wk",
               "Annual Flow (Mega Litres)", "Electricity Quantity",
               "Electricity Unit", "Natural Gas Quantity", "Natural Gas Unit",
               "GHG Emissions (Kg)")

clean_cols <- function(energy_cons, y=NA) {
  # remove extra columns and rename remaining columns
  cleaned <- energy_cons[, c(1:13, 32)] %>%
    slice(9:n()) %>%
    setNames(col_names) %>%
    clean_names() %>%
    mutate(year=y)
}


# get building energy consumption from opendartatoronto
package <- show_package("0600cad8-d024-483b-a9a8-ecfc3e32e375") %>%
  list_package_resources()

pack_2011_2014 <- package %>%
  filter(name == "annual-energy-consumption-data-2011-2014") %>%
  get_resource()

p11 <- pack_2011_2014[[1]] %>% clean_cols(y=2011)
p12 <- pack_2011_2014[[2]] %>% clean_cols(y=2012)
p13 <- pack_2011_2014[[3]] %>% clean_cols(y=2013)
p14 <- pack_2011_2014[[4]] %>% clean_cols(y=2014)

p15 <- package %>%
  filter(name == "annual-energy-consumption-data-2015") %>%
  get_resource() %>%
  clean_cols(y=2015)

p16 <- package %>%
  filter(name == "annual-energy-consumption-data-2016") %>%
  get_resource() %>%
  clean_cols(y=2016)

p17 <- package %>%
  filter(name == "annual-energy-consumption-data-2017") %>%
  get_resource() %>%
  clean_cols(y=2017)

p18 <- package %>%
  filter(name == "annual-energy-consumption-data-2018") %>%
  get_resource() %>%
  clean_cols(y=2018)

# combine dataframes
cleaned <- rbind(p11, p12, p13, p14, p15, p16, p17, p18) %>%
  transform(ghg_emissions_kg=as.numeric(ghg_emissions_kg))

# make sure all postal codes have a space
pc <- gsub('[ ]', '', cleaned$postal_code)
lhs <- substr(pc, 1, 3)
rhs <- substr(pc, 4, 6)
cleaned$postal_code <- paste(lhs, rhs, sep=" ")
addresses <- unique(cleaned[,c('city', 'postal_code', 'address')]) %>%
  mutate(country='Canada')

# ==============================================================================
# geocode addresses using zip code, city, and country
#latlon <- addresses %>%
#  geocode(street=address, city=city, postalcode=postal_code, country=country, method='osm',
#      lat = latitude , long = longitude)
addresses$address_snth <- paste(addresses$address, addresses$city, sep=', ')
latlon <- addresses %>%
  geocode(address=address_snth, method='osm',
          lat = latitude , long = longitude)
# ==============================================================================

# merge postal code coordinates with building data
geocoded <- merge(cleaned, latlon, by=c('address', 'postal_code', 'city'))
sum(is.na(geocoded$latitude))
view(latlon[is.na(latlon$latitude),])

raw_geocoded <- geocoded
save(raw_geocoded, file='outputs/raw_geocoded.RData')

# plot the geocoded points on the toronto wards
ggplot(wards) +
  geom_sf(aes(fill=X)) +
  geom_point(data=geocoded, aes(x=longitude, y=latitude)) +
  labs(x = "Longitude", y = "Latitude")

# label each row with it's ward
pnts_sf <- geocoded %>%
  drop_na(latitude, longitude) %>%
  st_as_sf(coords=c('longitude', 'latitude'), crs=st_crs(wards), remove=FALSE)
ward_labelled <- pnts_sf %>%
  mutate(
    intersection = as.integer(st_intersects(geometry, wards)),
    ward = if_else(is.na(intersection), '', wards$AREA_NAME[intersection])
  )

# convert units, subsample columns, drop na (non-toronto or bad data)
raw <- ward_labelled %>%
  st_drop_geometry() %>%
  mutate(
    floor_area_sf = case_when(
      unit ==  'Square meters' ~ as.numeric(total_floor_area) * 10.7639,
      unit ==  'Square feet' ~ as.numeric(total_floor_area) * 1,
      TRUE ~ as.numeric(NA)
    ),
    flow_ml = as.numeric(annual_flow_mega_litres),
    electricity_wh = case_when(
      electricity_unit ==  'kWh' ~ as.numeric(electricity_quantity) * 1000,
      TRUE ~ 0
    ), gas_cm = case_when(
      unit ==  'Cubic Meter' ~ as.numeric(total_floor_area) * 1,
      TRUE ~ 0
    ),
  ) %>%
  select(operation_name, ward, avg_hrs_wk, floor_area_sf, flow_ml,
         electricity_wh, gas_cm, ghg_emissions_kg, latitude, longitude, year)

cleaned_geocoded <- raw %>%
  na_if("") %>%
  drop_na()

ggplot(wards) +
  geom_sf(aes(), fill='lightblue', alpha=0.5) +
  geom_point(data=cleaned_geocoded, aes(x=longitude, y=latitude),
             stroke=0, alpha=0.03, size=5, shape=16) +
  labs(x = "Longitude", y = "Latitude")

# finally, save the dataset
dir.create('inputs/data/cleaned')
save(raw, file='outputs/raw.RData')
save(cleaned_geocoded, file='outputs/cleaned.RData')




