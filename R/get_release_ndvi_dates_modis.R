# Get MODIS NDVI dates

#Load packages
library(rgee)
library(raster)
library(lubridate)
library(piggyback)
library(tidyverse)

#' @author Brian Maitner, with tips from csaybar
#' @description This is an internal function used to convert the ee date to the UNIX standard date
get_integer_date <-function(img) {

  # 1. Extract the DayOfYear band
  day_values <- img$select("DayOfYear")

  # 2. Get the first day of the year and the UNIX base date.
  first_doy <- ee$Date(day_values$get("system:time_start"))$format("Y")
  base_date <- ee$Date("1970-01-01")


  # 3. Get the day diff between year start_date and UNIX date
  daydiff <- ee$Date(first_doy)$difference(base_date,"day")

  # 4. Mask to only values greater than zero.
  mask <- day_values$gt(0)
  day_values <- day_values$updateMask(mask)

  # #Now, I just need to add the origin to the map
  day_values$add(daydiff)
}



#' @author Brian Maitner, with tips from csaybar
#' @description This code is designed to modify the MODIS "DayOfYear" band to a "days relative to Jan 01 1970" band to facilitate comparisons with fire data and across years.
#' @param directory The directory the ndvi date layers should be saved to, defaults to "data/raw_data/ndvi_dates_modis/"
#' @param domain domain (sf polygon) used for masking
#' @param max_layers the maximum number of layers to download at once.  Set to NULL to ignore.  Default is 50
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy
#' @note This code assumes that data are downloaded in order, which is usually the case.  In the case that a raster is lost, it won't be replaced automatically unless it happens to be at the very end.
#' Probably not going to cause a problem, but worth noting out of caution.
#'
get_release_ndvi_dates_modis <- function(temp_directory = "data/temp/raw_data/ndvi_dates_modis/",
                                         tag = "raw_ndvi_dates_modis",
                                         domain,
                                         max_layers = 50,
                                         sleep_time = 1) {

  # clean out directory if it exists

    if(dir.exists(temp_directory)){
      unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)
    }

  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

  #Make sure there is a release by attempting to create one.  If it already exists, this will fail

    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  tag),
             error = function(e){message("Previous release found")})

  #Initialize earth engine (for targets works better if called here)

    ee_Initialize()

  # Load the collection

    modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A1")

  # Format the domain

    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()

  # convert date to UNIX standard (ie days from 1-1-1970)

    ndvi_integer_dates <- modis_ndvi$map(get_integer_date)

  # Download to local

    #Get a list of files already released

    released_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                               tag = tag)

    released_files$date <- gsub(pattern = ".tif",
                                replacement = "",
                                x = released_files$file_name)

    released_files <-
      released_files %>%
      filter(file_name != "") %>%
      filter(file_name != "log.csv")


    #check to see if any images have been downloaded already

    if(nrow(released_files) == 0){

      newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970

    }else{

      newest <- max(lubridate::as_date(released_files$date)) #if there are images, start with the most recent

    }


    # Filter the data to exclude anything you've already downloaded

      ndvi_integer_dates_new <-
        ndvi_integer_dates$
        filter(ee$Filter$gt("system:index",
                            gsub(pattern = "-", replacement = "_", x = newest)
        )
        )

    # Function to optionally limit the number of layers downloaded at once

      if(!is.null(max_layers)){

        info <- ndvi_integer_dates_new$getInfo()
        to_download <- unlist(lapply(X = info$features,FUN = function(x){x$properties$`system:index`}))

        to_download <- gsub(pattern = "_",replacement = "-",x = to_download)

        if(length(to_download) > max_layers){

          # ndvi_integer_dates_new <- ndvi_integer_dates_new$filterDate(start = to_download[1],
          #                                                     opt_end = to_download[max_layers+1])

          ndvi_integer_dates_new <-
            ndvi_integer_dates_new$
            filter(ee$Filter$lte("system:index",
                                 gsub(pattern = "-",
                                      replacement = "_",
                                      x = to_download[max_layers])
            )
            )

        }


      }# end if maxlayers is not null

  # Skip download if up to date already

      if(length(ndvi_integer_dates_new$getInfo()$features) == 0){

        message("No new NDVI date layers to download")
        return(invisible(NULL))

      }


  # Download the new stuff

    tryCatch(expr =
               ee_imagecollection_to_local(ic = ndvi_integer_dates_new,
                                           region = domain,
                                           dsn = temp_directory),
             error = function(e){message("Captured an error in rgee/earth engine processing of NDVI dates.")}
    )

  # Push files to release

      # Get a list of the local files

      local_files <- data.frame(local_filename = list.files(path = temp_directory,
                                                            recursive = TRUE,
                                                            full.names = TRUE))

      # End if there are no new/updated files to release

      if(nrow(local_files) == 0){

        message("Releases are already up to date.")
        return(invisible(NULL))


      }

      # loop through and release everything (if this causes problems, code in a sleep function)

        pb_upload(file = local_files$local_filename,
                  repo = "AdamWilsonLab/emma_envdata",
                  tag = tag)

    # Delete temp files
        unlink(x = file.path(temp_directory), #sub used to delete any trailing slashes, which interfere with unlink
               recursive = TRUE)

    # Finish up
      message("Finished Downloading NDVI date layers")
      return(invisible(NULL))
      #return(directory)



}#end function


########################################


