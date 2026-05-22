import os
from datetime import datetime

import ee
import geopandas as gpd
import numpy as np
import pandas as pd

from Utilities.Path_Utilities import get_enhanced_boltfire_location, get_input_parameters
from Utilities.Most_Used_Functions import snap_bbox_to_grid


def get_modis_download_variables():
    """Returns a list of dictionaries containing the necessary information for downloading MODIS NPP data."""
    npp = {
        "image_url": "MODIS/061/MOD17A3HGF",
        "variable": "Npp",
        "resolution": 500,
        "scale": 0.0001,
    }
    return [npp], {"Npp": npp}


def download_modis_numpy(image, bounds, npy_output_path, scale_factor=0.0001):
    """Downloads the specified MODIS variable as a NumPy array, applying the given scale factor, and saves it to the specified path."""
    if os.path.exists(npy_output_path):
        print(f"{npy_output_path} skipping, already there")
        return True

    ee_fill_value = -30001

    sample = image.sampleRectangle(region=bounds,defaultValue=ee_fill_value).getInfo()

    arr = np.array(sample["properties"]["Npp"], dtype=np.float32)
    arr[arr == ee_fill_value] = np.nan

    arr *= scale_factor
    np.save(npy_output_path, arr)

    print(f"Saved NumPy array to {npy_output_path}")
    return True



def download_modis(lightning_path, LIWtype):
    """For each fire, downloads MODIS NPP data for the year of the fire and saves it as .npy files."""
    fires = gpd.read_file(lightning_path).to_crs(4326)

    downloaded_fires = []
    failed_fires = []
    saved_fires = 0

    _, key_vars = get_modis_download_variables()

    for _, row in fires.iterrows():
        fire_id = str(row["FireID"]).split(".")[0]

        if fire_id in downloaded_fires:
            continue

        output_folder = os.path.join(get_enhanced_boltfire_location(), fire_id, LIWtype)
        os.makedirs(output_folder, exist_ok=True)

        start_date_dt = datetime.strptime(row["Str_Time"][:10], "%Y-%m-%d")
        start_date = start_date_dt.strftime("%Y-%m-%d")
        year = start_date_dt.strftime("%Y")
        date_str = start_date.replace("-", "")


        bounds = [
            row["geometry"].bounds[3],  # W
            row["geometry"].bounds[0],  # S
            row["geometry"].bounds[1],  # E
            row["geometry"].bounds[2],  # N
        ]

        resolution = 0.0001
        bounds = snap_bbox_to_grid(bounds, resolution, resolution)

        bounds = ee.Geometry.Rectangle(
            [
                bounds[1] - resolution / 2.0,
                bounds[0] + resolution / 2.0,
                bounds[3] + resolution / 2.0,
                bounds[2] - resolution / 2.0,
            ]
        )

        downloads_worked = True

        for _, var_info in key_vars.items():
            variable = var_info["variable"]

            if variable != "Npp":
                continue

            npy_path = os.path.join(output_folder, f"NPP_{date_str}.npy")
    
            image = (ee.ImageCollection(var_info["image_url"]).filterDate(f"{year}-01-01", f"{int(year) + 1}-01-01").first().select(variable))

            if image is None:
                print(f"No image found for NPP for FireID {fire_id}")
                downloads_worked = False
                continue

            image = image.reproject( crs="EPSG:4326",   scale=var_info["resolution"]).clip(bounds)

            npy_download = download_modis_numpy(image=image, bounds=bounds, npy_output_path=npy_path, scale_factor=var_info["scale"])

            if npy_download:
                print(f"NPP geotiff and numpy downloaded for {fire_id}")
            else:
                downloads_worked = False

        if downloads_worked:
            downloaded_fires.append(fire_id)
            saved_fires += 1
        else:
            failed_fires.append(fire_id)

    print(f" NPP download completed - successful: {saved_fires}, failed: {len(failed_fires)}")

    if failed_fires:
        failed_df = pd.DataFrame(failed_fires, columns=["FailedFireID"])
        failed_export_path = os.path.join(get_input_parameters(), "NPP_Failed_Fires.csv")
        failed_df.to_csv(failed_export_path, index=False)
        print(f"Failed Fires exported to: {failed_export_path}")
