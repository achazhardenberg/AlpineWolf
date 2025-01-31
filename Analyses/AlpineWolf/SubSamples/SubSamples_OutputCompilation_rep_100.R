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
library(MetBrewer)


## ------ SET REQUIRED WORKING DIRECTORIES ------
source("workingDirectories.R")


## ------ SOURCE CUSTOM FUNCTIONS ------
sourceDirectory(path = file.path(getwd(),"Source"), modifiedOnly = F)
#sourceCpp(file = file.path(getwd(),"Source/cpp/GetDensity.cpp"))
#sourceCpp(file = file.path(getwd(),"Source/cpp/GetSpaceUse.cpp"))


## -----------------------------------------------------------------------------
## ------ 0. SET ANALYSIS CHARACTERISTICS -----
## MODEL NAME 
modelName = "AlpineWolf.SubSample.rep_100"
thisDir <- file.path(analysisDir, modelName)

sex <- c("female","male")
status <- c("alpha","pup","other")
HabCov <- c("Bare Rocks","Herbaceous", "Forest","Pop","Wolf presence")
DetCov <- c("Transects_L", "Transect_Exp", "Snow", "East/West", "Log Pop")

myCols <- matrix(met.brewer(name = "Isfahan1", n = 8, type = "discrete")[c(2:4,7:5)],
                 nrow = 3, ncol = 2, byrow = F)
myCols2 <- matrix(met.brewer(name = "Pissaro", n = 7, type = "discrete")[c(1:2,4,5:6)],
                  nrow = 5, ncol = 1, byrow = F)


## -----------------------------------------------------------------------------
## ------   1. PROCESS OUTPUTS -----
load(file.path(thisDir, "parm.df.RData"))

inFiles <- list.files(path.IN)
outFiles <- list.files(path.OUT)[grep("NimbleOutFOR", list.files(path.OUT))]
ref <- expand.grid(list(G = c(F,T), H = c(F,T), A = c(F,T)))
for(s in 1:nrow(parm.df)){
  parm.df$scenario[s] <- which(ref$G == parm.df$Grouping[s] &
                                 ref$H == parm.df$Heterogeneity[s] &
                                 ref$A == parm.df$Adaptive[s])
}#s


## PROCESS OUTPUTS
myParams <- c("N","psi","sexRatio")

myResults <- list()
for(p in 1:length(myParams)){
  myResults[[p]] <- parm.df
  myResults[[p]]$mean <- rep(NA, nrow(parm.df))
  myResults[[p]]$lci <- rep(NA, nrow(parm.df))
  myResults[[p]]$uci <- rep(NA, nrow(parm.df))
  myResults[[p]]$sd <- rep(NA, nrow(parm.df))
  myResults[[p]]$CV <- rep(NA, nrow(parm.df))
  myResults[[p]]$Rhat <- rep(NA, nrow(parm.df))
}#p

n.rep <- max(parm.df$rep_ID)
n.set <- max(parm.df$set_ID)
for(s in 1:n.set){
  repCount <- 0
  for(r in 1:n.rep){
    fileName <- paste0("proc_NimbleOutFORNimbleInFile_Set",s,"_Rep",r,".RData")
    if(fileName %in% outFiles){
      load(file.path(path.OUT, fileName))
      if(all(na.omit(unlist(nimOutput$Rhat)) <= 1.1) & !is.na(any(unlist(nimOutput$Rhat) > 1.1)) ){
        repCount <- repCount + 1
        for(p in 1:length(myParams)){
          myResults[[p]]$mean[myResults[[p]]$set_ID == s & 
                                myResults[[p]]$rep_ID == r] <- nimOutput$mean[[myParams[p]]]
          myResults[[p]]$lci[myResults[[p]]$set_ID == s &
                               myResults[[p]]$rep_ID == r] <- nimOutput$q2.5[[myParams[p]]]
          myResults[[p]]$uci[myResults[[p]]$set_ID == s &
                               myResults[[p]]$rep_ID == r] <- nimOutput$q97.5[[myParams[p]]]
          myResults[[p]]$sd[myResults[[p]]$set_ID == s &
                              myResults[[p]]$rep_ID == r] <- nimOutput$sd[[myParams[p]]]
          myResults[[p]]$CV[myResults[[p]]$set_ID == s &
                              myResults[[p]]$rep_ID == r] <- nimOutput$sd[[myParams[p]]]/nimOutput$mean[[myParams[p]]]
          myResults[[p]]$Rhat[myResults[[p]]$set_ID == s &
                                myResults[[p]]$rep_ID == r] <- nimOutput$Rhat[[myParams[p]]]
          
        }#p
      }
    }#if
  }#r
  print(paste0("Set: ", s, " == ", repCount, " repetitions"))
}#s
save(myResults, file = file.path(thisDir, "results.RData"))



## -----------------------------------------------------------------------------
## ------   8. PLOT RESULTS -----
load(file.path(thisDir, "parm.df.RData"))
load(file.path(thisDir, "results.RData"))

## PLOTS N
{ 
  graphics.off()
  pdf(file = file.path(thisDir, "results_N.pdf"),
      width = 15, height = 8)
  
  species <- unique(parm.df$species)
  scenarios <- 1:8
  valNoise <- seq(-0.35,0.35, length.out = 8)
  par(mfrow = c(1,2))
  
  ## RELATIVE BIAS
  for(se in c("high", "low")){
    ylim <- 0.5
    plot(1,1, xlim = c(0.5,3.5), ylim = c(-ylim,ylim),
         type = "n", xaxt = "n", main = se,
         ylab = "RB(N)", xlab = "", axes = F)
    axis(1, at = 1:3, labels = c("Chamois","Red Deer", "Wild boar"))
    axis(2,
         at = seq(-ylim,ylim,length.out = 5),
         labels = seq(-ylim,ylim,length.out = 5))
    polygon(x = c(1.5,1.5,2.5,2.5),
            y = c(-ylim,ylim,ylim,-ylim),
            border = F, col = adjustcolor("gray80", alpha.f = 0.2))
    abline(h = 0, lty = 2, lwd = 2)
    abline(v = 1.5, lty = 2, lwd = 1)
    abline(v = 2.5, lty = 2, lwd = 1)
    
    p <- 1
    for(sp in 1:length(species)){
      for(sc in scenarios){
        temp <- myResults[[p]][myResults[[p]]$species == species[sp] &
                                 myResults[[p]]$scenario == sc  &
                                 myResults[[p]]$searchEffort == se, ]
        try(plot.violins2( dat.list = list(na.omit((temp$mean - temp$sim.N)/temp$sim.N)),
                           x = sp + valNoise[sc],
                           at = sp + valNoise[sc],
                           add = T,
                           col = myCols[sc],
                           violin.width = 0.05,
                           alpha = 0.9,
                           border.col = myCols[sc],
                           scale.width = F), silent = F)
      }#sc
    }#sp
  }#se
  legend(x = 2.8, y = ylim,
         legend = c("m0", "G", "H", "GH", "A", "GA", "HA", "GHA"),
         fill = colors)
  
  
  ## COEFFICIENT OF VARIATION
  for(se in c("high", "low")){
    ylim <- 0.15
    plot(1,1, xlim = c(0.5,3.5), ylim = c(0,ylim),
         type = "n", xaxt = "n", main = se,
         ylab = "CV(N)", xlab = "", axes = F)
    axis(1, at = 1:3, labels = c("Chamois","Red Deer", "Wild boar"))
    axis(2,
         at = seq(0,ylim,length.out = 5),
         labels = seq(0,ylim,length.out = 5))
    polygon(x = c(1.5,1.5,2.5,2.5),
            y = c(-ylim,ylim,ylim,-ylim),
            border = F, col = adjustcolor("gray80", alpha.f = 0.2))
    abline(v = 1.5, lty = 2, lwd = 1)
    abline(v = 2.5, lty = 2, lwd = 1)
    for(sp in 1:length(species)){
      for(sc in scenarios){
        temp <- myResults[[p]][myResults[[p]]$species == species[sp] &
                                 myResults[[p]]$scenario == sc &
                                 myResults[[p]]$searchEffort == se,  ]
        try(plot.violins2( dat.list = list(na.omit(temp$CV)),
                           x = sp + valNoise[sc],
                           at = sp + valNoise[sc],
                           add = T,
                           col = myCols[sc],
                           violin.width = 0.05,
                           alpha = 0.9,
                           border.col = myCols[sc],
                           scale.width = F), silent = F)
      }#sc
    }#sp
  }#se
  legend(x = 2.8, y = ylim,
         legend = c("m0", "G", "H", "GH", "A", "GA", "HA", "GHA"),
         fill = colors)
  
  ## COVERAGE
  for(se in c("high", "low")){
    ylim <- 1
    plot(1,1, xlim = c(0.5,3.5), ylim = c(0,ylim),
         type = "n", xaxt = "n", main = se,
         ylab = "95%CI coverage", xlab = "", axes = F)
    axis(1, at = 1:3, labels = c("Chamois","Red Deer", "Wild boar"))
    axis(2,
         at = seq(0,ylim,length.out = 5),
         labels = seq(0,ylim,length.out = 5))
    polygon(x = c(1.5,1.5,2.5,2.5),
            y = c(-ylim,ylim,ylim,-ylim),
            border = F, col = adjustcolor("gray80", alpha.f = 0.2))
    abline(h = 0.95, lty = 2, lwd = 2)
    abline(v = 1.5, lty = 2, lwd = 1)
    abline(v = 2.5, lty = 2, lwd = 1)
    for(sp in 1:length(species)){
      for(sc in scenarios){
        temp <- myResults[[p]][myResults[[p]]$species == species[sp] &
                                 myResults[[p]]$scenario == sc &
                                 myResults[[p]]$searchEffort == se, ]
        
        coverage <- mean(temp$lci <= temp$sim.N & temp$uci >= temp$sim.N, na.rm =T)
        try(points( y = coverage,
                    x = sp + valNoise[sc],
                    pch = 21, cex = 2,
                    bg = colors[sc],
                    col = myCols[sc]), silent = F)
      }#sc
    }#sp
  }#se
  legend(x = 0.5, y = 0.35,
         legend = c("m0", "G", "H", "GH", "A", "GA", "HA", "GHA"),
         fill = colors)
  
  graphics.off()
}

## PLOTS Sex Ratio
{ 
  graphics.off()
  pdf(file = file.path(thisDir, "results_SR.pdf"), width = 15, height = 8)
  
  species <- unique(parm.df$species)
  scenarios <- 1:8
  valNoise <- seq(-0.35,0.35, length.out = 8)
  par(mfrow = c(1,2))
  
  ## RELATIVE BIAS
  for(se in c("high", "low")){
    ylim <- 0.5
    plot(1,1, xlim = c(0.5,3.5), ylim = c(-ylim,ylim),
         type = "n", xaxt = "n", main = se,
         ylab = "RB(Sex Ratio)", xlab = "", axes = F)
    axis(1, at = 1:3, labels = c("Chamois","Red Deer", "Wild boar"))
    axis(2,
         at = seq(-ylim,ylim,length.out = 5),
         labels = seq(-ylim,ylim,length.out = 5))
    polygon(x = c(1.5,1.5,2.5,2.5),
            y = c(-ylim,ylim,ylim,-ylim),
            border = F, col = adjustcolor("gray80", alpha.f = 0.1))
    abline(h = 0, lty = 2, lwd = 2)
    abline(v = 1.5, lty = 2, lwd = 1)
    abline(v = 2.5, lty = 2, lwd = 1)
    p <- 3
    for(sp in 1:length(species)){
      for(sc in scenarios){
        temp <- myResults[[p]][myResults[[p]]$species == species[sp] &
                                 myResults[[p]]$scenario == sc  &
                                 myResults[[p]]$searchEffort == se, ]
        try(plot.violins2( dat.list = list(na.omit((temp$mean - temp$sim.SR)/temp$sim.SR)),
                           x = sp + valNoise[sc],
                           at = sp + valNoise[sc],
                           add = T,
                           col = myCols[sc],
                           violin.width = 0.05,
                           alpha = 0.9,
                           border.col = myCols[sc],
                           scale.width = F), silent = F)
      }#sc
    }#sp
  }#se
  legend(x = 2.8, y = ylim,
         legend = c("m0", "G", "H", "GH", "A", "GA", "HA", "GHA"),
         fill = colors)
  
  
  ## COEFFICIENT OF VARIATION
  for(se in c("high", "low")){
    ylim <- 0.15
    plot(1,1, xlim = c(0.5,3.5), ylim = c(0,ylim),
         type = "n", xaxt = "n", main = se,
         ylab = "CV(N)", xlab = "", axes = F)
    axis(1, at = 1:3, labels = c("Chamois","Red Deer", "Wild boar"))
    axis(2,
         at = seq(0,ylim,length.out = 5),
         labels = seq(0,ylim,length.out = 5))
    polygon(x = c(1.5,1.5,2.5,2.5),
            y = c(-ylim,ylim,ylim,-ylim),
            border = F, col = adjustcolor("gray80", alpha.f = 0.1))
    abline(v = 1.5, lty = 2, lwd = 1)
    abline(v = 2.5, lty = 2, lwd = 1)
    for(sp in 1:length(species)){
      for(sc in scenarios){
        temp <- myResults[[p]][myResults[[p]]$species == species[sp] &
                                 myResults[[p]]$scenario == sc &
                                 myResults[[p]]$searchEffort == se,  ]
        try(plot.violins2( dat.list = list(na.omit(temp$CV)),
                           x = sp + valNoise[sc],
                           at = sp + valNoise[sc],
                           add = T,
                           col = myCols[sc],
                           violin.width = 0.05,
                           alpha = 0.9,
                           border.col = myCols[sc],
                           scale.width = F), silent = F)
      }#sc
    }#sp
  }#se
  legend(x = 3, y = ylim,
         legend = c("m0", "G", "H", "GH", "A", "GA", "HA", "GHA"),
         fill = colors)
  
  ## COVERAGE
  for(se in c("high", "low")){
    ylim <- 1
    plot(1,1, xlim = c(0.5,3.5), ylim = c(0,ylim),
         type = "n", xaxt = "n", main = se,
         ylab = "95%CI coverage", xlab = "", axes = F)
    axis(1, at = 1:3, labels = c("Chamois","Red Deer", "Wild boar"))
    axis(2,
         at = seq(0,ylim,length.out = 5),
         labels = seq(0,ylim,length.out = 5))
    polygon(x = c(1.5,1.5,2.5,2.5),
            y = c(-ylim,ylim,ylim,-ylim),
            border = F, col = adjustcolor("gray80", alpha.f = 0.1))
    abline(h = 0.95, lty = 2, lwd = 2)
    abline(v = 1.5, lty = 2, lwd = 1)
    abline(v = 2.5, lty = 2, lwd = 1)
    for(sp in 1:length(species)){
      for(sc in scenarios){
        temp <- myResults[[p]][myResults[[p]]$species == species[sp] &
                                 myResults[[p]]$scenario == sc &
                                 myResults[[p]]$searchEffort == se, ]
        
        coverage <- mean(temp$lci <= temp$sim.SR & temp$uci >= temp$sim.SR, na.rm = T)
        try(points( y = coverage,
                    x = sp + valNoise[sc],
                    pch = 21, cex = 2,
                    bg = colors[sc],
                    col = myCols[sc]), silent = F)
      }#sc
    }#sp
  }#se
  legend(x = 0.5, y = 0.35,
         legend = c("m0", "G", "H", "GH", "A", "GA", "HA", "GHA"),
         fill = colors)
  
  graphics.off()
}



## -----------------------------------------------------------------------------
