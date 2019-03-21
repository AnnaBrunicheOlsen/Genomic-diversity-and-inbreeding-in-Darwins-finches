#!/bin/sh

#PBS -N plink_4x
#PBS -q fnrquail
#PBS -l nodes=1:ppn=1,naccesspolicy=shared
#PBS -l walltime=300:00:00
#PBS -m abe

module purge
module load bioinfo
module load vcflib
module load GATK/3.8.1
module load vcftools

cd $PBS_O_WORKDIR

# plink path
export PATH=/depot/fnrdewoody/apps:$PATH

cat 120_birds.txt | while read -r LINE

do

cd $LINE

##########################
##### call genotypes #####
##########################

# filter vcf file for depth
vcffilter -f "DP > 3" ${LINE}_SNPs.vcf > out.vcf

# divide header and SNPs
grep "#" out.vcf > header.txt
grep -v "#" out.vcf > body.txt

# filter vcf for sequencing errors
grep -v -a '0/1:1,' body.txt > body1.txt
grep -v -a '0/1:*,1:' body1.txt > body2.txt

# count number of columns (10 columns)
#awk '{print NF}' out3.vcf | sort -nu | tail -n 1

# GT info is in column 10
#awk '{print $10}' body2 > hetero

# put the vcf back together
cat header.txt body2.txt > ${LINE}_4x.vcf

# remove intermediate files
rm -rf header.txt
rm -rf body*.txt
rm -rf out.vcf

#########################
##### make map file #####
#########################

vcftools --vcf ${LINE}_4x.vcf --plink --out ${LINE}_4x

# make test file with scaffold info instead of chromosome info
# take column with contig info
awk '{print $2}' ${LINE}_4x.map > scaffold.txt
#split at the first full stop
awk -F'.' '{print $1}' scaffold.txt > scaffold2.txt
paste -d' ' scaffold2.txt ${LINE}_4x.map > test.map
awk '{print $1,$3,$4,$5}' test.map > ${LINE}_4x.map

# remove all intermediate files
rm -rf scaffold*
rm -rf test*

##########################################
###### THIS PART FINDS DEPTH OF COV ######
##########################################

# coverage needs to be included we chose 20x as minimum
# check if the file listing coverage/bp exists
FILE4=$"realigned_reads.sample_cumulative_coverage_counts"

if [ -f $FILE4 ]
then
    echo "$FILE4_exist"
else
	# depht of coverage 
	# to do this copy all the realigned_reads.bam files
	# prob easier to do in individ folders
	GenomeAnalysisTK -T DepthOfCoverage -R /scratch/snyder/a/abruenic/Darwins_finches/ref.fa -o realigned_reads \
	-I realigned_reads_SM.bam
fi

##################################################
###### THIS PART FINDS RUNS-OF-HOMOZYGOSITY ######
##################################################

# min 1KB in length
plink-1.9 --ped ${LINE}_4x.ped --map ${LINE}_4x.map --allow-extra-chr \
--homozyg-snp 20 \
--homozyg-kb 10 --homozyg-window-het 0 --homozyg-window-snp 20 \
--homozyg-window-threshold 0.05 --out ${LINE}_4x

# count number of ROHs, ROHs are in column 9
awk '{print $9}' ${LINE}_4x.hom > ROH.txt

# remove header
tail -n+2 ROH.txt > roh.txt

# count number of ROHs
wc -l roh.txt > rohNumber.txt
rohNumber=$(awk '{print $1}' rohNumber.txt)

# estimate length of ROHs
rohLength=$(awk '{ sum += $1} END {printf "%.2f", sum }' roh.txt)

# number of SNPs in ROHs, SNPs are in column 10
awk '{print $10}' ${LINE}_4x.hom > ROH_SNPs.txt

# remove header
tail -n+2 ROH_SNPs.txt > roh_snps.txt

# estimate number of ROHs
snpNumberROH=$(awk '{ sum += $1} END {printf "%.2f", sum }' roh_snps.txt)

# change name in *.hom files
# this is to make the file ready for R-plots
sed -i "s/sample1/$LINE/g" ${LINE}_4x.hom

# write results to file
cat ${LINE}_4x.hom >> /scratch/snyder/a/abruenic/Darwins_finches/individual_ROHs_4x.txt

############################################
###### THIS PART FINDS HETEROZYGOSITY ######
############################################

# total number of sites at 20x depth of coverage
# replace \t with \n
tr '\t' '\n' < realigned_reads.sample_cumulative_coverage_counts > site_4x.txt
# grep line 508 (gte_4)
sites=$(sed -n '508p' site_4x.txt)

# print to file
echo -e "$PWD\t $sites" \
>> /scratch/snyder/a/abruenic/Darwins_finches/sites_20x_coverage_4x.txt

# count heterozygotes
grep -a '0/1' ${LINE}_4x.vcf > het.txt
het="$(wc -l < het.txt)"

# count homozygotes
grep -a '0/0' ${LINE}_4x.vcf > homo.txt
grep -a '1/1' ${LINE}_4x.vcf >> homo.txt
homo="$(wc -l < homo.txt)"

# total number of SNPs
SNPs=$(($homo + $het)) 

# non-variant sites
bc <<< "($sites - $SNPs)" > non.txt
non=$(sed -n '1p' non.txt)

# heterozygosity
# adjust scale to allow for decimals
bc <<< "scale=9; ($het / $sites)" > hetero.txt
heteroAll=$(sed -n '1p' hetero.txt)

# heterozygosity minus ROH snps
bc <<< "($sites - $snpNumberROH)" > sitesNoRoh.txt
sitesNoRoh=$(sed -n '1p' sitesNoRoh.txt)
bc <<< "scale=9; ($het / $sitesNoRoh)" > hetNoRoh.txt
heteroNoRoh=$(sed -n '1p' hetNoRoh.txt)

# SNPrate
bc <<< "scale=6; ($SNPs / $sites)" > SNPrate.txt
SNPrate=$(sed -n '1p' SNPrate.txt)

# remove excess files
rm -rf *.txt
rm -rf *nosex
rm -rf *log
rm -rf *map
rm -rf *ped
rm -rf *summary
rm -rf *.e*
rm -rf *.o*
rm -rf *.sh
rm -rf *.sam

#echo -e ""PWD"\t "rohNumber"\t "rohLength"\t "snpNumberROH"\t \
#"sites"\t "het"\t "homo"\t "SNPs"\t "non"\t "heteroAll"\t "heteroNoRoh"" \
#>> /scratch/snyder/a/abruenic/Darwins_finches/heterozygosity.txt

# print to file
echo -e "$PWD\t $rohNumber\t $rohLength\t $snpNumberROH\t \
$sites\t $het\t $homo\t $SNPs\t $non\t $heteroAll\t $heteroNoRoh" \
>> /scratch/snyder/a/abruenic/Darwins_finches/heterozygosity_4x.txt

cd ..

done

# END