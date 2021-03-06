##load data
load("example_DEC_EC.RData")


##
##data_count: transcripts data
##cd: condition label
##




##fitting DESeq model on raw data(unnormalized)
library(DESeq2)
coldata = matrix(0,nrow = length(cd), ncol =1) ##cd is the condition label
colnames(coldata) = "cd"
coldata[,1] = factor(cd)
cd = factor(cd)
dds <- DESeqDataSetFromMatrix(countData = data_count_raw,
                              colData = coldata,
                              design= ~ cd)
dds$cd <- factor(dds$cd, 
                 levels = c(1,2))
dds <- DESeq(dds)
res <- DESeq2::results(dds)
De_dd = which(res$padj < 0.05)
length(De_dd) ## number of DE genes under 5% FDR

##fitting MAST
library(MAST)
library(data.table)
freq_expressed <- 0.2  ##set parameters to default value in MAST paper
FCTHRESHOLD <- log2(1.5)
ngeneon <- apply(data_count,2,function(x) length(which(x>0)))
cd_ <- cd
cdata <- data.frame(conditions=cd_,ngeneon=1:length(cd)) ##convert to data frame as required input of MAST
fdata <- data.frame(gene=factor(1:nrow(data_count)))
MNZ10 <- FromMatrix(log(data_count + 1),cdata,fdata)

cond<-factor(colData(MNZ10)$conditions)
colData(MNZ10)$condition<-cond
cdr2 <-colSums(assay(MNZ10)>0)
colData(MNZ10)$cngeneson <- scale(cdr2)
zlmCond <- zlm(~condition + cngeneson, MNZ10)
summaryCond <- summary(zlmCond, doLRT='condition2') 


summaryDt <- summaryCond$datatable
fcHurdle <- merge(summaryDt[contrast=='condition2' & component=='H',.(primerid, `Pr(>Chisq)`)], #hurdle P values
                  summaryDt[contrast=='condition2' & component=='logFC', .(primerid, coef, ci.hi, ci.lo)], by='primerid') 

fcHurdle[,fdr:=p.adjust(`Pr(>Chisq)`, 'fdr')]
fcHurdleSig <- merge(fcHurdle[fdr<.05 & abs(coef)> 0], as.data.table(mcols(MNZ10)), by='primerid')

Mp = fcHurdle$`Pr(>Chisq)`
id = fcHurdle$primerid
id = gsub("Gene","",id)
id = as.numeric(id)
ord = order(id)

Mp = Mp[ord]

length(which(fcHurdle$fdr < 0.05))

EDDM = as.numeric(fcHurdleSig$gene)
EDDM = which(Mp < 0.05)


###fitting SCDD
library(scDD)
##default prior parameter
prior_param=list(alpha=0.01, mu0=0, s0=0.01, a0=0.01, b0=0.01)
condition = factor(cd)
X =  SingleCellExperiment(assays = list(normcounts = data_count), 
                          colData = data.frame(condition))

X_scDD <- scDD(X, prior_param=prior_param, testZeroes=T)
RES = scDD::results(X_scDD)
p_sc = RES$combined.pvalue.adj
EDD_dz = which(p_sc < 0.05)
DDc = RES$DDcategory ##classify DD genes into category but unable to incorporate with p-value
length(EDD_dz)

###fitting SCDDBoost1
library(scDDboost)
D_c = cal_D(data_count, 10) ##calculate distance matrix using 10 cores
hp = c(1, rep(1,nrow(data_count))) ## set default hyper parameter of EBSeq to be 1
gcl = 1:nrow(data_count) ##gene cluster are set to be each gene form one cluster
sz = MedianNorm(data_count) ##size factor in EBSeq
K = 5 ##number of subtypes 
Posp = pat(K)[[1]] ##possible partitions

###generate refinement relation of partitions, number of cluster from 2 to 8
ref = list()
for(K in 2:8){
    ref[[K]] = g_ref(pat(K)[[1]])
}

##iter: number of iteration in EM algorithm in EBSeq, typically converge in 5 times
##nrandom: number of randomized distance matrices, typically PDD get stable when average on 100 randomized PDD.
pdd5 = PDD(data_count,cd, ncores = 10,K, D_c, sz, hp, pat(K)[[1]],iter = 10, random = T, lambda = 1, nrandom = 100)
EDDb = which(pdd5 > 0.95)



###get probability of DD or DE under each method
##EDD_sc refer to DD genes identified by scDD
##De_dd refer to DE genes identified by DESeq2
##EDDM refer to DE genes identified by MAST
##EDDb refer to DD genes identified by scDDboost



##figure 5
##significant DD genes identified by our approach
##CAMK2D:9745, SRP54:4464, C15orf63:15157
##MRPL20:3555, PTBP1:16824, TDP2:8004
tran = list()
J = 6
p_cur = c(9745,4464,15157,3555,16824,8004)
for(i in 1:J){
  tran[[i]] = data_count[p_cur[i],]
}
cur_rn = rn[p_cur]

cond_ind = c(rep("1", length(which(cd ==1))),
             rep("2", length(which(cd==2))))

cur_rn = factor(cur_rn, levels = cur_rn)
df = data.frame(x = rep(cond_ind, J), y = log(do.call(c, tran) + 1), z = rep(cur_rn, each = length(cd)))


pdf("density_G48_dd.pdf")

pp<-ggplot(df,aes(factor(x),y))+ geom_violin(aes(colour = factor(x))) + geom_point(size = 0.1,position = position_jitter(w = 0.05, h = 0)) +
  xlab("conditions") + 
  ylab("gene expressions")+
  theme(panel.background = element_rect(
    fill = 'white', colour = 'black'),
    axis.title.x=element_blank(),
    axis.text.x=element_blank(),
    axis.title.y=element_blank(),
    legend.title=element_blank(),
    panel.grid.minor.x = element_line(size = 0.5),
    panel.grid.minor.y = element_line(size = 0.5),
    panel.grid.major.x = element_line(size = 0.5),
    panel.grid.major.y = element_line(size = 0.5),
    panel.grid.major = element_line(colour = "grey"))
pp + facet_wrap( ~ z, ncol = 2)
dev.off()

###FDR boxplot
##based on previous experiments on random splitting one condition data into groups and count number of false postive.
deseq_tasic = c(1775, 1703, 1886, 1708, 1695) / 24057
deseq_chu = c(1878,1668,1776,1911,1692,
1699,1872,1900,1874,1836) / 19037
deseq_c = 2841 / 16579
deseq = c(1875, 1793, 2146, 1990, 1956, 2183, 2482, 2179,
2140, 2364, 1329, 1357, 1459, 1440, 944, 3481,
3419, 3483, 3521, 2845, 1419, 1465, 1130, 1065,
1393, 15,66,25,54,70 ) / 45686

deseq = c(deseq,deseq_c,deseq_tasic, deseq_chu)
mast = rep(0, length(deseq))
mast[1] = 2821/45686
mast[2] = mast[1]
mast[3] = 3/45686
mast[4] = 12/45686

scd = rep(0,length(deseq))

scdb = scd

scdb[1:6] = c(60, 60, 12, 5, 20, 1) /45686

df_fdr = data.frame(methods = rep(c("DESeq2", "MAST", "scDD", "scDDboost"),each = length(mast)),
y = c(deseq, mast, scd, scdb))

p = ggplot(df_fdr,aes(methods,y, color = methods)) + geom_boxplot(alpha = 0.7,
outlier.colour = "#1F3552", outlier.shape = 20) + geom_jitter()
pdf("fdr.pdf")
p + theme(panel.background = element_rect(
fill = 'white', colour = 'black'),
axis.text.x = element_text( color="black",
size= 14),
axis.text.y = element_text(face="bold", color="#993333",
size=14),
legend.text=element_text(size = 14),
legend.title = element_blank(),
axis.title.x=element_blank(),
axis.title=element_text(size=14,face="bold"),
panel.grid.minor.x = element_line(size = 0.5),
panel.grid.minor.y = element_line(size = 0.5),
panel.grid.major.x = element_line(size = 0.5),
panel.grid.major.y = element_line(size = 0.5),
panel.grid.major = element_line(colour = "grey"))+ ylab("FDR")

dev.off()
