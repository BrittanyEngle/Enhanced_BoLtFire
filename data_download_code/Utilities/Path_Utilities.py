
def get_root_folder():
    return "/path/to/root/folder/"

def get_output_folder():
    return "/path/to/output/folder/"

#-------------------ENTLN PATHS-----------------------------------
def get_entln_continent():
    return f"{get_root_folder()}ENTLN/Continent_Split/"

#-------------------- Non_LIWs -----------------------------------
def get_preprocessing_boltfire():
    return f"{get_root_folder()}PreProcessing_BoLtFire"

def get_non_liws():
    return f"{get_root_folder()}NonLIWs"

##-------------------GLOBFIRE------------------------------

def get_gwis_main_dataset():
    return f"{get_root_folder()}GlobFire/Processed/"

##-------------------BOLTFIRE_PUBLIC_DATASET------------------------------

def get_boltfire_public_dataset():
    return f"{get_root_folder()}BoLtFire_Public_Dataset/"

def get_enhanced_boltfire_dataset():
    return f"{get_root_folder()}Enhanced_BoLtFire/"

def get_enhanced_boltfire_location():
    return f"{get_root_folder()}Enhanced_BoLtFire/"

##-------------------Inputs&Outputs------------------------------
def get_input_parameters():
    return f"{get_root_folder()}Input_Parameters/"

##-------------------Results------------------------------
def get_csv_results():
    return f"{get_root_folder()}csv_results/"

def get_era5_reanalysis_folder():
    return f"{get_root_folder()}ERA5_Reanalysis/"
