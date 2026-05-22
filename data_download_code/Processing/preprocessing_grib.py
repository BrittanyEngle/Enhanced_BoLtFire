
import os
import glob
import subprocess
import shutil
import time

from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor, as_completed

import dask.array as da
import xarray as xr
import geopandas as gpd

def process_gribs(root_folder, biome_shapefile_path, worker_count=6):
    """
    Main function to process GRIB files: splits them by variable and date, then clips them by biome."""
    split_grib_by_all_parallel(root_folder, worker_count)
    clip_grib_by_biome_parallel(root_folder, biome_shapefile_path, worker_count)

def split_grib_by_all_parallel(root_folder, worker_count=6):
    """
    This function splits GRIB files by variable (shortName), date (dataDate), and step (stepRange) in parallel using grib_copy.
    """
    print("Started: split_grib_by_all_parallel")
    all_gribs = [os.path.join(root_folder,name,"data.grib") for name in os.listdir(root_folder) if os.path.isdir(os.path.join(root_folder, name))]
    all_outputs = [os.path.join(root_folder,name,"temp") for name in os.listdir(root_folder) if os.path.isdir(os.path.join(root_folder, name))]

    with ProcessPoolExecutor(worker_count) as executor:
        {executor.submit(split_grib_by_all, path[0], path[1]): path for path in zip(all_gribs,all_outputs)}
            
def split_grib_by_all(grib_path, output_path):
    """
    Splits GRIB files by variable (shortName), date (dataDate), and step (stepRange).
    """
    os.makedirs(output_path,exist_ok=True)
    with open(os.path.join(output_path,"processing.txt"), "w") as f:
        pass
    subprocess.run(["grib_copy",grib_path ,os.path.join(output_path,"[shortName]_[dataDate]_[stepRange].grib")])
    print(f"Done splitting {grib_path}")
    os.remove(os.path.join(output_path,"processing.txt"))

def clip_grib_by_biome_parallel(root_folder,biome_shapefile_path, worker_count=6):
    """
    This function clips GRIB files by biome/aoi to save space and increase efficiency.
    """
    print("Started: clip_grib_by_biome_parallel")
    all_folders = [os.path.join(root_folder,name) for name in os.listdir(root_folder) if os.path.isdir(os.path.join(root_folder, name))]
    var_names = ["10u","10v", "2d","2t","tp"]

    gdf = gpd.read_file(biome_shapefile_path)
    gdf = gdf.to_crs("EPSG:4326")  # Ensure CRS is EPSG:4326
    geom = gdf.geometry

    for folder in all_folders:
        if not os.path.exists(os.path.join(folder,"temp")):
            continue

        if os.path.exists(os.path.join(folder,"temp","processing.txt")):
            continue
        print(f"Processing folder: {folder}")
        
        for var_name in var_names:

            grib_paths = glob.glob(os.path.join(folder,"temp",f"{var_name}*.grib"))
            year_month = grib_paths[1].split("_")[-2][:-2]
            clipped_vars = []
            all_errors =[]
            star = time.time()
            with ProcessPoolExecutor(max_workers = worker_count) as executor:
                futures ={executor.submit(clip_grib_by_biome, grib_path, geom): grib_path for grib_path in grib_paths}
                for future in as_completed(futures):
                    result = future.result()
                    if "errors" in result and result["errors"]:
                        all_errors.extend(result["errors"])
                    if "clipped_vars" in result and result["clipped_vars"]:
                        clipped_vars.extend(result["clipped_vars"])
                    
            if all_errors:
                print(f"Errors occurred while processing {folder}:")
                for error in all_errors:
                    print(error)
                shutil.rmtree(os.path.join(folder, "temp"))  # Clean up temp files
                continue 
            
            grouped = defaultdict(list)
            for da in clipped_vars:
                t = da.time.values[0]
                grouped[t].append(da)
            daily_arrays = []
            for t in grouped:
                day_steps = xr.concat(grouped[t], dim='step')
                daily_arrays.append(day_steps)
            combined = xr.concat(daily_arrays, dim='time')
            combined.to_netcdf(f"{root_folder}/clipped_{var_name}_{year_month}.nc", mode='w', format='NETCDF4')

        print(f"Clipped dataset saved for {year_month}.")
        shutil.rmtree(os.path.join(folder))
        print(f"Temporary files cleaned up for {folder}.")
        print(f"Processing completed for folder: {folder} for {time.time()-star} seconds")

def clip_grib_by_biome(grib_path, geom):
    """Clips a GRIB file by the given geometry (biome/aoi) and returns the clipped variables as xarray DataArrays."""
    output = {"clipped_vars": [],  "errors": []}
    ds = xr.open_dataset(grib_path, engine='cfgrib', backend_kwargs={"errors": "ignore"})
    ds.rio.set_spatial_dims(x_dim='longitude', y_dim='latitude', inplace=True)
    ds.rio.write_crs("EPSG:4326", inplace=True)
    t = ds.time.values
    s = ds.step.values
    for var in ds.data_vars:
        var_data = ds[var]
        try:
            clipped = var_data.rio.clip(geom, "EPSG:4326", drop=True, all_touched=True)
            clipped = clipped.expand_dims({'time':[t], 'step':[s]})
            clipped.data = da.from_array(clipped.data, chunks="auto")
            output["clipped_vars"].append(clipped)
        except Exception as e:
            output["errors"].append(f"Error clipping variable {var} at time {t+s}: {e}")
    ds.close()

    return output
