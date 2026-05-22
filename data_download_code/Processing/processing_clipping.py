import os
import glob

from datetime import datetime, timedelta
from collections import defaultdict

import pytz
import geopandas as gpd
import xarray as xr
import numpy as np
from timezonefinder import TimezoneFinder

from Utilities.Most_Used_Functions import snap_bbox_to_grid,fast_bbox_clip_sel

def get_fire_metadata(lightning_path, LIWType):
    """Reads fire metadata from the lightning shapefile and returns a list of tuples containing relevant information for each fire."""
    Fires = gpd.read_file(lightning_path).to_crs(4326)
    fire_metadata = []  
    Failed_Fires = []
    for _, row in Fires.iterrows():
        FireID = str(row["FireID"]).split(".")[0]
        fire_geom = row["geometry"]
        str_time = row["Str_Time"]
        IgnLong = row["IgnLong"]
        IgnLat = row["IgnLat"]
        fire_metadata.append((LIWType, FireID, IgnLong, IgnLat, fire_geom, str_time))

    return fire_metadata, Failed_Fires

def group_fires_by_year_month_utc(fire_metadata): ## switch to utc/year
    """Groups fire metadata by year, this decreases the number of times we need to load the data :) """
    grouped_fires_yr_utc = defaultdict(list)
    for LIWType, FireID, IgnLong, IgnLat, fire_geom, str_time in fire_metadata:
        Ltng_StartDate = datetime.strptime(str_time[:26], "%Y-%m-%dT%H:%M:%S.%f") 
        year = Ltng_StartDate.year  
        month = Ltng_StartDate.month
        month = f"{month:02}"
        # Calc offset hours (UTC)
        offset_hours = get_timezone_offset_hours(fire_geom.centroid.y, fire_geom.centroid.x, Ltng_StartDate)

        offset_hours_int = int(round(offset_hours))
        offset_hours_value = f"{offset_hours_int:+03d}"

        grouped_fires_yr_utc[year].append((LIWType, FireID, IgnLong, IgnLat, fire_geom, year, month, offset_hours_value, str_time))
    return grouped_fires_yr_utc, year, offset_hours_value

def get_timezone_offset_hours(lat, lon, dt):
    """Calculates the timezone offset in hours for a given latitude, longitude, and datetime."""
    tf = TimezoneFinder()
    tz_name = tf.timezone_at(lat=lat, lng=lon)
    if not tz_name:
        raise ValueError("Could not determine timezone")
    local_tz = pytz.timezone(tz_name)
    localized_dt = local_tz.localize(dt)
    offset = localized_dt.utcoffset().total_seconds() / 3600
    return int(offset)

def preload_era5_land_data_for_year(year,offset_hours_value, base_dir,var_list):
    """Preloads ERA5 Land data for a given year and list of variables, returning a dictionary of xarray Datasets."""
    year_data = {}
    for var in var_list:
        if not os.path.exists(base_dir):
            print(f"Variable directory does not exist: {base_dir}") 
            continue
        file_paths = glob.glob(os.path.join(base_dir, f"clipped_{var}_{year}*_{offset_hours_value}.nc"))
        if not file_paths:
            print(f"No files found for {var} in {year}")
            continue
        if var == "tp":
            ds = xr.open_mfdataset(file_paths, combine='nested',concat_dim="time",engine="netcdf4")
        else:
            ds = xr.open_mfdataset(file_paths, combine='nested',concat_dim="day",engine="netcdf4")
        year_data[var] = ds
    return year_data

def get_local_datetime(dt, offset_hours):
    """Converts a UTC datetime to local datetime using the provided offset in hours."""
    return dt - timedelta(hours=offset_hours)

def process_fire_with_year_data(output_root, LIWType, FireID, IgnLong, IgnLat, fire_geom, str_time, year_data, single_point=False):
    """Processes a single fire by clipping the preloaded ERA5 Land data to the fire's geometry and saving the results as .npy files."""
    output_dir = os.path.join(output_root,FireID, LIWType)
    os.makedirs(output_dir, exist_ok=True)

    # Lightning start date
    Ltng_StartDate = datetime.strptime(str_time[:26], "%Y-%m-%dT%H:%M:%S.%f")
    #offest calculation
    offset_hours = get_timezone_offset_hours(fire_geom.centroid.y, fire_geom.centroid.x, Ltng_StartDate)
    
    ### Fire Size
    if not single_point:
        minx, miny, maxx, maxy = fire_geom.bounds
        buffered_coords = snap_bbox_to_grid([maxy, minx, miny, maxx], 0.1, 0.1)
        clipped_data = {var: fast_bbox_clip_sel(year_data[var], buffered_coords) for var in year_data}
    else:
        clipped_data ={var:year_data[var].sel(latitude=[IgnLat],longitude=[IgnLong],method="nearest") for var in year_data}
    # strart clip
    
    for var in clipped_data:
        if clipped_data[var].latitude.size == 0 or clipped_data[var].longitude.size == 0:
            print(f"{FireID}: No data found in bbox for {var}, skipping fire.")
            return
    # Loop over day offsets
    for offset_day in range(-15, 15):
        local_dt = get_local_datetime(
            Ltng_StartDate + timedelta(days=offset_day), offset_hours )
        local_dt = local_dt.replace(hour=0, minute=0, second=0, microsecond=0)

        # select data (only tp has time, instantaneous variables have day)
        clipped_day_data = {var: clipped_data[var].sel(time=local_dt) if var == "tp" else clipped_data[var].sel(day=local_dt) for var in clipped_data}

        for var in clipped_day_data:
            npy_path = os.path.join(output_dir,f"ERA5Land_{var}_{local_dt.year}{local_dt.month:02d}{local_dt.day:02d}_{offset_day:+03d}.npy")
            
            if var not in year_data:
                continue


            var_clipped_day_data = clipped_day_data[var]
            if isinstance(var_clipped_day_data, xr.Dataset):
                if var in var_clipped_day_data:
                    var_clipped_day_data = var_clipped_day_data[var]
                else:
                    var_clipped_day_data = var_clipped_day_data.to_array().squeeze()
            # convert to numpy
            arr = var_clipped_day_data.values
            np.save(npy_path, arr)




def clip_all_ERA5_land_fires(root_folder, output_root, biome_shapefile_path, lightning_path, LIWType, single_point = False):
    """Main function to clip all ERA5 Land data for all fires by their geometry and save the results as .npy files."""
    var_dict = ["tp", "rh", "t2m", "ws"] 
    boreal_shapefile = gpd.read_file(biome_shapefile_path)
    fire_metadata, _ = get_fire_metadata(lightning_path, LIWType)
    grouped_fires_yr_utc, year, offset_hours_value = group_fires_by_year_month_utc(fire_metadata) 
    for var in var_dict:
        for year, fires in grouped_fires_yr_utc.items():
            print(f"Loading year: {year} with {len(fires)} fires")
            s = datetime.now()
            year_data = preload_era5_land_data_for_year(year,offset_hours_value, root_folder, [var]) 
            print(f"Loaded year data in {datetime.now() - s}")
            print(f"Processing {len(fires)} fires for year {year}")
            for i, (LIWType, FireID,  IgnLong, IgnLat, fire_geom, year, _, offset_hours_value, str_time) in enumerate(fires):
                if not fire_geom.within(boreal_shapefile.geometry).all():
                    print(f"Skipping boreal fire {FireID} in {year}")
                    continue
                print(f"Processing fire {i+1}/{len(fires)}: {FireID} in {year}")
                process_fire_with_year_data(output_root,LIWType, FireID, IgnLong, IgnLat,fire_geom, str_time, year_data, single_point)
            year_data[var].close()
            year_data[var] = None
            year_data.clear()
