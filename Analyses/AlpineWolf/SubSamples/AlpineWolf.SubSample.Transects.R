###############################################################################
##### ----------------------- ALPINE WOLF SCR ---------------------------- #####
##### ----------------- s[CLC + HumPop + Zone] --------------------------- #####
##### ---------------- z[psi,rho,theta] ---------------------------------- #####
##### ---------------- y[p0(transects + zone + ),sigma] ------------------ #####
################################################################################
## ------ CLEAN THE WORK ENVIRONMENT ------
rm(list=ls())


## ------ IMPORT REQUIRED LIBRARIES ------
library(rgdal)
library(raster)
library(coda)
library(nimble)
library(nimbleSCR)
library(stringr)
library(abind)
library(R.utils)
library(sf)
library(fasterize)
library(dplyr)
library(lubridate)
library(stars)
library(RANN)
library(Rcpp)
library(RcppArmadillo)
library(RcppProgress)
library(gridExtra)
library(purrr)


## ------ SET REQUIRED WORKING DIRECTORIES ------
source("workingDirectories.R")


## ------ SOURCE CUSTOM FUNCTIONS ------
sourceDirectory(path = file.path(getwd(),"Source"), modifiedOnly = F)
sourceCpp(file = file.path(getwd(),"Source/cpp/GetDensity.cpp"))
sourceCpp(file = file.path(getwd(),"Source/cpp/GetSpaceUse.cpp"))


## -----------------------------------------------------------------------------
## ------ 0. SET ANALYSIS CHARACTERISTICS -----
## MODEL NAME 
modelName = "AlpineWolf.SubSample.Transects"
thisDir <- file.path(analysisDir, modelName)

## HABITAT SPECIFICATIONS
habitat = list( resolution = 5000, 
                buffer = 30000)

## DETECTORS SPECIFICATIONS
detectors = list( resolution = 5000,
                  detSubResolution = 1000,
                  samplingMonths = c(10:12,1:4))

## NGS DATA SPECIFICATIONS
data = list( sex = c("F","M"),
             status = c("alpha","pup","other"),
             aug.factor = 6) 

if(is.null(modelName))stop("YOU SHOULD PROBABLY CHOOSE A NAME FOR THIS ANALYSIS/MODEL")
if(!dir.exists(thisDir)){dir.create(thisDir)}
if(!dir.exists(file.path(thisDir, "input"))){dir.create(file.path(thisDir, "input"))}
if(!dir.exists(file.path(thisDir, "output"))){dir.create(file.path(thisDir, "output"))}



## -----------------------------------------------------------------------------
## ------ I. LOAD & CLEAN DATA ------
## ------   1. STUDY AREA ------


## ------   2. SEARCH EFFORT DATA ------
##---- Load GPS search transects
transects <- read_sf(file.path(dataDir,"GISData/Transects_Wolfalps20202021/paths_completeness/paths_completeness.shp"))
trans <- read_sf(file.path(dataDir,"GISData/Transects_Wolfalps20202021/transects_wolfalps_2020-2021.shp"))
# trans <- st_cast(trans,  "LINESTRING")
##---- Convert dates
transects$Date <- parse_date_time(transects$date, orders = c('ymd'))
transects$Year <- as.numeric(format(transects$Date,"%Y"))
transects$Month <- as.numeric(format(transects$Date,"%m"))
# 
# ##---- Plot check
# plot(transects, col = "red", add = T)



## ------   3. PRE-PROCESSED STUFF ------ 
load(file.path(thisDir,"Habitat.RData"))
load(file.path(thisDir,"Detectors.RData"))

detectors$grid <- detectors$grid[,-(3:6)]

## -----------------------------------------------------------------------------
## ------ II. PREPARE SCR DATA ------
## ------   1. RESCALE HABITAT & DETECTORS ------
##---- Rescale habitat and detector coordinates
scaledCoords <- scaleCoordsToHabitatGrid(
  coordsData = detectors$coords,
  coordsHabitatGridCenter = habitat$coords)

detectors$scaledCoords <- scaledCoords$coordsDataScaled
habitat$scaledCoords <- scaledCoords$coordsHabitatGridCenterScaled
habitat$loScaledCoords <- habitat$scaledCoords - 0.5
habitat$upScaledCoords <- habitat$scaledCoords + 0.5

##---- Identify local detectors
localObjects <- getLocalObjects(
  habitatMask = habitat$binary,
  coords = scaledCoords$coordsDataScaled[ ,1:2],
  dmax = 25)





## ------   2. DNA DATA ------
##---- All collected NGS samples
# allSamples <- read_sf(file.path(dataDir,"GISData/scats/merged_scats.shp"))
# plot(st_geometry(studyArea))
# plot(st_geometry(countries), col = "gray80",add=T)
# plot(allSamples, add = T,pch=3)

##---- Genotyped NGS samples
ngs <- read.csv(file.path(dataDir,"DNA/ngs21032022.csv"))
dim(ngs)


##---- Use lubridate to clean dates
# The orders argument is a character vector containing the possible date-time parsing 
# formats in the order they should be tested. So by giving c('dmy', 'ymd'), lubridate 
# will try to parse all strings as Day, Month, Year format. If it can't do that 
# successfully (for example, the date 2021-03-18 won't work as there is no 2021th day), 
# it will try the next in the list until all strings are parsed, or all orders exhausted.
ngs$Date <- parse_date_time(ngs$Date, orders = c('dmy','mdy','ymd'))
ngs$Year <- as.numeric(format(ngs$Date,"%Y"))
ngs$Month <- as.numeric(format(ngs$Date,"%m"))

##---- Filter out samples from 2019
ngs <- ngs[ngs$Year > 2019, ]
dim(ngs)

##---- Filter out dead recoveries
ngs <- ngs[ngs$Dead.recovery == "", ]
dim(ngs)

##---- Filter out opportunistic samples
ngs_opp <- ngs[!ngs$Type.of.sample == "Scat", ]

##---- To be added later
ngs <- ngs[ngs$Type.of.sample == "Scat", ]
dim(ngs)


##---- Turn ngs into spatial data frame
coordinates(ngs) <- cbind.data.frame(ngs$CoordX, ngs$CoordY)
proj4string(ngs) <- "+proj=utm +zone=32 +datum=WGS84 +units=m +no_defs"
ngs <- st_as_sf(ngs)

coordinates(ngs_opp) <- cbind.data.frame(ngs_opp$CoordX, ngs_opp$CoordY)
proj4string(ngs_opp) <- "+proj=utm +zone=32 +datum=WGS84 +units=m +no_defs"
ngs_opp <- st_as_sf(ngs_opp)

##---- Number of detections per individual
# numDetsPerId <- table(ngs$Genotype.ID)
# hist(numDetsPerId)
# 
# ##---- Number of individuals detected
# length(numDetsPerId)
# 
# ##---- Mean number of detections per ID
# mean(numDetsPerId)
# 
# ##---- Number of individuals with > 1 detection
# sum(numDetsPerId > 1)
# 
# ##---- mean number of individual detections by sex
# table(ngs$Sex, useNA = "always")
# apply(table(ngs$Genotype.ID, ngs$Sex, useNA = "always"),
#       2,
#       function(x)sum(x)/sum(x>0))
# 
# ##---- mean number of individual detections by status
# ngs$Status[ngs$Status == "pup 2016"] <- "pup"
# ngs$Status[ngs$Status == "pup 2017"] <- "pup"
# table(ngs$Status, useNA = "always")
# apply(table(ngs$Genotype.ID, ngs$Status, useNA = "always"),
#       2,
#       function(x)sum(x)/sum(x>0))
# 
# ##---- mean number of individual detections by sex and status
# apply(table(ngs$Genotype.ID, ngs$Status, ngs$Sex, useNA = "always"),
#       c(2,3),
#       function(x)sum(x)/sum(x>0))

## ------   3. DETECTION DATA ------
## ------     3.1. DETECTION MATRIX : y ------
##---- Calculate distance between detections and detectors

closest <- nn2( coordinates(detectors$sub.sp),
                st_coordinates(ngs),
                k = 1,
                searchtype = "radius",
                radius = 10000)


closest_opp <- nn2( coordinates(detectors$sub.sp),
                    st_coordinates(ngs_opp),
                    k = 1,
                    searchtype = "radius",
                    radius = 10000)

##---- Assign each detection to a detector based on minimum distance
ngs$sub.detector <- c(closest$nn.idx)
ngs$detector <- detectors$sub.sp$main.cell.new.id[closest$nn.idx] 

ngs_opp$sub.detector <- c(closest_opp$nn.idx)
ngs_opp$detector <- detectors$sub.sp$main.cell.new.id[closest_opp$nn.idx] 

# main.cell.id <- detectors$sub.sp$main.cell.new.id[closest$nn.idx]     
# ngs$detector <- unlist(
#   lapply(1:length(main.cell.id), function(x){
#     out <- NA
#     if(!is.na(main.cell.id[x]))out <- which(detectors$sp$main.cell.new.id %in% main.cell.id[x])
#     return(out)
#   }))
# all(ngs$detector==main.cell.id)


# ngs <- as.data.frame(ngs)

for (rep in 1:10) {
  

trans25 <- trans %>% 
  sample_frac(0.25) %>% 
  st_buffer(., dist = 500)

  
trans50 <- trans %>% 
    sample_frac(0.50)  %>% 
  st_buffer(., dist = 500)

  
trans75 <- trans %>% 
    sample_frac(0.75)  %>% 
    st_buffer(., dist = 500)
  


##---- Extract road length in each detector grid cell
ngs25 <- st_filter(ngs, trans25)
ngs50 <- st_filter(ngs, trans50)
ngs75 <- st_filter(ngs, trans75)


ngs25 <- rbind(ngs25,ngs_opp)
ngs50 <- rbind(ngs50,ngs_opp)
ngs75 <- rbind(ngs75,ngs_opp)

##---- Extract length and number of transects in each grid cell

ids_25 <- Reduce(intersect, list(trans25$ID_APP,  transects$transect_i))
transects25 <- subset(transects, transect_i  %in% ids_25)

detectors25 <- detectors

intersection25 <- st_intersection(detectors25$grid, transects25) %>%
  mutate(LEN = st_length(.),
          QI = .$Q.index) %>%
  st_drop_geometry() %>%
  group_by(id) %>%
  summarise(transect_L25 = sum(LEN),               ## Get total length searched in each detector grid cell
            transect_N25 = length(unique(Date)),   ## Get total number of visits in each detector grid cell
            transect_qi25 = mean(QI))              ## Get mean transects quality index for each detector grid cell
  
##---- Store in detector grid
detectors25$grid <- detectors25$grid %>%
  left_join(intersection25, by = "id")
detectors25$grid$transect_L25[is.na(detectors25$grid$transect_L25)] <- 0
detectors25$grid$transect_N25[is.na(detectors25$grid$transect_N25)] <- 1
detectors25$grid$transect_qi25[is.na(detectors25$grid$transect_qi25)] <- 0
detectors25$grid$transect_L25 <- scale(detectors25$grid$transect_L25)
detectors25$grid$mean_transect_L25 <- scale(detectors25$grid$transect_L25/detectors25$grid$transect_N25)



##----

detectors50 <- detectors


ids_50 <- Reduce(intersect, list(trans50$ID_APP,  transects$transect_i))
transects50 <- subset(transects, transect_i  %in% ids_50)

intersection50 <- st_intersection(detectors50$grid, transects50) %>%
  mutate(LEN = st_length(.),
         QI = .$Q.index) %>%
  st_drop_geometry() %>%
  group_by(id) %>%
  summarise(transect_L50 = sum(LEN),               ## Get total length searched in each detector grid cell
            transect_N50 = length(unique(Date)),   ## Get total number of visits in each detector grid cell
            transect_qi50 = mean(QI))              ## Get mean transects quality index for each detector grid cell

##---- Store in detector grid

detectors50$grid <- detectors25$grid %>%
  left_join(intersection50, by = "id")
detectors50$grid$transect_L50[is.na(detectors50$grid$transect_L50)] <- 0
detectors50$grid$transect_N50[is.na(detectors50$grid$transect_N50)] <- 1
detectors50$grid$transect_qi50[is.na(detectors50$grid$transect_qi50)] <- 0
detectors50$grid$transect_L50 <- scale(detectors50$grid$transect_L50)
detectors50$grid$mean_transect_L50 <- scale(detectors50$grid$transect_L50/detectors50$grid$transect_N50)


##----

detectors75 <- detectors


ids_75 <- Reduce(intersect, list(trans75$ID_APP,  transects$transect_i))
transects75 <- subset(transects, transect_i  %in% ids_75)


intersection75 <- st_intersection(detectors75$grid, transects75) %>%
  mutate(LEN = st_length(.),
         QI = .$Q.index) %>%
  st_drop_geometry() %>%
  group_by(id) %>%
  summarise(transect_L75 = sum(LEN),               ## Get total length searched in each detector grid cell
            transect_N75 = length(unique(Date)),   ## Get total number of visits in each detector grid cell
            transect_qi75 = mean(QI))              ## Get mean transects quality index for each detector grid cell

##---- Store in detector grid

detectors75$grid <- detectors75$grid %>%
  left_join(intersection75, by = "id")
detectors75$grid$transect_L75[is.na(detectors75$grid$transect_L75)] <- 0
detectors75$grid$transect_N75[is.na(detectors75$grid$transect_N75)] <- 1
detectors75$grid$transect_qi75[is.na(detectors75$grid$transect_qi75)] <- 0
detectors75$grid$transect_L75 <- scale(detectors75$grid$transect_L75)
detectors75$grid$mean_transect_L75 <- scale(detectors75$grid$transect_L75/detectors75$grid$transect_N75)



  
  
ngs25 <- as.data.frame(ngs25)
ngs50 <- as.data.frame(ngs50)
ngs75 <- as.data.frame(ngs75)
  
  
##---- Drop duplicated detections ate the same sub-detectors
  ngs25 <- ngs25[!duplicated(ngs25[ ,c("sub.detector", "Genotype.ID")]), ]
  ngs25 <- droplevels(ngs25)
  
  ngs50 <- ngs50[!duplicated(ngs50[ ,c("sub.detector", "Genotype.ID")]), ]
  ngs50 <- droplevels(ngs50)
  
  ngs75 <- ngs75[!duplicated(ngs75[ ,c("sub.detector", "Genotype.ID")]), ]
  ngs75 <- droplevels(ngs75)
  
  ##---- Count individual detections per detector
  detMat25 <- as.matrix(table(ngs25[ , c("Genotype.ID", "detector")]))
  detMat50 <- as.matrix(table(ngs50[ , c("Genotype.ID", "detector")]))
  detMat75 <- as.matrix(table(ngs75[ , c("Genotype.ID", "detector")]))
  
# ##---- Convert to binary detections (might keep later for binomial model)
# detMat[detMat > 0] <- 1
  
##---- Retrieve the number of detectors at which each individual is detected
  detNums25 <- apply(detMat25, 1, function(x) sum(x>0))
  detNums50 <- apply(detMat50, 1, function(x) sum(x>0))
  detNums75 <- apply(detMat75, 1, function(x) sum(x>0))
  
##--- Set-up matrices to store individual detection frequencies and indices
  n.detected25 <- dim(detMat25)[1]
  detIndices25 <- matrix(-1, n.detected25, max(detNums25)*2)
  ySparse25 <- matrix(-1, n.detected25, max(detNums25)*2)
  
  n.detected50 <- dim(detMat50)[1]
  detIndices50 <- matrix(-1, n.detected50, max(detNums50)*2)
  ySparse50 <- matrix(-1, n.detected50, max(detNums50)*2)
  
  n.detected75 <- dim(detMat75)[1]
  detIndices75 <- matrix(-1, n.detected75, max(detNums75)*2)
  ySparse75 <- matrix(-1, n.detected75, max(detNums75)*2)
  
##---- Fill in the matrix
  for(i in 1:n.detected25){
    ##-- Get where detections occur (detectors index)
    detIndices25[i,1:detNums25[i]] <- as.numeric(names(which(detMat25[i, ] > 0)))
    ##-- Get detection frequencies (always 1 in case of Bernoulli) 
    ySparse25[i,1:detNums25[i]] <- detMat25[i,which(detMat25[i, ] > 0)]
  }
  
  
  for(i in 1:n.detected50){
    ##-- Get where detections occur (detectors index)
    detIndices50[i,1:detNums50[i]] <- as.numeric(names(which(detMat50[i, ] > 0)))
    ##-- Get detection frequencies (always 1 in case of Bernoulli) 
    ySparse50[i,1:detNums50[i]] <- detMat50[i,which(detMat50[i, ] > 0)]
  }
  
  
  for(i in 1:n.detected75){
    ##-- Get where detections occur (detectors index)
    detIndices75[i,1:detNums75[i]] <- as.numeric(names(which(detMat75[i, ] > 0)))
    ##-- Get detection frequencies (always 1 in case of Bernoulli) 
    ySparse75[i,1:detNums75[i]] <- detMat75[i,which(detMat75[i, ] > 0)]
  }
  
  
  
  ##---- Combine individual detection number, frequencies and indices
  yCombined25 <- cbind(detNums25, ySparse25, detIndices25)
  
  yCombined50 <- cbind(detNums50, ySparse50, detIndices50)
  
  yCombined75 <- cbind(detNums75, ySparse75, detIndices75)
  
  
  ## ------     3.2. INDIVIDUAL COVARIATES ------
  ##---- List detected indivdual names
  
  IDs25 <- dimnames(yCombined25)[[1]]
  IDs50 <- dimnames(yCombined50)[[1]]
  IDs75 <- dimnames(yCombined75)[[1]]
  
  ##---- Set-up vectors to store individual covariates
  
  sex25 <- status25 <- pack25 <- rep(NA, length(IDs25))
  for(i in 1:length(IDs25)){
    ##-- Sex 
    temp25 <- unique(ngs25$Sex[ngs25$Genotype.ID %in% IDs25[i]])
    if(length(temp25)>1)warning(print(paste("ID:", IDs25[i], " sex:", temp25)))
    sex25[i] <- ifelse(length(temp25>1),temp25[1],temp25)
    
    ##- Social status
    temp25 <- unique(ngs25$Status[ngs25$Genotype.ID %in% IDs25[i]])
    if(length(temp25)>1){
      #warning(print(paste("ID:", IDs25[i], " status:", temp25)))
      if(any(temp25 %in% "na")){
        status25[i] <- temp25[!(temp25 =="na")]
      }else{
        status25[i] <- NA
      }
    } else {
      status25[i] <- temp25
    }
    
    
    ##-- Pack membership
    temp25 <- unique(ngs25$Pack[ngs25$Genotype.ID %in% IDs25[i]])
    if(any(temp25 %in% "dispersal")){
      status25[i] <- "dispersal"
    }
  }
  
  
  
  sex50 <- status50 <- pack50 <- rep(NA, length(IDs50))
  for(i in 1:length(IDs50)){
    ##-- Sex 
    temp50 <- unique(ngs50$Sex[ngs50$Genotype.ID %in% IDs50[i]])
    if(length(temp50)>1)warning(print(paste("ID:", IDs50[i], " sex:", temp50)))
    sex50[i] <- ifelse(length(temp50>1),temp50[1],temp50)
    
    ##- Social status
    temp50 <- unique(ngs50$Status[ngs50$Genotype.ID %in% IDs50[i]])
    if(length(temp50)>1){
      #warning(print(paste("ID:", IDs50[i], " status:", temp50)))
      if(any(temp50 %in% "na")){
        status50[i] <- temp50[!(temp50 =="na")]
      }else{
        status50[i] <- NA
      }
    } else {
      status50[i] <- temp50
    }
    
    ##-- Pack membership
    temp50 <- unique(ngs50$Pack[ngs50$Genotype.ID %in% IDs50[i]])
    if(any(temp50 %in% "dispersal")){
      status50[i] <- "dispersal"
    }
  }
  
  
  
  sex75 <- status75 <- pack75 <- rep(NA, length(IDs75))
  for(i in 1:length(IDs75)){
    ##-- Sex 
    temp75 <- unique(ngs75$Sex[ngs75$Genotype.ID %in% IDs75[i]])
    if(length(temp75)>1)warning(print(paste("ID:", IDs75[i], " sex:", temp75)))
    sex75[i] <- ifelse(length(temp75>1),temp75[1],temp75)
    
    ##- Social status
    temp75 <- unique(ngs75$Status[ngs75$Genotype.ID %in% IDs75[i]])
    if(length(temp75)>1){
      #warning(print(paste("ID:", IDs75[i], " status:", temp75)))
      if(any(temp75 %in% "na")){
        status75[i] <- temp75[!(temp75 =="na")]
      }else{
        status50[i] <- NA
      }
    } else {
      status75[i] <- temp75
    }
    
    ##-- Pack membership
    temp75 <- unique(ngs75$Pack[ngs75$Genotype.ID %in% IDs75[i]])
    if(any(temp75 %in% "dispersal")){
      status75[i] <- "dispersal"
    }
  }
  
  ##----- Convert to numerical values 
  # ----
  
  sex25[sex25 == "F"] <- 0
  sex25[sex25 == "M"] <- 1
  sex25[sex25 == ""] <- NA
  sex25 <- as.numeric(sex25)
  
  status25[status25 == "alpha"] <- 1
  status25[status25 == "pup"] <- 2
  status25[status25 == "other"] <- 3
  status25[status25 == "dispersal"] <- 3
  status25[status25 == ""] <- NA
  status25 <- as.numeric(status25)
  
  ##----
  sex50[sex50 == "F"] <- 0
  sex50[sex50 == "M"] <- 1
  sex50[sex50 == ""] <- NA
  sex50 <- as.numeric(sex50)
  
  status50[status50 == "alpha"] <- 1
  status50[status50 == "pup"] <- 2
  status50[status50 == "other"] <- 3
  status50[status50 == "dispersal"] <- 3
  status50[status50 == ""] <- NA
  status50 <- as.numeric(status50)
  
  ##----
  sex75[sex75 == "F"] <- 0
  sex75[sex75 == "M"] <- 1
  sex75[sex75 == ""] <- NA
  sex75 <- as.numeric(sex75)
  
  status75[status75 == "alpha"] <- 1
  status75[status75 == "pup"] <- 2
  status75[status75 == "other"] <- 3
  status75[status75 == "dispersal"] <- 3
  status75[status75 == ""] <- NA
  status75 <- as.numeric(status75)
  
  
  
  ## ------     3.3. DATA AUGMENTATION ------
  
  
  yCombined.aug25 <- MakeAugmentation( y = yCombined25,
                                       M = 4000,
                                       replace.value = 0)
  
  sex.aug25 <- MakeAugmentation( y = sex25,
                                 M = 4000,
                                 replace.value = NA)
  
  status.aug25 <- MakeAugmentation( y = status25,
                                    M = 4000,
                                    replace.value = NA)
  
  ## ---
  
  yCombined.aug50 <- MakeAugmentation( y = yCombined50,
                                       M = 4000,
                                       replace.value = 0)
  
  sex.aug50 <- MakeAugmentation( y = sex50,
                                 M = 4000,
                                 replace.value = NA)
  
  status.aug50 <- MakeAugmentation( y = status50,
                                    M = 4000,
                                    replace.value = NA)
  
  
  ## ---
  
  yCombined.aug75 <- MakeAugmentation( y = yCombined75,
                                       M = 4000,
                                       replace.value = 0)
  
  sex.aug75 <- MakeAugmentation( y = sex75,
                                 M = 4000,
                                 replace.value = NA)
  
  status.aug75 <- MakeAugmentation( y = status75,
                                    M = 4000,
                                    replace.value = NA)
  
  
  
  ## -----------------------------------------------------------------------------
  ## ------ III. NIMBLE ------- 
  ## ------   1. MODEL ------
  
  modelCode <- nimbleCode({
    ##---- SPATIAL PROCESS  
    for(c in 1:n.habCovs){
      betaHab[c] ~ dnorm(0.0,0.01)
    }#c
    habIntensity[1:n.habWindows] <- exp(
      hab.covs[1:n.habWindows,1:n.habCovs] %*% betaHab[1:n.habCovs])
    
    sumHabIntensity <- sum(habIntensity[1:n.habWindows])
    logHabIntensity[1:n.habWindows] <- log(habIntensity[1:n.habWindows])
    logSumHabIntensity <- log(sumHabIntensity)
    
    for(i in 1:n.individuals){
      s[i,1:2] ~ dbernppAC(
        lowerCoords = lowerHabCoords[1:n.habWindows,1:2],
        upperCoords = upperHabCoords[1:n.habWindows,1:2],
        logIntensities = logHabIntensity[1:n.habWindows],
        logSumIntensity = logSumHabIntensity,
        habitatGrid = habitatGrid2[1:y.max,1:x.max],
        numGridRows = y.max,
        numGridCols = x.max)
    }#i
    
    
    ##---- DEMOGRAPHIC PROCESS  
    psi ~ dunif(0,1)
    rho ~ dunif(0,1)
    
    for(ss in 1:2){
      theta[1:n.states,ss] ~ ddirch(alpha[1:n.states,ss])
    }#ss
    
    for(i in 1:n.individuals){ 
      sex[i] ~ dbern(rho)
      z[i] ~ dbern(psi)
      status[i] ~ dcat(theta[1:n.states,sex[i]+1])
    }#i 								
    
    
    ##---- DETECTION PROCESS 
    for(c in 1:n.detCovs){
      betaDet[c] ~ dnorm(0.0,0.01)
    }
    
    for(s in 1:n.states){
      for(ss in 1:2){
        p0[s,ss] ~ dunif(0,0.5)
        sigma[s,ss] ~ dunif(0,20)
        logit(p0Traps[s,ss,1:n.detectors]) <- logit(p0[s,ss]) + 
          det.covs[1:n.detectors,1:n.detCovs] %*% betaDet[1:n.detCovs]
      }#ss
    }#s
    
    for(i in 1:n.individuals){
      y[i,1:n.maxDets] ~ dbinomLocal_normal(
        size = size[1:n.detectors],
        p0Traps = p0Traps[status[i],sex[i]+1,1:n.detectors],
        sigma = sigma[status[i],sex[i]+1],
        s = s[i,1:2],
        trapCoords = detCoords[1:n.detectors,1:2],
        localTrapsIndices = localTrapsIndices[1:n.habWindows,1:n.localIndicesMax],
        localTrapsNum = localTrapsNum[1:n.habWindows],
        habitatGrid = habitatGrid[1:y.max,1:x.max],
        indicator = z[i],
        lengthYCombined = n.maxDets)
    }#i
    
    
    ##-- DERIVED PARAMETERS 
    N <- sum(z[1:n.individuals])
  })
  
  
  
## ------   2. BUNDLE DATA ------
##---- Set model constants, data & parameter simulated values (==inits)
  
nimData25 <- list( y = yCombined.aug25,
                     z = c(rep(1,n.detected25),
                           rep(NA,dim(yCombined.aug25)[1]-n.detected25)),
                     sex = sex.aug25,
                     status = status.aug25,
                     alpha = matrix(1,3,2),
                     lowerHabCoords = habitat$loScaledCoords, 
                     upperHabCoords = habitat$upScaledCoords, 
                     hab.covs = cbind.data.frame(
                       "bare rock" = habitat$grid$`bare rock`,
                       "herbaceous" = habitat$grid$`herbaceous`,
                       "forest" = habitat$grid$`forest`,
                       "pop" = habitat$grid$pop,
                       "IUCN" = habitat$grid$`IUCN`),
                     det.covs = cbind.data.frame(
                       "transect_L" = detectors25$grid$transect_L25,
                       "transect_qi" = detectors25$grid$transect_qi25,
                       "snow_fall" = detectors25$grid$`snow_fall`,
                       "zone" = detectors25$grid$`zone`,
                       "log_pop" = detectors25$grid$`log_pop`),
                     size = detectors25$size,
                     detCoords = detectors25$scaledCoords,
                     localTrapsIndices = localObjects$localIndices,
                     localTrapsNum = localObjects$numLocalIndices,
                     habitatGrid2 = habitat$matrix,
                     habitatGrid = localObjects$habitatGrid)
  
  
nimConstants25 <- list( n.individuals = nrow(nimData25$y),
                          n.maxDets = ncol(nimData25$y),
                          n.habWindows = habitat$n.HabWindows,
                          n.detectors = detectors25$n.detectors, 
                          n.habCovs = ncol(nimData25$hab.covs),
                          n.detCovs = ncol(nimData25$det.covs),
                          n.states = 3,
                          n.localIndicesMax = localObjects$numLocalIndicesMax,
                          y.max = dim(habitat$matrix)[1],
                          x.max = dim(habitat$matrix)[2])
  
  
  
nimData50 <- list( y = yCombined.aug50,
                     z = c(rep(1,n.detected50),
                           rep(NA,dim(yCombined.aug50)[1]-n.detected50)),
                     sex = sex.aug50,
                     status = status.aug50,
                     alpha = matrix(1,3,2),
                     lowerHabCoords = habitat$loScaledCoords, 
                     upperHabCoords = habitat$upScaledCoords, 
                     hab.covs = cbind.data.frame(
                       "bare rock" = habitat$grid$`bare rock`,
                       "herbaceous" = habitat$grid$`herbaceous`,
                       "forest" = habitat$grid$`forest`,
                       "pop" = habitat$grid$pop,
                       "IUCN" = habitat$grid$`IUCN`),
                     det.covs = cbind.data.frame(
                       "transect_L" = detectors50$grid$`transect_L50`,
                       "transect_qi" = detectors50$grid$`transect_qi50`,
                       "snow_fall" = detectors50$grid$`snow_fall`,
                       "zone" = detectors50$grid$`zone`,
                       "log_pop" = detectors50$grid$`log_pop`),
                     size = detectors50$size,
                     detCoords = detectors50$scaledCoords,
                     localTrapsIndices = localObjects$localIndices,
                     localTrapsNum = localObjects$numLocalIndices,
                     habitatGrid2 = habitat$matrix,
                     habitatGrid = localObjects$habitatGrid)
  
  
nimConstants50 <- list( n.individuals = nrow(nimData50$y),
                          n.maxDets = ncol(nimData50$y),
                          n.habWindows = habitat$n.HabWindows,
                          n.detectors = detectors50$n.detectors, 
                          n.habCovs = ncol(nimData50$hab.covs),
                          n.detCovs = ncol(nimData50$det.covs),
                          n.states = 3,
                          n.localIndicesMax = localObjects$numLocalIndicesMax,
                          y.max = dim(habitat$matrix)[1],
                          x.max = dim(habitat$matrix)[2])
  
  
  
  
  
nimData75 <- list( y = yCombined.aug75,
                     z = c(rep(1,n.detected75),
                           rep(NA,dim(yCombined.aug75)[1]-n.detected75)),
                     sex = sex.aug75,
                     status = status.aug75,
                     alpha = matrix(1,3,2),
                     lowerHabCoords = habitat$loScaledCoords, 
                     upperHabCoords = habitat$upScaledCoords, 
                     hab.covs = cbind.data.frame(
                       "bare rock" = habitat$grid$`bare rock`,
                       "herbaceous" = habitat$grid$`herbaceous`,
                       "forest" = habitat$grid$`forest`,
                       "pop" = habitat$grid$pop,
                       "IUCN" = habitat$grid$`IUCN`),
                     det.covs = cbind.data.frame(
                       "transect_L" = detectors75$grid$`transect_L75`,
                       "transect_qi" = detectors75$grid$`transect_qi75`,
                       "snow_fall" = detectors75$grid$`snow_fall`,
                       "zone" = detectors75$grid$`zone`,
                       "log_pop" = detectors75$grid$`log_pop`),
                     size = detectors75$size,
                     detCoords = detectors75$scaledCoords,
                     localTrapsIndices = localObjects$localIndices,
                     localTrapsNum = localObjects$numLocalIndices,
                     habitatGrid2 = habitat$matrix,
                     habitatGrid = localObjects$habitatGrid)
  
  
nimConstants75 <- list( n.individuals = nrow(nimData75$y),
                          n.maxDets = ncol(nimData75$y),
                          n.habWindows = habitat$n.HabWindows,
                          n.detectors = detectors75$n.detectors, 
                          n.habCovs = ncol(nimData75$hab.covs),
                          n.detCovs = ncol(nimData75$det.covs),
                          n.states = 3,
                          n.localIndicesMax = localObjects$numLocalIndicesMax,
                          y.max = dim(habitat$matrix)[1],
                          x.max = dim(habitat$matrix)[2])
  
nimParams <- c("N", "p0", "sigma", "psi",
                 "betaDet", "betaHab", "theta", "rho",
                 "z", "s", "status", "sex")
  
  
  
## ------   3. SAVE THE INPUT ------
  for(c in 1:4){
    s.init25 <- matrix(NA, nimConstants25$n.individuals, 2)
    for(i in 1:n.detected25){
      if(detNums25[i] > 1){
        s.init25[i, ] <- colMeans(detectors$scaledCoords[detIndices25[i,1:detNums25[i]], ])
      } else {
        s.init25[i, ] <- detectors$scaledCoords[detIndices25[i,1:detNums25[i]], ] + rnorm(2,0,0.1)
      }
    }#i
    for(i in (n.detected25 + 1):nimConstants25$n.individuals){
      s.init25[i, ] <- rbernppAC( n = 1,
                                  lowerCoords = nimData25$lowerHabCoords,
                                  upperCoords = nimData25$upperHabCoords,
                                  logIntensities = log(rep(1,habitat$n.HabWindows)),
                                  logSumIntensity = log(sum(rep(1,habitat$n.HabWindows))),
                                  habitatGrid = nimData25$habitatGrid,
                                  numGridRows = nrow(nimData25$habitatGrid),
                                  numGridCols = ncol(nimData25$habitatGrid))
    }#i
    
    sex.init25 <- rbinom(n = nimConstants25$n.individuals, 1, prob = 0.5)
    sex.init25[!is.na(nimData25$sex)] <- NA
    sex1.init25 <- sex.init25 + 1
    
    status.init25 <- rcat(n = nimConstants25$n.individuals, prob = c(0.5,0.45,0.05))
    status.init25[!is.na(nimData25$status)] <- NA
    
    z.init25 <- rbinom(n = nimConstants25$n.individuals, 1, prob = 0.1)
    z.init25[!is.na(nimData25$z)] <- NA
    
    nimInits25 <- list( "s" = s.init25,
                        "z" = z.init25,
                        "sex" = sex.init25,
                        "status" = status.init25,
                        "psi" = 0.5,
                        "rho" = 0.5,
                        "theta" = cbind(c(0.5,0.45,0.05),
                                        c(0.5,0.3,0.2)),
                        "betaDet" = rep(0,nimConstants25$n.detCovs),
                        "betaHab" = rep(0,nimConstants25$n.habCovs),
                        "p0" = cbind(c(0.1,0.1,0.05),
                                     c(0.1,0.1,0.05)),
                        "sigma" = cbind(c(1,1,2),
                                        c(1,1,2)))
    
    nimData <- nimData25
    nimConstants<- nimConstants25
    nimInits <- nimInits25
    
    save( modelCode,
          nimData,
          nimConstants,
          nimInits,
          nimParams,
          file = file.path(thisDir, "input25",
                           paste0(modelName, "_25_", rep,  "_", c,  "rep.RData")))
    
  }
  
  for(c in 1:4){
    s.init50 <- matrix(NA, nimConstants50$n.individuals, 2)
    for(i in 1:n.detected50){
      if(detNums50[i] > 1){
        s.init50[i, ] <- colMeans(detectors$scaledCoords[detIndices50[i,1:detNums50[i]], ])
      } else {
        s.init50[i, ] <- detectors$scaledCoords[detIndices50[i,1:detNums50[i]], ] + rnorm(2,0,0.1)
      }
    }#i
    for(i in (n.detected50 + 1):nimConstants50$n.individuals){
      s.init50[i, ] <- rbernppAC( n = 1,
                                  lowerCoords = nimData50$lowerHabCoords,
                                  upperCoords = nimData50$upperHabCoords,
                                  logIntensities = log(rep(1,habitat$n.HabWindows)),
                                  logSumIntensity = log(sum(rep(1,habitat$n.HabWindows))),
                                  habitatGrid = nimData50$habitatGrid,
                                  numGridRows = nrow(nimData50$habitatGrid),
                                  numGridCols = ncol(nimData50$habitatGrid))
    }#i
    
    
    sex.init50 <- rbinom(n = nimConstants50$n.individuals, 1, prob = 0.5)
    sex.init50[!is.na(nimData50$sex)] <- NA
    sex1.init50 <- sex.init50 + 1
    
    status.init50 <- rcat(n = nimConstants50$n.individuals, prob = c(0.5,0.45,0.05))
    status.init50[!is.na(nimData50$status)] <- NA
    
    z.init50 <- rbinom(n = nimConstants50$n.individuals, 1, prob = 0.1)
    z.init50[!is.na(nimData50$z)] <- NA
    
    nimInits50 <- list( "s" = s.init50,
                        "z" = z.init50,
                        "sex" = sex.init50,
                        "status" = status.init50,
                        "psi" = 0.5,
                        "rho" = 0.5,
                        "theta" = cbind(c(0.5,0.45,0.05),
                                        c(0.5,0.3,0.2)),
                        "betaDet" = rep(0,nimConstants50$n.detCovs),
                        "betaHab" = rep(0,nimConstants50$n.habCovs),
                        "p0" = cbind(c(0.1,0.1,0.05),
                                     c(0.1,0.1,0.05)),
                        "sigma" = cbind(c(1,1,2),
                                        c(1,1,2)))
    
    
    nimData <- nimData50
    nimConstants<- nimConstants50
    nimInits <- nimInits50
    
    save(  modelCode,
           nimData,
           nimConstants,
           nimInits,
           nimParams,
           file = file.path(thisDir, "input50",
                            paste0(modelName, "_50_", rep, "_", c,  "rep.RData")))
    
    
  }  
  
  for(c in 1:4){
    s.init75 <- matrix(NA, nimConstants75$n.individuals, 2)
    for(i in 1:n.detected75){
      if(detNums75[i] > 1){
        s.init75[i, ] <- colMeans(detectors$scaledCoords[detIndices75[i,1:detNums75[i]], ])
      } else {
        s.init75[i, ] <- detectors$scaledCoords[detIndices75[i,1:detNums75[i]], ] + rnorm(2,0,0.1)
      }
    }#i
    for(i in (n.detected75 + 1):nimConstants75$n.individuals){
      s.init75[i, ] <- rbernppAC( n = 1,
                                  lowerCoords = nimData75$lowerHabCoords,
                                  upperCoords = nimData75$upperHabCoords,
                                  logIntensities = log(rep(1,habitat$n.HabWindows)),
                                  logSumIntensity = log(sum(rep(1,habitat$n.HabWindows))),
                                  habitatGrid = nimData75$habitatGrid,
                                  numGridRows = nrow(nimData75$habitatGrid),
                                  numGridCols = ncol(nimData75$habitatGrid))
    }#i
    
    
    
    
    
    sex.init75 <- rbinom(n = nimConstants75$n.individuals, 1, prob = 0.5)
    sex.init75[!is.na(nimData75$sex)] <- NA
    sex.init75 <- sex.init75 + 1
    
    status.init75 <- rcat(n = nimConstants75$n.individuals, prob = c(0.5,0.45,0.05))
    status.init75[!is.na(nimData75$status)] <- NA
    
    z.init75 <- rbinom(n = nimConstants75$n.individuals, 1, prob = 0.1)
    z.init75[!is.na(nimData75$z)] <- NA
    
    nimInits75 <- list( "s" = s.init75,
                        "z" = z.init75,
                        "sex" = sex.init75,
                        "status" = status.init75,
                        "psi" = 0.5,
                        "rho" = 0.5,
                        "theta" = cbind(c(0.5,0.45,0.05),
                                        c(0.5,0.3,0.2)),
                        "betaDet" = rep(0,nimConstants75$n.detCovs),
                        "betaHab" = rep(0,nimConstants75$n.habCovs),
                        "p0" = cbind(c(0.1,0.1,0.05),
                                     c(0.1,0.1,0.05)),
                        "sigma" = cbind(c(1,1,2),
                                        c(1,1,2)))
    
    nimData <- nimData75
    nimConstants<- nimConstants75
    nimInits <- nimInits75
    
    save( modelCode,
          nimData,
          nimConstants,
          nimInits,
          nimParams,
          file = file.path(thisDir, "input75", 
                           paste0(modelName, "_75_", rep,"_", c,  "rep.RData")))
    
    
  }
  
  print(rep)

  }









## ------   4. FIT MODEL -----
##---- Create the nimble model object
nimModel <- nimbleModel( code = modelCode,
                         constants = nimConstants,
                         inits = nimInits,
                         data = nimData,
                         check = FALSE,
                         calculate = FALSE) 
nimModel$calculate()

##---- Compile the nimble model object to C++
CsimModel <- compileNimble(nimModel)
CsimModel$calculate()

##---- Configure and compile the MCMC object 
conf <- configureMCMC( model = nimModel,
                       monitors = nimParams,
                       thin = 1)
Rmcmc <- buildMCMC(conf)
compiledList <- compileNimble(list(model = nimModel, mcmc = Rmcmc))
Cmodel <- compiledList$model
Cmcmc <- compiledList$mcmc

##---- Run nimble MCMC in multiple bites
for(c in 1:1){
  print(system.time(
    runMCMCbites( mcmc = Cmcmc,
                  bite.size = 500,
                  bite.number = 2,
                  path = file.path(thisDir, paste0("output/chain",c)))
  ))
}

##---- Collect multiple MCMC bites and chains
nimOutput_noZ <- collectMCMCbites( path = file.path(thisDir, "output"),
                                   burnin = 0,
                                   param.omit = c("s","z","sex","status"))

##---- Traceplots
pdf(file = file.path(thisDir, paste0(modelName, "_traceplots.pdf")))
plot(nimOutput_noZ)
graphics.off()


##---- Process and save MCMC samples
nimOutput <- collectMCMCbites( path = file.path(thisDir, "output"),
                               burnin = 0)
res <- ProcessCodaOutput(nimOutput)

##---- Save processed MCMC samples
save(res, file = file.path(thisDir, paste0(modelName,"_mcmc.RData")))
