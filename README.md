# toronto-energy-consumption

## Overview

This repository explores the Toronto Energy Consumption dataset published by Open Data Toronto. I download the data and use geolocation to find which ward each building belongs to. In the paper, I look at the change in greenhouse gas emissions year-after-year in Toronto and find that while the total reported amount of greenhouse gasses increases almost every year, on average individual operations report a decreasing amount of emissions. This is likely due to an increase in operations who submit their data, as well as an increase in the number of operations in Toronto.

## Repository

The repository uses R to download and preprocess the data, using OpenStreetMap for geocoding, and RMarkdown to generate the final report. The `inputs` directory contains datasets that are saved unaltered from OpenDataToronto while the `outputs` directory contains files that are loaded when generating the report. The files in `outputs` have varying levels of preprocessing applied and contain the geocoded data. The `scripts` directory contains one script, `fetch_data.R`, which generates the files in the `outputs` directory. `bibliography.bib` contains the citations for the paper, and `ghg_emissions.pdg` contains the final paper.

In order to run generate the report from scratch, run the `scripts/fetch_data.R` script to download the datasets and generate the data that will be loaded when building the report. Note that this script does as much as it can to be efficient, but will still take 30-40 minutes to run. Next compile `ghg_emissions.rmd` to generate the report.