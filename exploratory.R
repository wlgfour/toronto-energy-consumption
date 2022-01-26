#### Preamble ####
# Purpose: Read ward boundaries and energy consumption data from opendatatoronto.
#          Use osm to geocode buildings and find which wards they are in.
# Author: William Gerecke
# Email: wlgfour@gmail.com
# Date: 1/26/2022
# Prerequisites: An older version required a Google Maps API key, but osm allows
#                free API calls so the only prerequisites are the packages
#                loaded below.
# Notes: This script will geocode 1483 buildings at 1 API call per second. This
#        means that the script will take at least 23 minutes to run.

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

# plot the map
ggplot(wards) +
  geom_sf(aes(fill=X))

# get building energy consumption from opendartatoronto
package <- show_package("0600cad8-d024-483b-a9a8-ecfc3e32e375") %>%
  list_package_resources() %>%
  filter(name == "annual-energy-consumption-data-2018") %>%
  get_resource()

# clean the dataframe
col_names <- c("Operation Name", "Operation Type", "Address", "City",
               "Postal Code", "Total Floor Area", "Unit", "Avg hrs/wk",
               "Annual Flow (Mega Litres)", "Electricity Quantity",
               "Electricity Unit", "Natural Gas Quantity", "Natural Gas Unit")

# remove extra columns
cleaned <- package[, 1:13] %>%
  slice(8:n())

# rename columns
cleaned <- cleaned %>%
  setNames(col_names) %>%
  clean_names()

address <- paste(cleaned$address, cleaned$city, sep=", ")
cleaned$address <- address

# geocode addresses
latlon <- cleaned %>%
  geocode(address, method = 'osm', lat = latitude , long = longitude)

# beind addresses to dataframe
geocoded <- cleaned %>%
  cbind(select(latlon, latitude, longitude))

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
joined <- ward_labelled %>%
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
         electricity_wh, gas_cm, latitude, longitude) %>%
  na_if("") %>%
  drop_na()

ggplot(wards) +
  geom_sf(aes(fill=X)) +
  geom_point(data=joined, aes(x=longitude, y=latitude)) +
  labs(x = "Longitude", y = "Latitude")

# finally, save the dataset
save(joined, file='inputs/data/cleaned/cleaned.RData')




