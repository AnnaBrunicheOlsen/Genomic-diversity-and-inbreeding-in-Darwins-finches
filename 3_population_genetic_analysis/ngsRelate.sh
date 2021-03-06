#!/bin/sh

#PBS -N NSGrelate
#PBS -q fnrwhale
#PBS -l nodes=1:ppn=10,naccesspolicy=singleuser
#PBS -l walltime=300:00:00
#PBS -m abe

module purge
module load bioinfo
module load gsl
module load zlib
module load gcc
module load samtools

cd $PBS_O_WORKDIR

export PATH=/home/abruenic/angsd/:$PATH
export PATH=/home/abruenic/angsd/misc/:$PATH
export PATH=/home/abruenic/NgsRelate/:$PATH

#https://github.com/ANGSD/NgsRelate 

# make bam.filelist
ls *.bam > bam.filelist

#cp /scratch/snyder/a/abruenic/Darwins_finches/ref.fa* .

# First we generate a file with allele frequencies (angsdput.mafs.gz) and a file
# with genotype likelihoods (angsdput.glf.gz).
angsd -b bam.filelist -gl 2 -domajorminor 1 -snp_pval 1e-6 -domaf 1 -minmaf 0.05 \
-doGlf 3 -minMapQ 30 -minQ 20 -setMinDepth 3 -doFasta 2 -doCounts 1 -nThreads 10

# Then we extract the frequency column from the allele frequency file and 
# remove the header (to make it in the format NgsRelate needs)
zcat angsdput.mafs.gz | cut -f5 |sed 1d > freq

# get number of individuals 
LINE="$(wc -l < bam.filelist)"

### run NgsRelate
ngsRelate -g angsdput.glf.gz -n $LINE -f freq -p 10 -O newres

# END
