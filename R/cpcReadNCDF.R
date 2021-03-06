#' Read in CPC Data from File
#'
#' This function allows you to query your customized NCDF files generated by cpcYearToNCDF in an efficient manner with minimal worrying
#' about syntax. In order for these queries to work, you need to first download the relevant data using the \code{cpcYearToNCDF} function
#' for the years you wish to download. This function allows you to read those files, using the same \code{download_folder} parameter.
#' It can return either tidy data or a 3D array.
#' @param start_date the first date of data to extract. Must be a date class object: see \code{lubridate::ymd} for easy generation.
#' @param end_date the last date of data to extract.
#' @param lat_lims a vector of length 2 specifying the minimum and maximum latitudes to query
#' @param lon_lims a vector of length 2 specifying the minimum and maximum longitudes to query
#' @param download_folder the folder containing the \code{.nc} files you wish to read. Should be the same as the \code{download_folder} argument you passed to
#'   \code{cpcYearToNCDF} unless you have moved the files.
#' @param tidy if TRUE, returns the data as a tidy \code{data.table}. If FALSE, returns a 3D array indexed by [lon, lat, time].
#' @param round_lonlat if TRUE, the longitude and latitude limits you enter will be rounded to the nearest valid values. If FALSE, if the values you enter are not
#'   in the data set, this function will throw an error.
#' @return returns either a \code{data.table} with columns date, lon, lat, and prcp_mm or a three-dimensional array indexed [lon, lat, time]. This choice
#'   is controlled by the \code{tidy} argument.
#' @import magrittr
#' @import data.table
#' @export cpcReadNCDF
cpcReadNCDF <- function(start_date, end_date, lat_lims, lon_lims, download_folder = getwd(), tidy = T, round_lonlat = TRUE){
  require(lubridate)
  require(ncdf4)
  require(magrittr)
  require(data.table)

  # ---------- Checks on the Parameters ------

  # check the dates
  if(!(is.Date(start_date) & is.Date(end_date))) stop('start_date and end_date must be date objects. see lubridate package for easy generation')

  # check lims
  if(!(length(lat_lims == 2) & length(lon_lims == 2))) stop('lat_lims and lon_lims must be length 2')
  if(!(min(lat_lims) >= -90 | max(lat_lims) <= 90)) stop('lat_lims must be between -90 and 90')
  if(!(min(lon_lims) >= 0 | max(lat_lims) <= 360)) stop('lon_lims must be between 0 and 360')

  # check download_folder validity
  if(substr(download_folder, nchar(download_folder), nchar(download_folder)) != '/') download_folder <- paste0(download_folder, '/')
  if(!dir.exists(download_folder)) stop('invalid download_folder specified')

  # check if years are available
  years_requested <- year(start_date):year(end_date)
  years_available <- unlist(strsplit(Sys.glob(paste0(download_folder, '*.nc')), '.nc'))
  years_available <- substr(years_available, nchar(years_available) - 3, nchar(years_available)) %>% as.numeric()
  if(!all(years_requested %in% years_available)) stop('Not all years requested are available. Use cpcYearToNCDF to download them first.')

  # global parameters
  global <- cpcGlobal()
  lons <- global$cpcLonVec
  lats <- global$cpcLatVec
  # times depend on year

  # set to nearest grids
  if(!all(lat_lims %in% lats)){
    if(round_lonlat){
      warning('Adjusting lat_lims to nearest grid point')
      lat_lims[1] <- lats[which.min(abs(lats - lat_lims[1]))]
      lat_lims[2] <- lats[which.min(abs(lats - lat_lims[2]))]
    } else{
      stop('Invalid lat_lims parameter.')
    }
  }
  if(!all(lon_lims %in% lons)){
    if(round_lonlat){
      warning('Adjusting lon_lims to nearest grid point')
      lon_lims[1] <- lons[which.min(abs(lons - lon_lims[1]))]
      lon_lims[2] <- lons[which.min(abs(lons - lon_lims[2]))]
    } else {
      stop('Invalid lon_lims parameter')
    }
  }

  # ---------- Read the Data ------

  # initialize
  out_list <- vector('list', length(years_requested))

  # loop through each year separately
  for(i in 1:length(years_requested)){

    # times depend on the year
    times <- seq(ymd(paste(years_requested[i], 1, 1)), ymd(paste(years_requested[i], 12, 31)), 1) %>% as.numeric()

    # set the start and end dates for this particular year
    if(i == 1){ #it's first year
      start_date_i <- start_date
    } else {
      start_date_i <- ymd(paste(years_requested[i], 1, 1))
    }
    if(i == length(years_requested)){ #it's first year
      end_date_i <- end_date
    } else {
      end_date_i <- ymd(paste(years_requested[i], 12, 31))
    }

    year_i <- years_requested[i]
    nc_fn_i <- paste0(download_folder, 'cpcRain_', year_i, '.nc')

    # build the start and count indices
    start <- c(which(lons == min(lon_lims)),
               which(lats == min(lat_lims)),
               min(which(as_date(times) == start_date_i)))
    end <- c(which(lons == max(lon_lims)),
             which(lats == max(lat_lims)),
             max(which(as_date(times) == end_date_i)))
    count <- end - start + 1

    nc <- nc_open(nc_fn_i)

    nc_array <- ncvar_get(nc, varid = 'precip', start = start, count = count)
    dimnames(nc_array)[[1]] <- lons[start[1]:end[1]]
    dimnames(nc_array)[[2]] <- lats[start[2]:end[2]]
    dimnames(nc_array)[[3]] <- times[start[3]:end[3]] %>% lubridate::as_date() %>% as.character()

    # tidy data if tidy == TRUE else leave as array
    if(tidy){
      out_list[[i]] <- cpcMeltArray(nc_array)
    } else {
      out_list[[i]] <- nc_array
    }

  }

  # join the data sets
  if(tidy){
    out_list <- rbindlist(out_list)
  } else {
    out_list <- abind::abind(out_list, along = 3)
  }

  return(out_list)
}
