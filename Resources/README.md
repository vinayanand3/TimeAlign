# cities.tsv

World city list used by the "Add a city or time zone" search: about 34,000 cities with
population of at least 15,000.

- Source: GeoNames `cities15000.zip`, `admin1CodesASCII.txt`, `countryInfo.txt`
  from https://download.geonames.org/export/dump/
- License: Creative Commons Attribution 4.0 (https://creativecommons.org/licenses/by/4.0/).
  Data by GeoNames (https://www.geonames.org).
- Columns: name, subtitle ("State, Country"), IANA zone, population, aliases (comma-separated,
  only for cities of 500k+ so old names like Bombay or Bangalore still match).

To refresh: download and unzip those three files into a folder, then run
`python3 tools/trim_geonames.py <folder> Resources/cities.tsv`.
