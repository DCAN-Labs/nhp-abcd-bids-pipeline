#!/bin/bash
set -e

Subject="$1"
ResultsFolder="$2"
ROIsFolder="$3"
DownSampleFolder="$4"
LevelOnefMRIName="$5"
LevelOnefsfName="$6"
LowResMesh="$7"
GrayordinatesResolution="$8"
OriginalSmoothingFWHM="$9"
Confound="${10}"
FinalSmoothingFWHM="${11}"
TemporalFilter="${12}"
VolumeBasedProcessing="${13}"


TR_vol=`${CARET7DIR}/wb_command -file-information ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas.dtseries.nii -no-map-info -only-step-interval`

#Only do the additional smoothing required to hit the target final smoothing for CIFTI
AdditionalSmoothingFWHM=`echo "sqrt(( $FinalSmoothingFWHM ^ 2 ) - ( $OriginalSmoothingFWHM ^ 2 ))" | bc -l`

AdditionalSigma=`echo "$AdditionalSmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`

SmoothingString="_s${FinalSmoothingFWHM}"
TemporalFilterString="_hp""$TemporalFilter"

FEATDir="${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefsfName}${TemporalFilterString}${SmoothingString}_level1.feat"
if [ -e ${FEATDir} ] ; then
  rm -r ${FEATDir}
  mkdir ${FEATDir}
else
  mkdir -p ${FEATDir}
fi

if [ $TemporalFilter = "200" ] ; then
  #Don't edit the fsf file if the temporal filter is the same
  cp ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefsfName}_hp200_s4_level1.fsf ${FEATDir}/temp.fsf
else
  #Change the highpass filter string to the desired highpass filter
  cat ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefsfName}_hp200_s4_level1.fsf | sed s/"set fmri(paradigm_hp) \"200\""/"set fmri(paradigm_hp) \"${TemporalFilter}\""/g > ${FEATDir}/temp.fsf
fi

#Change smoothing to be equal to additional smoothing in FSF file and change output directory to match total smoothing and highpass
cat ${FEATDir}/temp.fsf | sed s/"set fmri(smooth) \"4\""/"set fmri(smooth) \"${AdditionalSmoothingFWHM}\""/g | sed s/_hp200_s4/${TemporalFilterString}${SmoothingString}/g > ${FEATDir}/design.fsf
rm ${FEATDir}/temp.fsf

#Change number of timepoints to match timeseries so that template fsf files can be used
fsfnpts=`cat ${FEATDir}/design.fsf | grep "set fmri(npts)" | cut -d " " -f 3 | sed 's/"//g'`
CIFTInpts=`${CARET7DIR}/wb_command -nifti-information ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas.dtseries.nii -print-header | grep "^dim\[6\]:" | cut -d " " -f 2`
if [ $fsfnpts -ne $CIFTInpts ] ; then
  cat ${FEATDir}/design.fsf | sed s/"set fmri(npts) \"\?${fsfnpts}\"\?"/"set fmri(npts) ${CIFTInpts}"/g > ${FEATDir}/temp.fsf
  mv ${FEATDir}/temp.fsf ${FEATDir}/design.fsf
  echo "Short Run! Reseting FSF Number of Timepoints (""${fsfnpts}"") to Match CIFTI (""${CIFTInpts}"")"
fi

#Create design files, model confounds if desired
DIR=`pwd`
cd ${FEATDir}
if [ $Confound = "NONE" ] ; then
  feat_model ${FEATDir}/design
else 
  feat_model ${FEATDir}/design ${ResultsFolder}/${LevelOnefMRIName}/${Confound}
fi
cd $DIR

#Prepare files and folders
DesignMatrix=${FEATDir}/design.mat
DesignContrasts=${FEATDir}/design.con
DesignfContrasts=${FEATDir}/design.fts

###Grayordinates Processing###
#Add any additional smoothing
if [ ! $FinalSmoothingFWHM -eq $OriginalSmoothingFWHM ] ; then
  ${CARET7DIR}/wb_command -cifti-smoothing ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas.dtseries.nii ${AdditionalSigma} ${AdditionalSigma} COLUMN ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString".dtseries.nii -left-surface "$DownSampleFolder"/"$Subject".L.midthickness."$LowResMesh"k_fs_LR.surf.gii -right-surface "$DownSampleFolder"/"$Subject".R.midthickness."$LowResMesh"k_fs_LR.surf.gii
else
  cp ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas.dtseries.nii ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString".dtseries.nii
fi

#Add temporal filtering
${CARET7DIR}/wb_command -cifti-convert -to-nifti ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString".dtseries.nii ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"_FAKENIFTI.nii.gz
fslmaths ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"_FAKENIFTI.nii.gz -bptf `echo "0.5 * $TemporalFilter / $TR_vol" | bc -l` 0 ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"_FAKENIFTI.nii.gz
${CARET7DIR}/wb_command -cifti-convert -from-nifti ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"_FAKENIFTI.nii.gz ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString".dtseries.nii ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$TemporalFilterString""$SmoothingString".dtseries.nii 
rm ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"_FAKENIFTI.nii.gz

#Split into surface and volume
${CARET7DIR}/wb_command -cifti-separate-all ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$TemporalFilterString""$SmoothingString".dtseries.nii -volume ${FEATDir}/${LevelOnefMRIName}_AtlasSubcortical"$TemporalFilterString""$SmoothingString".nii.gz -left ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}.atlasroi.L."$LowResMesh"k_fs_LR.func.gii -right ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}.atlasroi.R."$LowResMesh"k_fs_LR.func.gii

###Subcortical Volume Processsing###
#Run film_gls on subcortical volume data
${HCPPIPEDIR_Bin}/film_gls --rn=${FEATDir}/SubcorticalVolumeStats --sa --ms=5 --in=${FEATDir}/${LevelOnefMRIName}_AtlasSubcortical"$TemporalFilterString""$SmoothingString".nii.gz --pd="$DesignMatrix" --thr=1 --mode=volumetric
rm ${FEATDir}/${LevelOnefMRIName}_AtlasSubcortical"$TemporalFilterString""$SmoothingString".nii.gz

###Cortical Surface Processing###
for Hemisphere in L R ; do
  #Prepare for film_gls  
  ${CARET7DIR}/wb_command -metric-dilate ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}.atlasroi."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii "$DownSampleFolder"/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii 50 ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}.atlasroi_dil."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii -nearest

  #Run film_gls on surface data
  ${HCPPIPEDIR_Bin}/film_gls --rn=${FEATDir}/"$Hemisphere"_SurfaceStats --sa --ms=15 --epith=5 --in2="$DownSampleFolder"/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii --in=${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}.atlasroi_dil."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii --pd="$DesignMatrix" --mode=surface
  rm ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}.atlasroi_dil."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}.atlasroi."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii
done


###Grayordinates Processing###
#Merge Surface and Subcortical Gray into Grayordinates
mkdir ${FEATDir}/GrayordinatesStats
cat ${FEATDir}/SubcorticalVolumeStats/dof > ${FEATDir}/GrayordinatesStats/dof
cat ${FEATDir}/SubcorticalVolumeStats/logfile > ${FEATDir}/GrayordinatesStats/logfile
cat ${FEATDir}/L_SurfaceStats/logfile >> ${FEATDir}/GrayordinatesStats/logfile
cat ${FEATDir}/R_SurfaceStats/logfile >> ${FEATDir}/GrayordinatesStats/logfile
cd ${FEATDir}/SubcorticalVolumeStats
Files=`ls | grep .nii.gz | cut -d "." -f 1`
cd $DIR
for File in $Files ; do
  ${CARET7DIR}/wb_command -cifti-create-dense-timeseries ${FEATDir}/GrayordinatesStats/${File}.dtseries.nii -volume ${FEATDir}/SubcorticalVolumeStats/${File}.nii.gz $ROIsFolder/Atlas_ROIs.${GrayordinatesResolution}.nii.gz -left-metric ${FEATDir}/L_SurfaceStats/${File}.func.gii -roi-left "$DownSampleFolder"/"$Subject".L.atlasroi."$LowResMesh"k_fs_LR.shape.gii -right-metric ${FEATDir}/R_SurfaceStats/${File}.func.gii -roi-right "$DownSampleFolder"/"$Subject".R.atlasroi."$LowResMesh"k_fs_LR.shape.gii
done
rm -r ${FEATDir}/SubcorticalVolumeStats ${FEATDir}/L_SurfaceStats ${FEATDir}/R_SurfaceStats

#Run contrast_mgr on grayordinates data
cd ${FEATDir}/GrayordinatesStats
Files=`ls | grep .dtseries.nii | cut -d "." -f 1`
cd $DIR
for File in $Files ; do
  ${CARET7DIR}/wb_command -cifti-convert -to-nifti ${FEATDir}/GrayordinatesStats/${File}.dtseries.nii ${FEATDir}/GrayordinatesStats/${File}.nii.gz
done
contrast_mgr -f ${DesignfContrasts} ${FEATDir}/GrayordinatesStats "$DesignContrasts"
cd ${FEATDir}/GrayordinatesStats
FilesII=`ls | grep .nii.gz | cut -d "." -f 1`
cd $DIR
for File in $FilesII ; do
  echo $File
  if [ -z "$(echo $Files | grep $File)" ] ; then 
    ${CARET7DIR}/wb_command -cifti-convert -from-nifti ${FEATDir}/GrayordinatesStats/${File}.nii.gz ${FEATDir}/GrayordinatesStats/pe1.dtseries.nii ${FEATDir}/GrayordinatesStats/${File}.dtseries.nii
  fi
  rm ${FEATDir}/GrayordinatesStats/${File}.nii.gz
done

###Standard Volume-based Processsing###
if [ $VolumeBasedProcessing = "YES" ] ; then

  #Add volume smoothing
  FinalSmoothingSigma=`echo "$FinalSmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
  fslmaths ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_SBRef.nii.gz -bin -kernel gauss ${FinalSmoothingSigma} -fmean ${FEATDir}/mask_weight -odt float
  fslmaths ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}.nii.gz -kernel gauss ${FinalSmoothingSigma} -fmean -div ${FEATDir}/mask_weight -mas ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_SBRef.nii.gz ${FEATDir}/${LevelOnefMRIName}"$SmoothingString".nii.gz -odt float
  
  #Add temporal filtering
  fslmaths ${FEATDir}/${LevelOnefMRIName}"$SmoothingString".nii.gz -bptf `echo "0.5 * $TemporalFilter / $TR_vol" | bc -l` -1 ${FEATDir}/${LevelOnefMRIName}"$TemporalFilterString""$SmoothingString".nii.gz

  #Run film_gls on subcortical volume data
  ${HCPPIPEDIR_Bin}/film_gls --rn=${FEATDir}/StandardVolumeStats --sa --ms=5 --in=${FEATDir}/${LevelOnefMRIName}"$TemporalFilterString""$SmoothingString".nii.gz --pd="$DesignMatrix" --thr=1000

  #Run contrast_mgr on subcortical volume data
  contrast_mgr -f ${DesignfContrasts} ${FEATDir}/StandardVolumeStats "$DesignContrasts"
fi


