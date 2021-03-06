#' @author Brian Maitner
#' @param input_tag tag associated with input files
#' @param output_tag tag assocaited with output files
#' @param temp_directory A temporary directory to use for processessing.  Will be cleared out at the end.
#' @param template_release path to raster file to use as a template for reprojection
#' @param ... Does nothing, but is used in making connections between files in the targets framework
#' @note This function uses method = bilinear at present
process_release_elevation_nasadem <- function(input_tag = "raw_static",
                                              output_tag = "processed_static",
                                              temp_directory = "data/temp/raw_data/elevation_nasadem/",
                                              template_release,
                                              ...){

  #  #Ensure directory is empty if it exists

    if(dir.exists(temp_directory)){
      unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
    }

  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }


  # get template raster

    robust_pb_download(file = template_release$file,
                       dest = temp_directory,
                       repo = template_release$repo,
                       tag = template_release$tag,
                       max_attempts = 10,
                       sleep_time = 10)

    #template <- terra::rast(file.path(temp_directory, template_release$file))
    template <- raster::raster(file.path(temp_directory, template_release$file))


    # get input rasters

    raster_list <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                           tag = input_tag) %>%
      filter(grepl(pattern = "nasadem",
                   x = file_name))

    robust_pb_download(file = raster_list$file_name,
                       dest = temp_directory,
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = input_tag,
                       max_attempts = 10,
                       sleep_time = 10)


    # reformat and save each

    for(i in 1:nrow(raster_list)){

      raster_i <- raster::raster(file.path(temp_directory, raster_list$file_name[i]))
      #raster_i <- terra::rast(file.path(temp_directory, raster_list$file_name[i]))


      #Use bilinear for everything

        method <- "bilinear"

      raster::projectRaster(from = raster_i,
                            to = template,
                            method = method,
                            filename = file.path(temp_directory, paste("tf_",raster_list$file_name[i],sep = "")),
                            overwrite = TRUE
                            )

      #Terra is currently having some problems with reading and writing so I've switched back to raster for now
      # terra::project(x = raster_i,
      #                y = template,
      #                method = method,
      #                filename = file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = "")),
      #                overwrite = TRUE)

      # Double check projection

        if(projection(raster(file.path(temp_directory, paste("tf_",raster_list$file_name[i],sep = "")))) != projection(template)){
          stop("Issue with reprojection")
          }


      pb_upload(file = file.path(temp_directory, paste("tf_",raster_list$file_name[i],sep = "")),
                repo = "AdamWilsonLab/emma_envdata",
                tag = output_tag,
                name = raster_list$file_name[i])

      # cleanup
        rm(raster_i)
        file.remove( file.path(temp_directory, paste("tf_",raster_list$file_name[i],sep = "")) )
        file.remove( file.path(temp_directory, raster_list$file_name[i]) )


    } #i loop

  # Clear out the folder

    unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)

  # End functions

    message("Finished processing elevation layer")
    return(invisible(NULL))


} #end fx



#################################

