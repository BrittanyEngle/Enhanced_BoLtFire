import os
from calendar import monthrange
from concurrent.futures import ThreadPoolExecutor, as_completed

import cdsapi

def download_era5_instant(client, year, month, base_path):
    """Download one month of hourly ERA5-Land data (dewpoint, temperature, wind components and total precip) and save it as a zipped GRIB file."""
    variable_list = ["2m_dewpoint_temperature", "2m_temperature", "10m_u_component_of_wind", "10m_v_component_of_wind","total_precipitation"]
    dataset = "reanalysis-era5-land"
    last_day = monthrange(year, int(month))[1]
    all_days = [f"{d:02d}" for d in range(1, last_day + 1)]

    request = {
        "variable": variable_list,
        "year": str(year),
        "month": month,
        "day": all_days,
        "time": [
        "00:00", "01:00", "02:00",
        "03:00", "04:00", "05:00",
        "06:00", "07:00", "08:00",
        "09:00", "10:00", "11:00",
        "12:00", "13:00", "14:00",
        "15:00", "16:00", "17:00",
        "18:00", "19:00", "20:00",
        "21:00", "22:00", "23:00"],
        "data_format": "grib",
        "download_format": "zip",
        "area": [90, -180, 0, 180]
    }

    filename = f"{year}_{month}_other.zip"
    target_dir = os.path.join(base_path)
    target = os.path.join(target_dir, filename)
    if os.path.exists(target):
        print(f"File already exists: {target}")
        return
    os.makedirs(target_dir, exist_ok=True)

    print(f"Submitting: {filename}")

    client.retrieve(dataset, request).download(target)
    print(f"Downloaded: {filename}")

def download_era5_parallel(ERA5_download_path, worker_count=2):
    """Allows for parallel downloading of multiple months of ERA5-Land data."""
    years = range(2012,2023)
    months = [f"{m:02d}" for m in range(1, 13)]

    os.environ['CDSAPI_URL'] = 'https://cds.climate.copernicus.eu/api'
    client = cdsapi.Client()

    tasks = []
    with ThreadPoolExecutor(max_workers=worker_count) as executor:
        for year in years:
            for month in months:
                tasks.append(executor.submit(download_era5_instant, client, year, month, ERA5_download_path))

    for future in as_completed(tasks):
        future.result()  
