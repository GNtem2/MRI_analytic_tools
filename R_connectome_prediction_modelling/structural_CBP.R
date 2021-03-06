#########################################################
# "Connectome Prediction Analysis"
# "Raúl Rodríguez-Cruces"
# "8 de septiembre de 2017"
#########################################################
#---------- Uploads Parameters and libraries ----------#
require(corrplot)
source("/home/rr/Dropbox/linuxook/oma/Mica_Fig3/mica_fig3_funciones.R")
rm(bi, iCC_w, iEff_w, iL_w, Mgroup,mtx_full, mtx_log, mtx_norm, mtx_scl, net.info, net.nodes, pK, plot.K)

#---------- Introduction ----------#
# This protocol is based on [Shen et al. 2017](dx.doi.org/10.1038/nprot.2016.178) for connectome prediction. However, it was originaly created for fMRI connectomes and some modifications have been performed in order to adecuate it for **structural connectivity matrices**.  
# NOTE:  
#   > As in the reference paper, the predictive power of the model is assessed via correlation between predicted and observed scores across all subjects.  
# > Note that this assumes normal or near-normal distributions for both vectors, and does not assess absolute accuracy of predictions (only relative accuracy within the sample).  
# > It is recommended to explore *additional/alternative metrics for assessing predictive power*, such as prediction error sum of squares or prediction $r^2$.  

## STEP 1: Inputs uploading ----------#
# Here we upload the connectomes as a $MxMxN$ matrix and the cognitive variable as an $Nx1$ vector, where:  
#   - M = Number of nodes  
# - N = Subjects  
# - B = Behavior  

#The elements $(i,j)$ of each matrix represents the $N_{SIFT}$ weighted structural connection between two nodes for subject $k$.


# Uploads all files
fichier<-read.csv('/home/rr/Escritorio/conx_matrices/Files.csv',header = FALSE)
rois<-read.csv("/home/rr/Escritorio/conx_matrices/atlas_coord.txt",header = FALSE)
colnames(rois)<-c("roi","x","y","z","roi.nom")
# Crea variables vacias
N<-length(fichier[,1])
mtxs<-array(0,dim = c(162,162,N))

# ID of the subjects
lab<-c()

# Reads all matrices
for (i in 1:N){
  tmp<-mtx_load(as.character(fichier[i,1]))
  mtxs[,,i]<-tmp$matrix
  lab<-c(lab,tmp$id)
  print(paste0("Reading files from ",tmp$id))}
rows<-tmp$rows
rm(tmp, i, fichier, N, rows)

# COMPLETE SUBSET with network analysis and cluster class
pc<-"/home/rr/"
cases<-read.csv(paste0(pc,"/Dropbox/linuxook/oma/cases_Zclust.csv"))
cases<-cases[,c(20,1:19)]
cases$pos<-match(cases$urm,as.numeric(lab))
cases<-na.omit(cases)

# Tests if the Clusters are in the same order
a<-cases$pos
as.integer(lab[a])==cases$urm

# MATCH Connectivity matrices with CLASSES
Mtxs <- mtxs[,,a]
no_sub <- dim(Mtxs)[3]
no_node <- dim(Mtxs)[1]
rm(mtxs,pc)

# Behavioral variable Nx1 vector
B<-as.matrix(cases$IMT)

# FUNCTION Logarithm of each Wij
mtx_log <-function(Mtx){
  Mtx <- apply(Mtx,1:2, function(x) if (x != 0) x=log(x) else 0 )
  Mtx[lower.tri(Mtx)] <- t(Mtx)[lower.tri(Mtx)]
  return(Mtx)}
for (i in 1:no_sub) {Mtxs[,,i]<-mtx_log(Mtxs[,,i])}

# FUNCTION Z-score of each Wij based on controls
z.score <- function(mat, Pos){
  n <- dim(Mtxs)[1]
  z.mat <- mat
  for(i in 1:(n-1)){
    for(j in (i+1):n){
      mu <- mean(mat[i,j,Pos])
      sigma <- sd(mat[i,j,Pos])
      z.mat[i,j,] <- z.mat[j,i,] <- (mat[i,j,]-mu)/sigma
    }
  }
  z.mat[is.infinite(z.mat) | z.mat=="NaN"]<-0
  return(z.mat)
}

# Obtaines the position of controls to z-score all values
z.mtx<-z.score(Mtxs,which(cases$GR=="ctrl"))
# Testing matrix
# corrplot(z.mtx[,,1],is.corr = F,tl.col="black",method="color",cl.pos = "r")

# Subgraph


# Threshold for feature selection
thr<- 0.05


## STEP 2: Trainning & Cross validation
#Creates a training group each loop leaving one out.
# **NOTE:** Should we do this only for the patients excluding controls??

# FUNCTION
#--------------------------------------------------
corr_mtx<-function(M,V,Method){ 
  # M= array of matrices MxMxN, # V=Nx1
  # Function that obtains a list of p-values and r-values 
  # from correlating an array of matrices with a vector of behavioral data
  n <- ncol(M)
  Subj<-length(V)
  p.mat <- r.mat <- array(NA,c(n,n))
  
  for (i in 1:(n - 1)) {
    for (j in (i + 1):n) {
      tmp <- cor.test(M[i,j,],V,exact = FALSE,method = Method)
      p.mat[i, j] <- p.mat[j, i] <- tmp$p.value
      r.mat[i, j] <- r.mat[j, i] <- tmp$estimate
    }
  }
  diag(r.mat)<-diag(p.mat)<-0
  # assigns value of 0 if there is no values in the correlation
  r.mat[is.na(r.mat) | r.mat=="NaN"]<-0
  p.mat[is.na(p.mat) | p.mat=="NaN"]<-1
  
  return(list("rho"=r.mat, "p.val"=p.mat))
}
plot.predict <- function(x,y,Col,Lim) {
  source("/home/rr/Dropbox/VolTA/addTrans.R")
  # Confidence Intervals at 95%
  newx <- seq(Lim[1], Lim[2], length.out=20)
  preds <- predict(lm(y~x), newdata = data.frame(x=newx),interval = 'confidence')
  polygon(c(rev(newx), newx), c(rev(preds[ ,3]), preds[ ,2]), col = addTrans(Col,75), border = NA)
}


#M<-mtx.test
M<-z.mtx
D<-dim(M)
pos.mtxs<-array(NA,D)
neg.mtxs<-array(NA,D)

B.pred.pos <- B.pred.neg <- c()
for (i in 1:D[3]){
  print(paste("[INFO]... Running prediction for CBP, leaving one out:",i))
  #------------------------------------------------    
  # STEP 2 - TRAINNING & CROSS VALIDATIONS SUB-GROUPS
  #------------------------------------------------
  # Matrices and vector of behavior for the training k-fold N-1
  train.mats<-M[,,-i]
  train.B<-B[-i]
  
  #------------------------------------------------    
  # STEP 3 - RELATION OF CONNECTIVITY TO BEHAVIOR
  #------------------------------------------------
  # ALTERNATIVE 1: Use SPEARMAN correlation
  # ALTERNATIVE 2: Use PARTIAL CORRELATIONS
  # ALTERNATIVE 3: Use ROBUST REGRESSION for correlating each edge with behavior
  corr<-corr_mtx(train.mats,train.B,"pearson")
  r.mat<-corr$rho
  p.mat<-corr$p.val
  
  #------------------------------------------------    
  # STEP 4 - EDGE SELECTION
  #------------------------------------------------
  pos.m <- p.mat<0.01 & r.mat>0
  pos.m <- apply(pos.m,1:2,function(x) if (x==FALSE) x=0 else x=1)
  
  neg.m <- p.mat<0.01 & r.mat<0
  neg.m <- apply(neg.m,1:2,function(x) if (x==FALSE) x=0 else x=1)
  
  neg.mtxs[,,i] <- neg.m
  pos.mtxs[,,i] <- pos.m
  
  # Testing pearson-r & p-values matrices
  # corrplot(neg.m,is.corr = F,tl.col="black",method="color",cl.pos = "r")
  # corrplot(pos.m,is.corr = F,tl.col="black",method="color",cl.pos = "r")
  #   
  #------------------------------------------------
  # STEP 5 -SINGLE SUBJECT SUMMARY VALUES 
  #------------------------------------------------
  # t.sss = train single subject sum
  t.sss.pos <- t.sss.neg <-c()
  for (j in 1:(no_sub-1)) {
    t.sss.pos <- c(t.sss.pos,sum(train.mats[,,j]*pos.m)/2)
    t.sss.neg <- c(t.sss.neg,sum(train.mats[,,j]*neg.m)/2) }
  
  #------------------------------------------------
  # STEP 6 - MODEL FITTING
  #------------------------------------------------
  # build model on TRAIN subs
  # fit.pos <- lm(train.B~poly(t.sss.pos,degree = 1,raw = T))
  # fit.neg <- lm(train.B~poly(t.sss.neg,degree = 1,raw = T))
  fit.pos <- lm(train.B~t.sss.pos)
  fit.neg <- lm(train.B~t.sss.neg)
  
  # run model on TEST sub
  test.mat <- M[,,i]
  test.sss.pos <- sum(test.mat*pos.m)/2
  test.sss.neg <- sum(test.mat*neg.m)/2
  
  #------------------------------------------------
  # STEP 7 - PREDICTION IN NOVEL SUBJECTS 
  #------------------------------------------------
  B.pred.pos <- c(B.pred.pos, fit.pos$coefficients[2] * test.sss.pos + fit.pos$coefficients[1])
  B.pred.neg <- c(B.pred.neg, fit.neg$coefficients[2] * test.sss.neg + fit.neg$coefficients[1])
  
  #------------------------------------------------
  # PLOTS
  #------------------------------------------------
  # 	par(mfrow=c(1,2))
  #   Lim<-c(min(c(t.sss.neg,t.sss.pos)),	max(c(t.sss.neg,t.sss.pos)))
  #   Col<-c("gray50","midnightblue","red4","orange")[cases$SIDE[-i]]
  #   plot(t.sss.neg,train.B,col=Col,cex=2,pch=20,xlab="Negative SSS",ylab="Behavior",main = paste("Leaving out subject",i),xlim=Lim)
  #   abline(fit.neg,col="blue",lwd=2)
  #   points(test.sss.neg,B[i],cex=2,bg="white",pch=21,col="red4",lwd=4)
  #   points(test.sss.neg,B.pred.neg[i],cex=2,bg="white",pch=21,col="blue",lwd=4.5)
  #   plot.predict(t.sss.neg,train.B,"blue",Lim)
  # 
  #   plot(t.sss.pos,train.B,col=Col,cex=2,pch=20,xlab="Positive SSS",ylab="Behavior",main = paste("Leaving out subject",i),xlim=Lim)
  #   abline(fit.pos,col="red",lwd=2)
  #   points(test.sss.pos,B[i],cex=2,bg="white",pch=21,col="red4",lwd=4)
  #   points(test.sss.pos,B.pred.pos[i],cex=2,bg="white",pch=21,col="red",lwd=4.5)
  #   plot.predict(t.sss.pos,train.B,"red",Lim)
}


## STEP 3: Relation of connectivity and behavior
# This step was done by correlating each **edge** ($W_{ij}$) for all subjects ($EDGE_{ij}$) and the **behavioral measure**.  
# We obtain two matrices whose edges represent the value of the $r$ and the $p-value$ for the correlation of the $EDGE_{ij}$ and the behavior.  
# Alternatives for obtaining the correlation values are:  
#   - *Spearman* correlation  
# - *Partial* correlations  
# - *Robust regression* for correlating each edge with the behavioral measure

## STEP 4: Edge selection  
# Based on the significance of the p-values matrix with an *arbitrary threshold (0.01)*.  
# The threshold is applied over the non corrected-p-values. 
# As an **Alternative** a subselection of the nodes could be performed before this analysis in order to increase sensitivity and decreassed the multiple comparasion problem. This could be seen as an *hypothesis driven approach.*  
   

# Inverse of Student's T cumulative distribution function to obtain r threshold
Th <- qt(thr/2,no_sub-1-2,lower.tail = TRUE)
R <- sqrt(Th^2/(no_sub-1-2+Th^2))
# Weighted mask using a sigmoidal function
sigmf<-function(x,a,c){ y = 1/(1 + exp(-a*(x-c)))
return(y) }
# weight = 0.05, when correlation = R/3
# weight = 0.88, when correlation = R
neg.mask <-pos.mask <- r.mat
pos.mask[pos.mask<0]<-0
neg.mask[neg.mask>0]<-0

pos.mask[pos.mask>0]<-sigmf(r.mat[r.mat>0],3/R,R/3)
neg.mask[neg.mask<0]<-sigmf(r.mat[r.mat<0],-3/R,R/3)
par(mfrow=c(1,2))
corrplot(pos.mask,is.corr = F,tl.col="black",method="color",cl.pos = "r",title = "Positive Sigmoid")
corrplot(neg.mask,is.corr = F,tl.col="black",method="color",cl.pos = "r",title="Negative Sigmoid")


# STEP 5: Single Subject Summay values ($SS\sum$)  
#For each subject in the training set, summarize the selected edges to a single value per subject for the positive edge set and the negative edge set separately

## STEP 8: Evaluation of the predictive model
#------------------------------------------------
# STEP 8 - PREDICTION IN NOVEL SUBJECTS 
#------------------------------------------------
par(mfrow=c(1,2))
mod<-lm(B.pred.pos~B)
plot(B,B.pred.pos,pch=21,bg="white",col="blue",lwd=3,cex=1.5,ylab="Predicted Values",xlab = "True values",main=paste("Positive-corr, slope:",mod$coefficients[2]))
abline(mod,col="blue")

mod<-lm(B.pred.neg~B)
plot(B,B.pred.neg,pch=21,bg="white",col="red",lwd=3,cex=1.5,ylab="Predicted Values",xlab = "True values",main=paste("Negative-corr, slope:",mod$coefficients[2]))
abline(mod,col="red")

corrplot(apply(neg.mtxs,1:2,function(x) sum(x)/no_sub),is.corr = F,tl.col="black",method="color",cl.pos = "r",title = "Binary Negative Selections")
corrplot(apply(pos.mtxs,1:2,function(x) sum(x)/no_sub),is.corr = F,tl.col="black",method="color",cl.pos = "r",title = "Binary Positive Selections")


