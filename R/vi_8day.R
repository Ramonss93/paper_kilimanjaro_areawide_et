### environment ----------------------------------------------------------------

## clear workspace
rm(list = ls(all = TRUE))

## set working directory
Orcs::setwdOS(path_lin = "/media/fdetsch/XChange/", path_win = "D:/",
              path_ext = "kilimanjaro/evapotranspiration")

## load packages
lib <- c("MODIS", "Rsenal", "rgdal", "doParallel")
Orcs::loadPkgs(lib)

## parallelization
cl <- makeCluster(detectCores() - 1)
registerDoParallel(cl)

## modis options
MODISoptions(localArcPath = "MODIS_ARC", outDirPath = "MODIS_ARC/PROCESSED",
             outProj = "+init=epsg:21037")


## loop over single product
lst <- lapply(c("MOD09Q1", "MYD09Q1"), function(product) {
  
  ## status message
  cat("Commencing with the processing of", product, "...\n")
  
  # ## download data
  # runGdal(product = product, collection = "006",
  #         begin = "2013001", end = "2015365", tileH = 21, tileV = 9,
  #         job = paste0(product, ".006"))
  
  ### crop layers ----------------------------------------------------------------
  
  ## reference extent
  ext_crop <- uniformExtent()

  ## target folder
  dir_crp <- paste0("data/", product, ".006/crp")
  if (!dir.exists(dir_crp)) dir.create(dir_crp)

  # ## perform crop
  # rst_crp <- foreach(i = c("b01", "b02", "state_250m", "qc_250m"),
  #                    .packages = "MODIS") %dopar% {
  #                      
  #   # list and import available files
  #   fls <- list.files(paste0(getOption("MODIS_outDirPath"), "/", product, ".006"),
  #                     pattern = paste0(i, ".tif$"), full.names = TRUE)
  #   rst <- raster::stack(fls)
  #   
  #   # crop
  #   fls_out <- paste(dir_crp, basename(fls), sep = "/")
  #   rst_out <- raster::crop(rst, ext_crop, snap = "out")
  #   
  #   # if dealing with band 1 or band 2, apply scale factor
  #   if (i %in% c("b01", "b02")) {
  #     raster::dataType(rst_out) <- "INT2S"
  #     rst_out <- rst_out * 0.0001
  #     
  #   # else convert to 16-bit unsigned integer
  #   } else {
  #     raster::dataType(rst_out) <- "INT2U"
  #   }
  #   
  #   # save and return cropped layers
  #   lst_out <- lapply(1:nlayers(rst_out), function(j)
  #     raster::writeRaster(rst_out[[j]], filename = fls_out[j],
  #                         format = "GTiff", overwrite = TRUE)
  #   )
  #   
  #   raster::stack(lst_out)
  # }
  
  ## reimport cropped files
  rst_crp <- foreach(i = c("b01", "b02", "state_250m", "qc_250m"), 
                     .packages = "raster") %dopar% {
    
    # list and import available files
    fls_crp <- list.files(dir_crp, pattern = paste0(i, ".tif$"), full.names = TRUE)
    stack(fls_crp)
  }
  
  
  ### quality control, step #1: ------------------------------------------------
  ### discard cloudy pixels based on companion quality information ('qc_250m')
  
  dir_qc1 <- paste0("data/", product, ".006/qc1")
  if (!dir.exists(dir_qc1)) dir.create(dir_qc1)
  
  # # perform quality check #1 for each band separately
  # lst_qc1 <- foreach(i = rst_crp[1:2]) %do% {
  #   
  #   ## loop over layers
  #   lst_out <- foreach(j = 1:nlayers(i), .packages = lib) %dopar%
  #     overlay(i[[j]], rst_crp[[4]][[j]], fun = function(x, y) {
  #       id <- sapply(y[], function(k) {
  #         bin <- number2binary(k, 16, TRUE)
  #         modland <- substr(bin, 15, 16)
  #         
  #         # all bands ideal quality
  #         if (modland == "00") {
  #           return(TRUE)
  #           
  #           # some or all bands less than ideal quality
  #         } else if (modland == "01") {
  #           qual_b1 <- substr(bin, 9, 12) %in% c("0000", "0111", "1000", "1100")
  #           qual_b2 <- substr(bin, 5, 8) %in% c("0000", "0111", "1000", "1100")
  #           
  #           all(qual_b1, qual_b2)
  #           
  #           # pixel not produced due to cloud effects or other reasons
  #         } else {
  #           return(FALSE)
  #         }
  #       })
  #       
  #       x[!id] <- NA
  #       return(x)
  #     }, filename = paste(dir_qc1, names(i[[j]]), sep = "/"),
  #     overwrite = TRUE, format = "GTiff")
  #   
  #   raster::stack(lst_out)
  # }
  
  ## reimport step #1 quality-controlled files
  lst_qc1 <- foreach(i = c("b01", "b02"), .packages = "raster") %dopar% {
    fls_qc1 <- list.files(dir_qc1, pattern = paste0(i, ".tif$"), full.names = TRUE)
    stack(fls_qc1)
  }
  
  
  ### quality control, step #2: ------------------------------------------------
  ### discard cloudy pixels based on 'state_250m' flags
  
  dir_qc2 <- paste0("data/", product, ".006/qc2")
  if (!dir.exists(dir_qc2)) dir.create(dir_qc2)
  
  # ## perform quality check #2 for each band separately
  # lst_qc2 <- foreach(i = lst_qc1) %do% {
  #   
  #   ## loop over layers
  #   lst_out <- foreach(j = 1:nlayers(i), .packages = lib) %dopar%
  #     overlay(i[[j]], rst_crp[[3]][[j]], fun = function(x, y) {
  #       id <- sapply(y[], function(k) {
  #         bin <- number2binary(k, 16, TRUE)
  #         cloud_state <- substr(bin, 15, 16) %in% c("00", "11", "10")
  #         cloud_shadow <- substr(bin, 14, 14) == "0"
  #         cirrus <- substr(bin, 7, 8) %in% c("00", "01")
  #         intern_cloud <- substr(bin, 6, 6) == "0"
  #         fire <- substr(bin, 5, 5) == "0"
  #         snow <- substr(bin, 4, 4) == "0"
  #         intern_snow <- substr(bin, 1, 1) == "0"
  #         
  #         all(cloud_state, cloud_shadow, cirrus, intern_cloud,
  #             fire, snow, intern_snow)
  #       })
  #       
  #       x[!id] <- NA
  #       return(x)
  #     }, filename = paste(dir_qc2, names(i[[j]]), sep = "/"),
  #     overwrite = TRUE, format = "GTiff")
  #   
  #   raster::stack(lst_out)
  # }
  
  ## reimport step #2 quality-controlled files
  lst_qc2 <- foreach(i = c("b01", "b02"), .packages = "raster") %dopar% {
    fls_qc2 <- list.files(dir_qc2, pattern = paste0(i, ".tif$"), full.names = TRUE)
    stack(fls_qc2)
  }
  
  
  ### quality control, step #3: ------------------------------------------------
  ### discard pixels adjacent to clouds
  
  dir_qc3 <- paste0("data/", product, ".006/qc3")
  if (!dir.exists(dir_qc3)) dir.create(dir_qc3)
  
  ## perform quality check #3 for each band separately
  lst_qc3 <- foreach(i = lst_qc2) %do% {
    raster::stack(foreach(j = unstack(i), .packages = "raster") %dopar% {
      fls_qc3 <- paste0(dir_qc3, "/", names(j), ".tif")
      if (file.exists(fls_qc3)) {
        raster::raster(fls_qc3)
      } else {
        rst_msk <- raster::focal(j, w = matrix(1, 3, 3), fun = function(x) {
          any(is.na(x[c(2, 4, 6, 8)]))
        })
        
        j[rst_msk == 1] <- NA
        raster::writeRaster(j, filename = fls_qc3, 
                            format = "GTiff", overwrite = TRUE)
      }
    })
  }


# ### monthly value composites ---------------------------------------------------
#
# indices <- as.numeric(as.factor(as.yearmon(seq(as.Date("2013-01-01"),
#                                                as.Date("2013-02-28"), 8))))
#
# rst.b1.b2.agg <-
#   foreach(i = c(1, 2), .packages = lib) %dopar% {
#     foreach(j = unique(indices), .combine = "stack") %do% {
#       sub <- rst.b1.b2.cc[[i]][[grep(j, indices)]]
#       calc(sub, fun = function(x) {
#         if (all(is.na(x))) return(NA) else return(round(median(x, na.rm = TRUE)))
#       }, filename = paste0("myd09q1/processed/AGG_", names(sub)[1]),
#       format = "GTiff", overwrite = TRUE)
#     }
#   }


  ### normalized difference vegetation index -----------------------------------
  
  dir_ndvi <- paste0("data/", product, ".006/ndvi")
  if (!dir.exists(dir_ndvi)) dir.create(dir_ndvi)
  
  fls_ndvi <- gsub("_b01", "", names(lst_qc1[[1]]))
  
  fls_ndvi_out <- paste0(dir_ndvi, "/NDVI_", fls_ndvi, ".tif")
  if (all(file.exists(fls_ndvi_out))) {
    rst_ndvi <- raster::stack(fls_ndvi_out)
  } else {
    rst_ndvi <- ndvi(lst_qc3[[1]], lst_qc3[[2]],
                     filename = paste0(dir_ndvi, "/NDVI"),
                     format = "GTiff", overwrite = TRUE,
                     bylayer = TRUE, suffix = fls_ndvi)
  }
  

  ### soil-adjusted vegetation index -------------------------------------------
  
  dir_savi <- paste0("data/", product, ".006/savi")
  if (!dir.exists(dir_savi)) dir.create(dir_savi)
  
  fls_savi <- gsub("_b01", "", names(lst_qc1[[1]]))
  
  fls_savi_out <- paste0(dir_savi, "/SAVI_", fls_savi, ".tif")
  if (all(file.exists(fls_savi_out))) {
    rst_savi <- raster::stack(fls_savi_out)
  } else {
    rst_savi <- savi(lst_qc3[[1]], lst_qc3[[2]],
                   filename = paste0(dir_savi, "/SAVI"),
                   format = "GTiff", overwrite = TRUE,
                   bylayer = TRUE, suffix = fls_savi)
  }
  
  return(list(rst_ndvi, rst_savi))
})


### gap-filling ----------------------------------------------------------------

lst_fill <- foreach(i = list(lst[[1]][[1]], lst[[2]][[1]], lst[[1]][[2]], lst[[2]][[2]]), 
                    j = list(lst[[2]][[1]], lst[[1]][[1]], lst[[2]][[2]], lst[[1]][[2]]), 
                    .packages = c("raster", "foreach")) %dopar% {
                      
  dir_fill <- paste0(dirname(attr(i[[1]], "file")@name), "/gf")
  if (!dir.exists(dir_fill)) dir.create(dir_fill)
  
  fls_fill <- paste0(dir_fill, "/", names(i), ".tif")
  
  if (all(file.exists(fls_fill))) {
    raster::stack(fls_fill)
  } else {                      
    
    mat_resp <- raster::as.matrix(i)
    mat_pred <- raster::as.matrix(j)

    mat_fill <- foreach(k = 1:nrow(mat_resp), .combine = "rbind") %do% {
      dat <- data.frame(y = mat_resp[k, ], x = mat_pred[k, ])
      
      if (sum(complete.cases(dat)) >= (.2 * nrow(dat))) {
        mod <- lm(y ~ x, data = dat)
        
        id <- which(!is.na(dat$x) & is.na(dat$y))
        newdata <- data.frame(x = dat$x[id])
        dat$y[id] <- predict(mod, newdata)
      }
      
      return(dat$y)
    }
                        
    rst_fill <- raster::setValues(i, mat_fill)
    
    lst_fill <- foreach(i = 1:ncol(mat_resp), .packages = "raster") %dopar%
      raster::writeRaster(rst_fill[[i]], filename = fls_fill[i], 
                          format = "GTiff", overwrite = TRUE)
    
    raster::stack(lst_fill)
  }
}


### combined products ----------------------------------------------------------

dir_cmb <- "data/MCD09Q1.006"
if (!dir.exists(dir_cmb)) dir.create(dir_cmb)

## ndvi
fls_cmb_ndvi <- gsub("MOD09Q1", "MCD09Q1", names(lst_fill[[1]]))
fls_cmb_ndvi <- gsub("NDVI_", "", fls_cmb_ndvi)
dir_cmb_ndvi <- paste0(dir_cmb, "/ndvi")
if (!dir.exists(dir_cmb_ndvi)) dir.create(dir_cmb_ndvi)

rst_ndvi_cmb <- overlay(lst_fill[[1]], lst_fill[[2]], 
                        fun = function(...) max(..., na.rm = TRUE), 
                        unstack = TRUE, filename = paste0(dir_cmb_ndvi, "/NDVI"), 
                        bylayer = TRUE, suffix = fls_cmb_ndvi, format = "GTiff", 
                        overwrite = TRUE)

## savi
fls_cmb_savi <- gsub("MOD09Q1", "MCD09Q1", names(lst_fill[[3]]))
fls_cmb_savi <- gsub("SAVI_", "", fls_cmb_savi)
dir_cmb_savi <- paste0(dir_cmb, "/savi")
if (!dir.exists(dir_cmb_savi)) dir.create(dir_cmb_savi)

rst_savi_cmb <- overlay(lst_fill[[3]], lst_fill[[4]], 
                        fun = function(...) max(..., na.rm = TRUE), 
                        unstack = TRUE, filename = paste0(dir_cmb_savi, "/SAVI"), 
                        bylayer = TRUE, suffix = fls_cmb_savi, format = "GTiff", 
                        overwrite = TRUE)

## deregister parallel backend
stopCluster(cl)
  