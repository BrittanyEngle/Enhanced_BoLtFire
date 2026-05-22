import ee
import os
from ERA5Download.ERA5Land_Download import download_era5_parallel
from Non_LIW_Download import clip_entln_by_liws_buffered,get_neares_flashes, download_non_liw_image_modis
from Parameter_Download.Invariants import generate_invariants_data
from Parameter_Download.MODIS_NPP import download_modis
from Utilities.Path_Utilities import  getInputParameters
from Processing.preprocessing_grib import process_gribs
from Processing.processing import generate_monthly_utcfiles_parallel, calculate_rh_ws
from Processing.processing_clipping import clip_all_ERA5_land_fires
from Results import compute_era5_means_with_offset
from Results import compute_era5_means_with_offset


if __name__ == "__main__":
########### SETUP ############
    ### GEE Authentication
    ee.Authenticate()
    ee.Initialize(project="") # GEE account here

    ## Processing threads, you can adjust this based on your computing capabilities
    num_threads = 15
    os.environ.setdefault("OMP_NUM_THREADS", str(num_threads))
    os.environ.setdefault("OPENBLAS_NUM_THREADS", str(num_threads))
    os.environ.setdefault("MKL_NUM_THREADS", str(num_threads))
    os.environ.setdefault("VECLIB_MAXIMUM_THREADS", str(num_threads))
    os.environ.setdefault("NUMEXPR_NUM_THREADS", str(num_threads))       


########### NonLIW Preprocessing & No-Fire Review ############
    """Since we already have all of the LIW fires, we now need to find the NoLIW fires."""

    """BoLtFire Shapefiles are built by continent, we will loop through each continent and find the NoLIW fires for each continent."""
    for continent in ["NA", "AS", "EU"]:
        """ 1. This loads BoLtFire dataset, and uses the GWIS dataset to go back, 
        year-by-year to ensure no previous fire. Then the ENTLN lightning location data is clipped to that buffered fire polygon."""
        clip_entln_by_liws_buffered(continent)
        """ 2. Nearest flash from the buffered ENTLN NoLIW to the BoLtFire lighting ignition point is selected."""
        get_neares_flashes(continent)
        """3.  This downloads MODIS RGB imagery for each NoLIW fire. dNBR is calculated from the imagery. 
        The imagery is used to confirm that there was no previous fire."""

        NonLIW_file_path = "" # path of NoLIWs
        download_non_liw_image_modis(continent, NonLIW_file_path)


########### ERA5-Land Download and Processing ############

    """ 1. Use download.py to download ERA5 data as zip files
    Set the amount of threads you want running during the download using max_workers in the function call. This will push multiple requests to the CDS API at once, 
    which "will speed up the download process". Be careful here, the API punishes you for too many requests at once. I had the best results at 2 or 3."""
    ERA5_download_path = ""
    worker_count = 2
    download_era5_parallel(ERA5_download_path,worker_count)

    """ 2. Unzip the files using the below command (after running: All files should now be unzipped, the file inside each folder will be a grib file)"""
    #cd /path/to/ERA5_Land/All_Variables/
    #for zip in *.zip; do unzip -q "$zip" -d "${zip%.zip}"; done

    """ If you made a mistake and need to re-download individual files, you can use the below command to download one file at a time. """
    #cd /path/to/ERA5_Land/All_Variables/
    #unzip /path/to/ERA5_Land/All_Variables/2012_12_other.zip -d 2012_12_other

    """3. Run process_gribs() from preprocessing_grib.py: this will split the grib files from each folder into netcdf files based on variable, date, and step.
    It will then clip each netcdf file by the AOI to minimize space requirements of the data."""

    root_folder = ""
    biome_shapefile_path = ""
    worker_count = 6
    process_gribs(root_folder, biome_shapefile_path,worker_count)

    """4. Run generate_monthly_utcfiles_parallel() from processing.py: this file splits each of the variables into monthly 
    netcdfs for those variables""" 
    root_folder = ""
    worker_count = 5
    generate_monthly_utcfiles_parallel(root_folder,worker_count)

    """5. Run calc_RH_WS() from processing.py to calculate the relative humidity and wind speed from the ERA5-Land variables. This will create new netcdf files for RH and WS."""
    clipped_root_folder = ""
    calculate_rh_ws(clipped_root_folder)

    """6. Run ERA5_land_clip_all_fires() from processing_clipping, this will clip each variable by each fire """
    ### Filepaths
    output_root = ""
    root_folder = ""
    biome_shapefile_path
    LIW_fires_path = os.path.join(getInputParameters(), f"PreProcessing_LIWs/BoLtFire_LIWs_ALL.shp")
    NonLIW_fires_path = os.path.join(getInputParameters(), f"PreProcessing_NonLIWs/BoLtFire_NonLIWs_ALL.shp")
    clip_all_ERA5_land_fires(root_folder, output_root,biome_shapefile_path, LIW_fires_path, "LIW",single_point = False)
    clip_all_ERA5_land_fires(root_folder, output_root, biome_shapefile_path, NonLIW_fires_path, "NonLIW",single_point = False)

########### Invariant Downloads and Processing ############
    ### Filepaths
    LIW_fires_path = os.path.join(getInputParameters(), f"PreProcessing_LIWs/BoLtFire_LIWs_ALL.shp")
    NonLIW_fires_path = os.path.join(getInputParameters(), f"PreProcessing_NonLIWs/BoLtFire_NonLIWs_ALL.shp")


    """ 1. Run invariants_data() from Invariants.py: this will download the MODIS data for each fire and save it as geotiffs. 
    It will also create a 512x512 grid of the value of the invariant for each fire, which can be used as input to the model. 
    The numpy file is used as input to the model, while the geotiff is for visualization purposes.
    """
    generate_invariants_data(LIW_fires_path, "LIW")
    generate_invariants_data(NonLIW_fires_path, "NonLIW")

    """ 2. Run MODIS_downloads from MODIS_NPP.py to download MODIS NPP as a numoy file and a geotiff for each fire. 
    The numpy file is used as input to the model, while the geotiff is for visualization purposes. """
    download_modis(LIW_fires_path, "LIW")
    download_modis(NonLIW_fires_path, "NonLIW")

 

########### Resulting CSV file ############
    """ Run compute_era5_land_paper2_means_with_offset() from Results.py to create the resulting CSV file with the mean values of each variable for each fire, as well as the offset from the ignition day.
    This csv is the imported into the R script for the final analysis and plotting."""
    compute_era5_means_with_offset() ## create the CSV for the R script to read in for the final analysis and plotting

