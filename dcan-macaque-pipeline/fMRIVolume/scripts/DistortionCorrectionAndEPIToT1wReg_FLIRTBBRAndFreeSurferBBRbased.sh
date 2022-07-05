#!/bin/bash 
set -e

export OMP_NUM_THREADS=1
export PATH=`echo $PATH | sed 's|freesurfer/|freesurfer53/|g'`

# Requirements for this script
#  installed versions of: FSL5.0.2 and FreeSurfer 5.2 or later versions
#  environment: FSLDIR, FREESURFER_HOME + others

################################################ SUPPORT FUNCTIONS ##################################################
Usage() {
  echo "`basename $0`: Script to register EPI to T1w, with distortion correction"
  echo " "
  echo "Usage: `basename $0` [--workingdir=<working dir>]"
  echo "             --scoutin=<input scout image (pre-sat EPI)>"
  echo "             --t1=<input T1-weighted image>"
  echo "             --t1restore=<input bias-corrected T1-weighted image>"
  echo "             --t1brain=<input bias-corrected, brain-extracted T1-weighted image>"
  echo "             --fmapmag=<input fieldmap magnitude image>"
  echo "             --fmapphase=<input fieldmap phase image>"
  echo "             --echodiff=<difference of echo times for fieldmap, in milliseconds>"
  echo "             --SEPhaseNeg=<input spin echo negative phase encoding image>"
  echo "             --SEPhasePos=<input spin echo positive phase encoding image>"
  echo "             --echospacing=<effective echo spacing of fMRI image, in seconds>"
  echo "             --unwarpdir=<unwarping direction: x/y/z/-x/-y/-z>"
  echo "             --owarp=<output filename for warp of EPI to T1w>"
  echo "             --biasfield=<input bias field estimate image, in fMRI space>"
  echo "             --oregim=<output registered image (EPI to T1w)>"
  echo "             --freesurferfolder=<directory of FreeSurfer folder>"
  echo "             --freesurfersubjectid=<FreeSurfer Subject ID>"
  echo "             --gdcoeffs=<gradient non-linearity distortion coefficients (Siemens format)>"
  echo "             [--qaimage=<output name for QA image>]"
  echo "             --method=<method used for distortion correction: FIELDMAP or TOPUP>"
  echo "             [--topupconfig=<topup config file>]"
  echo "             --ojacobian=<output filename for Jacobian image (in T1w space)>"

}

# function for parsing options
getopt1() {
    sopt="$1"
    shift 1
    for fn in $@ ; do
	if [ `echo $fn | grep -- "^${sopt}=" | wc -w` -gt 0 ] ; then
	    echo $fn | sed "s/^${sopt}=//"
	    return 0
	fi
    done
}

defaultopt() {
    echo $1
}

################################################### OUTPUT FILES #####################################################

# Outputs (in $WD):
#  
#    FIELDMAP section only: 
#      Magnitude  Magnitude_brain  FieldMap
#
#    FIELDMAP and TOPUP sections: 
#      Jacobian2T1w
#      ${ScoutInputFile}_undistorted  
#      ${ScoutInputFile}_undistorted2T1w_init   
#      ${ScoutInputFile}_undistorted_warp
#
#    FreeSurfer section: 
#      fMRI2str.mat  fMRI2str
#      ${ScoutInputFile}_undistorted2T1w  
#
# Outputs (not in $WD):
#
#       ${RegOutput}  ${OutputTransform}  ${JacobianOut}  ${QAImage}



################################################## OPTION PARSING #####################################################


# Just give usage if no arguments specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi
# check for correct options
if [ $# -lt 21 ] ; then Usage; exit 1; fi

# parse arguments
WD=`getopt1 "--workingdir" $@`  # "$1"
ScoutInputName=`getopt1 "--scoutin" $@`  # "$2"
T1wImage=`getopt1 "--t1" $@`  # "$3"
T1wRestoreImage=`getopt1 "--t1restore" $@`  # "$4"
T1wBrainImage=`getopt1 "--t1brain" $@`  # "$5"
SpinEchoPhaseEncodeNegative=`getopt1 "--SEPhaseNeg" $@`  # "$7"
SpinEchoPhaseEncodePositive=`getopt1 "--SEPhasePos" $@`  # "$5"
DwellTime=`getopt1 "--echospacing" $@`  # "$9"
MagnitudeInputName=`getopt1 "--fmapmag" $@`  # "$6"
MagnitudeInputBrainName=`getopt1 "fmapmagbrain" $@`
PhaseInputName=`getopt1 "--fmapphase" $@`  # "$7"
deltaTE=`getopt1 "--echodiff" $@`  # "$8"
UnwarpDir=`getopt1 "--unwarpdir" $@`  # "${10}"
OutputTransform=`getopt1 "--owarp" $@`  # "${11}"
BiasField=`getopt1 "--biasfield" $@`  # "${12}"
RegOutput=`getopt1 "--oregim" $@`  # "${13}"
FreeSurferSubjectFolder=`getopt1 "--freesurferfolder" $@`  # "${14}"
FreeSurferSubjectID=`getopt1 "--freesurfersubjectid" $@`  # "${15}"
GradientDistortionCoeffs=`getopt1 "--gdcoeffs" $@`  # "${17}"
QAImage=`getopt1 "--qaimage" $@`  # "${20}"
DistortionCorrection=`getopt1 "--method" $@`  # "${21}"
TopupConfig=`getopt1 "--topupconfig" $@`  # "${22}"
JacobianOut=`getopt1 "--ojacobian" $@`  # "${23}"
ContrastEnhanced=`getopt1 "--ce" $@`
InputMaskImage=`getopt1 "--inputmask" $@`

ScoutInputFile=`basename $ScoutInputName`
T1wBrainImageFile=`basename $T1wBrainImage`


# default parameters
RegOutput=`$FSLDIR/bin/remove_ext $RegOutput`
WD=`defaultopt $WD ${RegOutput}.wdir`
GlobalScripts=${HCPPIPEDIR_Global}
GlobalBinaries=${HCPPIPEDIR_Bin}
TopupConfig=`defaultopt $TopupConfig ${HCPPIPEDIR_Config}/b02b0.cnf`
UseJacobian=false
ContrastEnhanced=`defaultopt $ContrastEnhanced false`

if [ ${ContrastEnhanced} = "false" ] ; then
  FSContrast="--bold"
else
  FSContrast="--T1"
fi

echo " "
echo " START: DistortionCorrectionEpiToT1wReg_FLIRTBBRAndFreeSurferBBRBased"

mkdir -p $WD

# Record the input options in a log file
echo "$0 $@" >> $WD/log.txt
echo "PWD = `pwd`" >> $WD/log.txt
echo "date: `date`" >> $WD/log.txt
echo " " >> $WD/log.txt

if [ ! -e ${WD}/FieldMap ] ; then
  mkdir ${WD}/FieldMap
fi

########################################## DO WORK ########################################## 

cp ${T1wBrainImage}.nii.gz ${WD}/${T1wBrainImageFile}.nii.gz

###### FIELDMAP VERSION (GE FIELDMAPS) ######
if [ $DistortionCorrection = "FIELDMAP" ] ; then
  # process fieldmap with gradient non-linearity distortion correction
echo  ${GlobalScripts}/FieldMapPreprocessingAll.sh \
      --workingdir=${WD}/FieldMap \
      --fmapmag=${MagnitudeInputName} \
      --fmapmagbrain=${MagnitudeInputBrainName} \
      --fmapphase=${PhaseInputName} \
      --echodiff=${deltaTE} \
      --ofmapmag=${WD}/Magnitude \
      --ofmapmagbrain=${WD}/Magnitude_brain \
      --ofmap=${WD}/FieldMap \
      --gdcoeffs=${GradientDistortionCoeffs}
  ${GlobalScripts}/FieldMapPreprocessingAll.sh \
      --workingdir=${WD}/FieldMap \
      --fmapmag=${MagnitudeInputName} \
      --fmapphase=${PhaseInputName} \
      --echodiff=${deltaTE} \
      --ofmapmag=${WD}/Magnitude \
      --ofmapmagbrain=${WD}/Magnitude_brain \
      --ofmap=${WD}/FieldMap \
      --gdcoeffs=${GradientDistortionCoeffs}
  cp ${ScoutInputName}.nii.gz ${WD}/Scout.nii.gz
  #Test if Magnitude Brain and T1w Brain Are Similar in Size, if not, assume Magnitude Brain Extraction Failed and Must Be Retried After Removing Bias Field
  MagnitudeBrainSize=`${FSLDIR}/bin/fslstats ${WD}/Magnitude_brain -V | cut -d " " -f 2`
  T1wBrainSize=`${FSLDIR}/bin/fslstats ${WD}/${T1wBrainImageFile} -V | cut -d " " -f 2`

  if false && [[ X`echo "if ( (${MagnitudeBrainSize} / ${T1wBrainSize}) > 1.25 ) {1}" | bc -l` = X1 || X`echo "if ( (${MagnitudeBrainSize} / ${T1wBrainSize}) < 0.75 ) {1}" | bc -l` = X1 || ${ContrastEnhanced} = "true" ]] ; then
    echo "should not reach this code"
    ${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${WD}/Magnitude.nii.gz -ref ${T1wImage} -omat "$WD"/Mag2T1w.mat -out ${WD}/Magnitude2T1w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30
    ${FSLDIR}/bin/convert_xfm -omat "$WD"/T1w2Mag.mat -inverse "$WD"/Mag2T1w.mat
    ${FSLDIR}/bin/applywarp --interp=nn -i ${WD}/${T1wBrainImageFile} -r ${WD}/Magnitude.nii.gz --premat="$WD"/T1w2Mag.mat -o ${WD}/Magnitude_brain_mask.nii.gz    
    ${FSLDIR}/bin/fslmaths ${WD}/Magnitude_brain_mask.nii.gz -bin ${WD}/Magnitude_brain_mask.nii.gz
    ${FSLDIR}/bin/fslmaths ${WD}/Magnitude.nii.gz -mas ${WD}/Magnitude_brain_mask.nii.gz ${WD}/Magnitude_brain.nii.gz

    ${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${WD}/Scout.nii.gz -ref ${T1wImage} -omat "$WD"/Scout2T1w.mat -out ${WD}/Scout2T1w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30
    ${FSLDIR}/bin/convert_xfm -omat "$WD"/T1w2Scout.mat -inverse "$WD"/Scout2T1w.mat
    ${FSLDIR}/bin/applywarp --interp=nn -i ${WD}/${T1wBrainImageFile} -r ${WD}/Scout.nii.gz --premat="$WD"/T1w2Scout.mat -o ${WD}/Scout_brain_mask.nii.gz    
    ${FSLDIR}/bin/fslmaths ${WD}/Scout_brain_mask.nii.gz -bin ${WD}/Scout_brain_mask.nii.gz
    ${FSLDIR}/bin/fslmaths ${WD}/Scout.nii.gz -mas ${WD}/Scout_brain_mask.nii.gz ${WD}/Scout_brain.nii.gz

    #Test if Magnitude Brain and T1w Brain Are Similar in Size, if not, assume Magnitude Brain Extraction Failed and Must Be Retried After Removing Bias Field
    T1wBrainSize=`${FSLDIR}/bin/fslstats ${WD}/${T1wBrainImageFile} -V | cut -d " " -f 2`
    ScoutBrainSize=`${FSLDIR}/bin/fslstats ${WD}/Scout_brain -V | cut -d " " -f 2`
    MagnitudeBrainSize=`${FSLDIR}/bin/fslstats ${WD}/Magnitude_brain -V | cut -d " " -f 2`

    if false && [[ X`echo "if ( (${ScoutBrainSize} / ${T1wBrainSize}) > 1.25 ) {1}" | bc -l` = X1 || X`echo "if ( (${ScoutBrainSize} / ${T1wBrainSize}) < 0.75 ) {1}" | bc -l` = X1 ]] ; then
      echo "should not reach this code 2"
      ${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${WD}/Magnitude.nii.gz -ref ${WD}/${T1wBrainImageFile} -omat "$WD"/Mag2T1w.mat -out ${WD}/Magnitude2T1w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30
      ${FSLDIR}/bin/convert_xfm -omat "$WD"/T1w2Mag.mat -inverse "$WD"/Mag2T1w.mat
      ${FSLDIR}/bin/applywarp --interp=nn -i ${WD}/${T1wBrainImageFile} -r ${WD}/Magnitude.nii.gz --premat="$WD"/T1w2Mag.mat -o ${WD}/Magnitude_brain_mask.nii.gz    
      ${FSLDIR}/bin/fslmaths ${WD}/Magnitude_brain_mask.nii.gz -bin ${WD}/Magnitude_brain_mask.nii.gz
      ${FSLDIR}/bin/fslmaths ${WD}/Magnitude.nii.gz -mas ${WD}/Magnitude_brain_mask.nii.gz ${WD}/Magnitude_brain.nii.gz
      
      ${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${WD}/Scout.nii.gz -ref ${WD}/${T1wBrainImageFile} -omat "$WD"/Scout2T1w.mat -out ${WD}/Scout2T1w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30
      ${FSLDIR}/bin/convert_xfm -omat "$WD"/T1w2Scout.mat -inverse "$WD"/Scout2T1w.mat
      ${FSLDIR}/bin/applywarp --interp=nn -i ${WD}/${T1wBrainImageFile} -r ${WD}/Scout.nii.gz --premat="$WD"/T1w2Scout.mat -o ${WD}/Scout_brain_mask.nii.gz    
      ${FSLDIR}/bin/fslmaths ${WD}/Scout_brain_mask.nii.gz -bin ${WD}/Scout_brain_mask.nii.gz
      ${FSLDIR}/bin/fslmaths ${WD}/Scout.nii.gz -mas ${WD}/Scout_brain_mask.nii.gz ${WD}/Scout_brain.nii.gz
    fi

    # Forward warp the fieldmap magnitude and register to Scout image (transform phase image too)
    #${FSLDIR}/bin/fslmaths ${WD}/FieldMap -mas ${WD}/Magnitude_brain_mask.nii.gz -dilD -dilD ${WD}/FieldMap
    #${FSLDIR}/bin/fugue --loadfmap=${WD}/FieldMap --dwell=${DwellTime} --saveshift=${WD}/FieldMap_ShiftMap.nii.gz
    #${FSLDIR}/bin/convertwarp --relout --rel --ref=${WD}/Magnitude --shiftmap=${WD}/FieldMap_ShiftMap.nii.gz --shiftdir=${UnwarpDir} --out=${WD}/FieldMap_Warp.nii.gz   
    #${FSLDIR}/bin/invwarp --ref=${WD}/Magnitude --warp=${WD}/FieldMap_Warp.nii.gz --out=${WD}/FieldMap_Warp.nii.gz

    #${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WD}/Magnitude_brain -r ${WD}/Magnitude_brain -w ${WD}/FieldMap_Warp.nii.gz -o ${WD}/Magnitude_brain_warpped
    #${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${WD}/Magnitude_brain_warpped -ref ${WD}/Scout_brain.nii.gz -out ${WD}/Magnitude_brain_warpped2Scout_brain.nii.gz -omat ${WD}/Fieldmap2Scout_brain.mat -searchrx -30 30 -searchry -30 30 -searchrz -30 30
    
    #${FSLDIR}/bin/flirt -in ${WD}/FieldMap.nii.gz -ref ${WD}/Scout_brain.nii.gz -applyxfm -init ${WD}/Fieldmap2Scout_brain.mat -out ${WD}/FieldMap2Scout_brain.nii.gz
    
    # Convert to shift map then to warp field and unwarp the Scout
    #${FSLDIR}/bin/fugue --loadfmap=${WD}/FieldMap2Scout_brain.nii.gz --dwell=${DwellTime} --saveshift=${WD}/FieldMap2Scout_brain_ShiftMap.nii.gz    
    #${FSLDIR}/bin/convertwarp --relout --rel --ref=${WD}/Scout_brain.nii.gz --shiftmap=${WD}/FieldMap2Scout_brain_ShiftMap.nii.gz --shiftdir=${UnwarpDir} --out=${WD}/FieldMap2Scout_brain_Warp.nii.gz    
    #${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WD}/Scout_brain.nii.gz -r ${WD}/Scout_brain.nii.gz -w ${WD}/FieldMap2Scout_brain_Warp.nii.gz -o ${WD}/Scout_brain_dc.nii.gz

    #if [ ${ContrastEnhanced} = "false" ] ; then
      #${FSLDIR}/bin/epi_reg --epi=${WD}/Scout_brain_dc.nii.gz --t1=${T1wImage} --t1brain=${WD}/${T1wBrainImageFile} --out=${WD}/${ScoutInputFile}_undistorted
    #else
      #${FSLDIR}/bin/flirt -interp spline -in ${WD}/Scout_brain_dc.nii.gz -ref ${WD}/${T1wBrainImageFile} -omat ${WD}/${ScoutInputFile}_undistorted_init.mat -out ${WD}/${ScoutInputFile}_undistorted
      #${FSLDIR}/bin/applywarp --interp=spline -i ${WD}/Scout_brain_dc.nii.gz -r ${T1wImage} --premat=${WD}/${ScoutInputFile}_undistorted_init.mat -o ${WD}/${ScoutInputFile}_undistorted
      #cp ${WD}/${ScoutInputFile}_undistorted_init.mat ${WD}/${ScoutInputFile}_undistorted.mat
    #fi

    # Make a warpfield directly from original (non-corrected) Scout to T1w
    #${FSLDIR}/bin/convertwarp --relout --rel --ref=${T1wImage} --warp1=${WD}/FieldMap2Scout_brain_Warp.nii.gz --postmat=${WD}/${ScoutInputFile}_undistorted.mat -o ${WD}/${ScoutInputFile}_undistorted_warp.nii.gz
    
      
    # register scout to T1w image using fieldmap
    if [ ${ContrastEnhanced} = "true" ] ; then
      fslmaths ${WD}/Scout_brain.nii.gz -recip ${WD}/Scout_brain_inv.nii.gz
      Regfile=${WD}/Scout_brain_inv.nii.gz
    else
      Regfile=${WD}/Scout_brain.nii.gz
    fi
    ${FSLDIR}/bin/epi_reg --epi=${Regfile} --t1=${T1wImage} --t1brain=${WD}/${T1wBrainImageFile} --out=${WD}/${ScoutInputFile}_undistorted --fmap=${WD}/FieldMap.nii.gz --fmapmag=${WD}/Magnitude.nii.gz --fmapmagbrain=${WD}/Magnitude_brain.nii.gz --echospacing=${DwellTime} --pedir=${UnwarpDir}
  else
    echo "Magnitude and Brain size are approximately equal, registering scout to T1w image"
    # skull strip epi -- important for macaques
      #@TODO @WARNING inserting manual mask if it is set...
      if [ ! -z ${InputMaskImage} ]; then
           fslmaths ${InputMaskImage} -bin "$WD"/Scout_brain_mask.nii.gz
           fslmaths "$WD"/Scout.nii.gz -mas "$WD"/Scout_brain_mask.nii.gz "$WD"/Scout_brain.nii.gz
      else
        ${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${WD}/Scout.nii.gz -ref ${WD}/${T1wBrainImageFile} -omat "$WD"/Scout2T1w.mat -out ${WD}/Scout2T1w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30
        ${FSLDIR}/bin/convert_xfm -omat "$WD"/T1w2Scout.mat -inverse "$WD"/Scout2T1w.mat
        ${FSLDIR}/bin/applywarp --interp=nn -i ${WD}/${T1wBrainImageFile} -r ${WD}/Scout.nii.gz --premat="$WD"/T1w2Scout.mat -o ${WD}/Scout_brain_mask.nii.gz    
        ${FSLDIR}/bin/fslmaths ${WD}/Scout_brain_mask.nii.gz -bin ${WD}/Scout_brain_mask.nii.gz
        ${FSLDIR}/bin/fslmaths ${WD}/Scout.nii.gz -mas ${WD}/Scout_brain_mask.nii.gz ${WD}/Scout_brain.nii.gz
      fi
    # register scout to T1w image using fieldmap
    ${FSLDIR}/bin/epi_reg --epi=${WD}/Scout_brain.nii.gz --t1=${T1wImage} --t1brain=${WD}/${T1wBrainImageFile} --out=${WD}/${ScoutInputFile}_undistorted --fmap=${WD}/FieldMap.nii.gz --fmapmag=${WD}/Magnitude.nii.gz --fmapmagbrain=${WD}/Magnitude_brain.nii.gz --echospacing=${DwellTime} --pedir=${UnwarpDir}
  fi
  # convert epi_reg warpfield from abs to rel convention (NB: this is the current convention for epi_reg but it may change in the future, or take an option)
  #${FSLDIR}/bin/immv ${WD}/${ScoutInputFile}_undistorted_warp ${WD}/${ScoutInputFile}_undistorted_warp_abs
  #${FSLDIR}/bin/convertwarp --relout --abs -r ${WD}/${ScoutInputFile}_undistorted_warp_abs -w ${WD}/${ScoutInputFile}_undistorted_warp_abs -o ${WD}/${ScoutInputFile}_undistorted_warp
  # create spline interpolated output for scout to T1w + apply bias field correction
  ${FSLDIR}/bin/applywarp --rel --interp=spline -i ${ScoutInputName} -r ${T1wImage} -w ${WD}/${ScoutInputFile}_undistorted_warp.nii.gz -o ${WD}/${ScoutInputFile}_undistorted_1vol.nii.gz
  ${FSLDIR}/bin/fslmaths ${WD}/${ScoutInputFile}_undistorted_1vol.nii.gz -div ${BiasField} ${WD}/${ScoutInputFile}_undistorted_1vol.nii.gz
  ${FSLDIR}/bin/immv ${WD}/${ScoutInputFile}_undistorted_1vol.nii.gz ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz
  ###Jacobian Volume FAKED for Regular Fieldmaps (all ones) ###
  ${FSLDIR}/bin/fslmaths ${T1wImage} -abs -add 1 -bin ${WD}/Jacobian2T1w.nii.gz
    
###### TOPUP VERSION (SE FIELDMAPS) ######
elif [ $DistortionCorrection = "TOPUP" ] ; then
  # Use topup to distortion correct the scout scans
  #    using a blip-reversed SE pair "fieldmap" sequence
  ${GlobalScripts}/TopupPreprocessingAll.sh \
      --workingdir=${WD}/FieldMap \
      --phaseone=${SpinEchoPhaseEncodeNegative} \
      --phasetwo=${SpinEchoPhaseEncodePositive} \
      --scoutin=${ScoutInputName} \
      --echospacing=${DwellTime} \
      --unwarpdir=${UnwarpDir} \
      --owarp=${WD}/WarpField \
      --ojacobian=${WD}/Jacobian \
      --gdcoeffs=${GradientDistortionCoeffs} \
      --topupconfig=${TopupConfig}

  # create a spline interpolated image of scout (distortion corrected in same space)
  ${FSLDIR}/bin/applywarp --rel --interp=spline -i ${ScoutInputName} -r ${ScoutInputName} -w ${WD}/WarpField.nii.gz -o ${WD}/${ScoutInputFile}_undistorted
  # apply Jacobian correction to scout image (optional)
  if [ $UseJacobian = true ] ; then
      ${FSLDIR}/bin/fslmaths ${WD}/${ScoutInputFile}_undistorted -mul ${WD}/Jacobian.nii.gz ${WD}/${ScoutInputFile}_undistorted
  fi
  # register undistorted scout image to T1w
     ${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${WD}/${ScoutInputFile}_undistorted -ref ${WD}/${T1wBrainImageFile} -omat "$WD"/Scout2T1w.mat -out ${WD}/Scout2T1w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30
      ${FSLDIR}/bin/convert_xfm -omat "$WD"/T1w2Scout.mat -inverse "$WD"/Scout2T1w.mat
      ${FSLDIR}/bin/applywarp --interp=nn -i ${WD}/${T1wBrainImageFile} -r ${WD}/${ScoutInputFile}_undistorted --premat="$WD"/T1w2Scout.mat -o ${WD}/Scout_brain_mask.nii.gz    
      ${FSLDIR}/bin/fslmaths ${WD}/Scout_brain_mask.nii.gz -bin ${WD}/Scout_brain_mask.nii.gz
      ${FSLDIR}/bin/fslmaths ${WD}/${ScoutInputFile}_undistorted -mas ${WD}/Scout_brain_mask.nii.gz ${WD}/Scout_brain_dc.nii.gz
  if [ ${ContrastEnhanced} = "false" ] ; then
    ${FSLDIR}/bin/epi_reg --epi=${WD}/Scout_brain_dc.nii.gz --t1=${T1wImage} --t1brain=${WD}/${T1wBrainImageFile} --out=${WD}/${ScoutInputFile}_undistorted
  else
    flirt -interp spline -in ${WD}/Scout_brain_dc.nii.gz -ref ${WD}/${T1wBrainImageFile} -omat ${WD}/${ScoutInputFile}_undistorted_init.mat -out ${WD}/${ScoutInputFile}_undistorted
    applywarp --interp=spline -i ${WD}/Scout_brain_dc.nii.gz -r ${T1wImage} --premat=${WD}/${ScoutInputFile}_undistorted_init.mat -o ${WD}/${ScoutInputFile}_undistorted
    cp ${WD}/${ScoutInputFile}_undistorted_init.mat ${WD}/${ScoutInputFile}_undistorted.mat
  fi
  # generate combined warpfields and spline interpolated images + apply bias field correction
  ${FSLDIR}/bin/convertwarp --relout --rel -r ${T1wImage} --warp1=${WD}/WarpField.nii.gz --postmat=${WD}/${ScoutInputFile}_undistorted.mat -o ${WD}/${ScoutInputFile}_undistorted_warp
  ${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WD}/Jacobian.nii.gz -r ${T1wImage} --premat=${WD}/${ScoutInputFile}_undistorted.mat -o ${WD}/Jacobian2T1w.nii.gz
  ${FSLDIR}/bin/applywarp --rel --interp=spline -i ${ScoutInputName} -r ${T1wImage} -w ${WD}/${ScoutInputFile}_undistorted_warp -o ${WD}/${ScoutInputFile}_undistorted
  # apply Jacobian correction to scout image (optional)
  if [ $UseJacobian = true ] ; then
      ${FSLDIR}/bin/fslmaths ${WD}/${ScoutInputFile}_undistorted -div ${BiasField} -mul ${WD}/Jacobian2T1w.nii.gz ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz 
  else
      ${FSLDIR}/bin/fslmaths ${WD}/${ScoutInputFile}_undistorted -div ${BiasField} ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz 
  fi
else
  echo "UNKNOWN DISTORTION CORRECTION METHOD"
  echo "FAKING JACOBIAN AND SCOUT IMAGES"
  ${FSLDIR}/bin/flirt -interp spline -in ${ScoutInputName}.nii.gz -ref ${T1wBrainImage} -omat ${WD}/fMRI2str.mat -out ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz 
  ${FSLDIR}/bin/fslmaths ${T1wImage} -abs -add 1 -bin ${WD}/Jacobian2T1w.nii.gz  
fi


### FREESURFER BBR - found to be an improvement, probably due to better GM/WM boundary
SUBJECTS_DIR=${FreeSurferSubjectFolder}
#export SUBJECTS_DIR
#Check to see if FreeSurferNHP.sh was used
if [ -e ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm ] ; then
	#running new macaque version
  echo "NEW MACAQUE NON-BBR DFM-corrected pipeline is utilized -- no bbregister will be used"
  echo "below are parameters (hopefully) for debugging:"
  echo ${WD}
  echo ${ScoutInputName}
  echo ${OutputTransform}
  echo ${JacobianOut}
  cp ${WD}/${ScoutInputFile}_undistorted_warp.nii.gz ${OutputTransform}.nii.gz
  imcp ${WD}/Jacobian2T1w.nii.gz ${JacobianOut} #  this is the proper "JacobianOut" for input into OneStepResampling.
#  echo "NONHUMAN PRIMATE RUNNING" ### ERIC ###
  #Perform Registration in FreeSurferNHP 1mm Space
  
  #applywarp --interp=spline -i ${WD}/Scout.nii.gz -r ${WD}/${T1wBrainImageFile} --premat=${WD}/${ScoutInputFile}_undistorted_init.mat -o ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz
#  ScoutImage="${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz"
  
#  for Image in ${ScoutImage} ${VSMImage} ; do
#    echo "ERIC'S IMAGE CHECK:"
#    echo $Image
#    ImageFile=`remove_ext ${Image}`

#    res=`fslorient -getsform $Image | cut -d " " -f 1 | cut -d "-" -f 2`
#    oldsform=`fslorient -getsform $Image`
#    newsform=""
#    i=1
#    while [ $i -le 12 ] ; do
#      oldelement=`echo $oldsform | cut -d " " -f $i`
#      newelement=`echo "scale=1; $oldelement / $res" | bc -l`
#      newsform=`echo "$newsform""$newelement"" "`
#      if [ $i -eq 4 ] ; then
#        originx="$newelement"
#      fi
#      if [ $i -eq 8 ] ; then
#       originy="$newelement"
#     fi
#     if [ $i -eq 12 ] ; then
#       originz="$newelement"
#     fi
#      i=$(($i+1))
#    done
#    newsform=`echo "$newsform""0 0 0 1" | sed 's/  / /g'`

#    cp "$Image" "$ImageFile"_1mm.nii.gz
#    fslorient -setsform $newsform "$ImageFile"_1mm.nii.gz
#    fslhd -x "$ImageFile"_1mm.nii.gz | sed s/"dx = '${res}'"/"dx = '1'"/g | sed s/"dy = '${res}'"/"dy = '1'"/g | sed s/"dz = '${res}'"/"dz #= '1'"/g | fslcreatehd - "$ImageFile"_1mm_head.nii.gz
#    fslmaths "$ImageFile"_1mm_head.nii.gz -add "$ImageFile"_1mm.nii.gz "$ImageFile"_1mm.nii.gz
#    fslorient -copysform2qform "$ImageFile"_1mm.nii.gz
#    rm "$ImageFile"_1mm_head.nii.gz
#    dimex=`fslval "$ImageFile"_1mm dim1`
#    dimey=`fslval "$ImageFile"_1mm dim2`
#    dimez=`fslval "$ImageFile"_1mm dim3`
    # ERIC: PADS ASSUME EVEN-NUMBERED DIMENSIONS, odd dimensions do not work.
#    padx=`echo "(256 - $dimex) / 2" | bc`
#    pady=`echo "(256 - $dimey) / 2" | bc`
#    padz=`echo "(256 - $dimez) / 2" | bc`
#    # ERIC: ADDED ODD DETECTION SECTION
#    oddx=`echo "(256 - $dimex) % 2" | bc`
#    oddy=`echo "(256 - $dimey) % 2" | bc`
#    oddz=`echo "(256 - $dimez) % 2" | bc`
    
    # ERIC: USING ODD DETECTION FOR ALWAYS PADDING CORRECTLY TO 256
#    if [ $oddx -eq 1 ] ; then
#      fslcreatehd $oddx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$ImageFile"_1mm_pad1x
#      fslcreatehd $padx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$ImageFile"_1mm_padx
#      fslmerge -x "$ImageFile"_1mm "$ImageFile"_1mm_pad1x "$ImageFile"_1mm_padx "$ImageFile"_1mm "$ImageFile"_1mm_padx
#      rm "$ImageFile"_1mm_pad1x.nii.gz "$ImageFile"_1mm_padx.nii.gz
#    else
#      fslcreatehd $padx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$ImageFile"_1mm_padx
#      fslmerge -x "$ImageFile"_1mm "$ImageFile"_1mm_padx "$ImageFile"_1mm "$ImageFile"_1mm_padx
#      rm "$ImageFile"_1mm_padx.nii.gz
#    fi
    
#    if [ $oddy -eq 1 ] ; then
#      fslcreatehd 256 $oddy $dimez 1 1 1 1 1 0 0 0 16 "$ImageFile"_1mm_pad1y
#      fslcreatehd 256 $pady $dimez 1 1 1 1 1 0 0 0 16 "$ImageFile"_1mm_pady
#      fslmerge -y "$ImageFile"_1mm "$ImageFile"_1mm_pad1y "$ImageFile"_1mm_pady "$ImageFile"_1mm "$ImageFile"_1mm_pady
#      rm "$ImageFile"_1mm_pad1y.nii.gz "$ImageFile"_1mm_pady.nii.gz
#    else
#      fslcreatehd 256 $pady $dimez 1 1 1 1 1 0 0 0 16 "$ImageFile"_1mm_pady
#      fslmerge -y "$ImageFile"_1mm "$ImageFile"_1mm_pady "$ImageFile"_1mm "$ImageFile"_1mm_pady
#      rm "$ImageFile"_1mm_pady.nii.gz
#    fi
    
#    if [ $oddz -eq 1 ] ; then
#      fslcreatehd 256 256 $oddz 1 1 1 1 1 0 0 0 16 "$ImageFile"_1mm_pad1z
#      fslcreatehd 256 256 $padz 1 1 1 1 1 0 0 0 16 "$ImageFile"_1mm_padz
#      fslmerge -z "$ImageFile"_1mm "$ImageFile"_1mm_pad1z "$ImageFile"_1mm_padz "$ImageFile"_1mm "$ImageFile"_1mm_padz
#      rm "$ImageFile"_1mm_pad1z.nii.gz "$ImageFile"_1mm_padz.nii.gz
#    else
#      fslcreatehd 256 256 $padz 1 1 1 1 1 0 0 0 16 "$ImageFile"_1mm_padz
#      fslmerge -z "$ImageFile"_1mm "$ImageFile"_1mm_padz "$ImageFile"_1mm "$ImageFile"_1mm_padz
#      rm "$ImageFile"_1mm_padz.nii.gz
#    fi
    
#    fslorient -setsformcode 1 "$ImageFile"_1mm
#    fslorient -setsform -1 0 0 `echo "$originx + $padx" | bc -l` 0 1 0 `echo "$originy - $pady" | bc -l` 0 0 1 `echo "$originz - $padz" | bc -l` 0 0 0 1 "$ImageFile"_1mm
#  done
  
#echo  ${FREESURFER_HOME}/bin/bbregister --s "${FreeSurferSubjectID}_1mm" --mov ${WD}/${ScoutInputFile}_undistorted2T1w_init_1mm.nii.gz --surf white.deformed --init-reg ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/transforms/eye.dat ${FSContrast} --reg ${WD}/EPItoT1w.dat --o ${WD}/${ScoutInputFile}_undistorted2T1w_1mm.nii.gz 
#  ${FREESURFER_HOME}/bin/bbregister --s "${FreeSurferSubjectID}_1mm" --mov ${WD}/${ScoutInputFile}_undistorted2T1w_init_1mm.nii.gz --surf white.deformed --init-reg ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/transforms/eye.dat ${FSContrast} --reg ${WD}/EPItoT1w.dat --o ${WD}/${ScoutInputFile}_undistorted2T1w_1mm.nii.gz 
#echo  tkregister2 --noedit --reg ${WD}/EPItoT1w.dat --mov ${WD}/${ScoutInputFile}_undistorted2T1w_init_1mm.nii.gz --targ ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/T1w_hires.nii.gz --fslregout ${WD}/fMRI2str_1mm.mat
#  tkregister2 --noedit --reg ${WD}/EPItoT1w.dat --mov ${WD}/${ScoutInputFile}_undistorted2T1w_init_1mm.nii.gz --targ ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/T1w_hires.nii.gz --fslregout ${WD}/fMRI2str_1mm.mat
#echo  applywarp --interp=spline -i ${WD}/${ScoutInputFile}_undistorted2T1w_init_1mm.nii.gz -r ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/T1w_hires.nii.gz --premat=${WD}/fMRI2str_1mm.mat -o ${WD}/${ScoutInputFile}_undistorted2T1w_1mm.nii.gz
#  applywarp --interp=spline -i ${WD}/${ScoutInputFile}_undistorted2T1w_init_1mm.nii.gz -r ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/T1w_hires.nii.gz --premat=${WD}/fMRI2str_1mm.mat -o ${WD}/${ScoutInputFile}_undistorted2T1w_1mm.nii.gz

#  convert_xfm -omat ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/transforms/temp.mat -concat ${WD}/fMRI2str_1mm.mat ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/transforms/real2fs.mat
#  convert_xfm -omat ${WD}/fMRI2str.mat -concat ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/transforms/fs2real.mat ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/transforms/temp.mat
#  rm ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/transforms/temp.mat
## Trying to circumvent step-by-step transformations, and work straight from .5mm space for monkeys
#echo  ${FREESURFER_HOME}/bin/bbregister --s "${FreeSurferSubjectID}" --mov ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz --surf white.deformed --init-reg ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}/mri/transforms/eye.dat ${FSContrast} --reg ${WD}/EPItoT1w.dat --o ${WD}/${ScoutInputFile}_undistorted2T1w.nii.gz 
#  ${FREESURFER_HOME}/bin/bbregister --s "${FreeSurferSubjectID}" --mov ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz --surf white.deformed --init-reg ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}/mri/transforms/eye.dat ${FSContrast} --reg ${WD}/EPItoT1w.dat --o ${WD}/${ScoutInputFile}_undistorted2T1w.nii.gz 
#echo  tkregister2 --noedit --reg ${WD}/EPItoT1w.dat --mov ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz --targ ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/T1w_hires.nii.gz --fslregout ${WD}/fMRI2str.mat
#  tkregister2 --noedit --reg ${WD}/EPItoT1w.dat --mov ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz --targ ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/T1w_hires.nii.gz --fslregout ${WD}/fMRI2str.mat
#echo  applywarp --interp=spline -i ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz -r ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/T1w_hires.nii.gz --premat=${WD}/fMRI2str.mat -o ${WD}/${ScoutInputFile}_undistorted2T1w.nii.gz
#  applywarp --interp=spline -i ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz -r ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}_1mm/mri/T1w_hires.nii.gz --premat=${WD}/fMRI2str.mat -o ${WD}/${ScoutInputFile}_undistorted2T1w.nii.gz



  
  ###What to do about shift map in new location###?
  
else
  echo "NORMAL RUNNING" ### ERIC ###
  #Run Normally
  #hi-res deformations (0.8mm) may not exist due to difference in processing -- check to see if hi-res deformations exist, if not, create dummies from final surfaces
  if [ -e ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}/surf/lh.white.deformed ] ; then
    echo "LEFT HEMISPHERE HI-RES DEFORMATION FOUND"
  else
    cp ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}/surf/lh.white ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}/surf/lh.white.deformed
  fi
  if [ -e ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}/surf/rh.white.deformed ] ; then
    echo "RIGHT HEMISPHERE HI-RES DEFORMATION FOUND"
  else
    cp ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}/surf/rh.white ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}/surf/rh.white.deformed
  fi
  #perform BBR
    ${FREESURFER_HOME}/bin/bbregister --s ${FreeSurferSubjectID} --mov ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz --surf white.deformed --init-reg ${FreeSurferSubjectFolder}/${FreeSurferSubjectID}/mri/transforms/eye.dat ${FSContrast} --reg ${WD}/EPItoT1w.dat --o ${WD}/${ScoutInputFile}_undistorted2T1w.nii.gz
  # Create FSL-style matrix and then combine with existing warp fields
  ${FREESURFER_HOME}/bin/tkregister2 --noedit --reg ${WD}/EPItoT1w.dat --mov ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz --targ ${T1wImage}.nii.gz --fslregout ${WD}/fMRI2str.mat
fi


### Start : Marc's Janky Fix for No Distortion Corrected Warp ###
  
if [ -e ${WD}/${ScoutInputFile}_undistorted_warp.nii.gz ] ; then
    echo "WARP FOUND"
	${FSLDIR}/bin/convertwarp --relout --rel --warp1=${WD}/${ScoutInputFile}_undistorted_warp.nii.gz --ref=${T1wImage} --postmat=${WD}/fMRI2str.mat --out=${WD}/fMRI2str.nii.gz
else
    echo "WARP DOES NOT EXIST : CREATING WARP FROM ORIGINAL"
 	#${FSLDIR}/bin/flirt -interp spline -in ${ScoutInputName}.nii.gz -ref ${T1wBrainImage} -omat ${WD}/fMRI2str.mat -out ${WD}/${ScoutInputFile}_undistorted2T1w_init.nii.gz 
	${FSLDIR}/bin/convertwarp --relout --rel --ref=${T1wImage} --postmat=${WD}/fMRI2str.mat --out=${WD}/fMRI2str.nii.gz
fi
	# Create warped image with spline interpolation, bias correction and (optional) Jacobian modulation
	#${FSLDIR}/bin/convertwarp --relout --rel --ref=${T1wImage} --postmat=${WD}/fMRI2str.mat --out=${WD}/fMRI2str.nii.gz
	${FSLDIR}/bin/applywarp --rel --interp=spline -i ${ScoutInputName} -r ${T1wImage}.nii.gz -w ${WD}/fMRI2str.nii.gz -o ${WD}/${ScoutInputFile}_undistorted2T1w

### End ###


if [ $UseJacobian = true ] ; then
    ${FSLDIR}/bin/fslmaths ${WD}/${ScoutInputFile}_undistorted2T1w -div ${BiasField} -mul ${WD}/Jacobian2T1w.nii.gz ${WD}/${ScoutInputFile}_undistorted2T1w
else
    ${FSLDIR}/bin/fslmaths ${WD}/${ScoutInputFile}_undistorted2T1w -div ${BiasField} ${WD}/${ScoutInputFile}_undistorted2T1w
fi


cp ${WD}/${ScoutInputFile}_undistorted2T1w.nii.gz ${RegOutput}.nii.gz
cp ${WD}/fMRI2str.nii.gz ${OutputTransform}.nii.gz
cp ${WD}/Jacobian2T1w.nii.gz ${JacobianOut}.nii.gz


# QA image (sqrt of EPI * T1w)
${FSLDIR}/bin/fslmaths ${T1wRestoreImage}.nii.gz -mul ${RegOutput}.nii.gz -sqrt ${QAImage}.nii.gz

echo " "
echo " END: DistortionCorrectionEpiToT1wReg_FLIRTBBRAndFreeSurferBBRBased"
echo " END: `date`" >> $WD/log.txt

########################################## QA STUFF ########################################## 

if [ -e $WD/qa.txt ] ; then rm -f $WD/qa.txt ; fi
echo "cd `pwd`" >> $WD/qa.txt
echo "# Check registration of EPI to T1w (with all corrections applied)" >> $WD/qa.txt
echo "fslview ${T1wRestoreImage} ${RegOutput} ${QAImage}" >> $WD/qa.txt
echo "# Check undistortion of the scout image" >> $WD/qa.txt
echo "fslview `dirname ${ScoutInputName}`/GradientDistortionUnwarp/Scout ${WD}/${ScoutInputFile}_undistorted" >> $WD/qa.txt

##############################################################################################

