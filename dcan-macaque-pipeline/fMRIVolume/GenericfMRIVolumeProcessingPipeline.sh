#!/bin/bash
#set -e

export PATH=`echo $PATH | sed 's|freesurfer/|freesurfer53/|g'`
export OMP_NUM_THREADS=1

# Requirements for this script
#  installed versions of: FSL5.0.2 or higher , FreeSurfer (version 5 or higher) , gradunwarp (python code from MGH)
#  environment: use SetUpHCPPipeline.sh  (or individually set FSLDIR, FREESURFER_HOME, HCPPIPEDIR, PATH - for gradient_unwarp.py)

# make pipeline engine happy...
if [ $# -eq 1 ]
then
    echo "Version unknown..."
    exit 0
fi

########################################## PIPELINE OVERVIEW ##########################################

# TODO

########################################## OUTPUT DIRECTORIES ##########################################

# TODO

################################################ SUPPORT FUNCTIONS ##################################################

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

################################################## OPTION PARSING #####################################################
#set echo

# Just give usage if no arguments specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi

# parse arguments
Path=`getopt1 "--path" $@`  # "$1"
Subject=`getopt1 "--subject" $@`  # "$2"
NameOffMRI=`getopt1 "--fmriname" $@`  # "$6"
fMRITimeSeries=`getopt1 "--fmritcs" $@`  # "$3"
fMRIScout=`getopt1 "--fmriscout" $@`  # "$4"
SpinEchoPhaseEncodeNegative=`getopt1 "--SEPhaseNeg" $@`  # "$7"
SpinEchoPhaseEncodePositive=`getopt1 "--SEPhasePos" $@`  # "$5"
MagnitudeInputName=`getopt1 "--fmapmag" $@`  # "$8" #Expects 4D volume with two 3D timepoints
MagnitudeInputBrainName=`getopt1 "--fmapmagbrain" $@` # If you've already masked the magnitude.
PhaseInputName=`getopt1 "--fmapphase" $@`  # "$9"
DwellTime=`getopt1 "--echospacing" $@`  # "${11}"
deltaTE=`getopt1 "--echodiff" $@`  # "${12}"
UnwarpDir=`getopt1 "--unwarpdir" $@`  # "${13}"
FinalfMRIResolution=`getopt1 "--fmrires" $@`  # "${14}"
DistortionCorrection=`getopt1 "--dcmethod" $@`  # "${17}" #FIELDMAP or TOPUP
GradientDistortionCoeffs=`getopt1 "--gdcoeffs" $@`  # "${18}"
TopupConfig=`getopt1 "--topupconfig" $@`  # "${20}" #NONE if Topup is not being used
ContrastEnhanced=`getopt1 "--ce" $@`
RUN=`getopt1 "--printcom" $@`  # use ="echo" for just printing everything and not running the commands (default is to run)
useT2=`getopt1 "--useT2" $@`
useRevEpi=`getopt1 "--userevepi" $@` # true/false uses the scout brain and reverse se/reverse epi instead of a spin echo pair.
PreviousTask=`getopt1 "--previousregistration" $@`
if [ ! -z $PreviousTask ]; then
  if [[ $PreviousTask =~ task-.* ]]; then
    PreviousRegistration=true
  else
    echo "previousregistration $PreviousTask must start with a 'task-'"
  fi
else
  PreviousRegistration=false
fi

set -ex
# Setup PATHS
PipelineScripts=${HCPPIPEDIR_fMRIVol}
GlobalScripts=${HCPPIPEDIR_Global}
GlobalBinaries=${HCPPIPEDIR_Bin}

#Naming Conventions
T1wImage="T1w_acpc_dc"
T1wRestoreImage="T1w_acpc_dc_restore"
T1wRestoreImageBrain="T1w_acpc_dc_restore_brain"
T1wFolder="T1w" #Location of T1w images
AtlasSpaceFolder="MNINonLinear"
ResultsFolder="Results"
BiasField="BiasField_acpc_dc"
BiasFieldMNI="BiasField"
T1wAtlasName="T1w_restore"
MovementRegressor="Movement_Regressors" #No extension, .txt appended
MotionMatrixFolder="MotionMatrices"
MotionMatrixPrefix="MAT_"
FieldMapOutputName="FieldMap"
MagnitudeOutputName="Magnitude"
MagnitudeBrainOutputName="Magnitude_brain"
ScoutName="Scout"
OrigScoutName="${ScoutName}_orig"
OrigTCSName="${NameOffMRI}_orig"
FreeSurferBrainMask="brainmask_fs"
fMRI2strOutputTransform="${NameOffMRI}2str"
RegOutput="Scout2T1w"
AtlasTransform="acpc_dc2standard"
OutputfMRI2StandardTransform="${NameOffMRI}2standard"
Standard2OutputfMRITransform="standard2${NameOffMRI}"
QAImage="T1wMulEPI"
JacobianOut="Jacobian"
SubjectFolder="$Path"
########################################## DO WORK ##########################################
T1wFolder="$Path"/"$T1wFolder"
AtlasSpaceFolder="$Path"/"$AtlasSpaceFolder"
ResultsFolder="$AtlasSpaceFolder"/"$ResultsFolder"/"$NameOffMRI"

fMRIFolder="$Path"/"$NameOffMRI"
echo
if [ ! -e "$fMRIFolder" ] ; then
  mkdir "$fMRIFolder"
fi
cp "$fMRITimeSeries" "$fMRIFolder"/"$OrigTCSName".nii.gz

#Create fake "Scout" if it doesn't exist
if [ $fMRIScout = "NONE" ] ; then
  ${RUN} ${FSLDIR}/bin/fslroi "$fMRIFolder"/"$OrigTCSName" "$fMRIFolder"/"$OrigScoutName" 0 1
  FakeScout="True"
else
  cp "$fMRIScout" "$fMRIFolder"/"$OrigScoutName".nii.gz
fi

#Gradient Distortion Correction of fMRI
if [ ! $GradientDistortionCoeffs = "NONE" ] ; then
    mkdir -p "$fMRIFolder"/GradientDistortionUnwarp
    ${RUN} "$GlobalScripts"/GradientDistortionUnwarp.sh \
	--workingdir="$fMRIFolder"/GradientDistortionUnwarp \
	--coeffs="$GradientDistortionCoeffs" \
	--in="$fMRIFolder"/"$OrigTCSName" \
	--out="$fMRIFolder"/"$NameOffMRI"_gdc \
	--owarp="$fMRIFolder"/"$NameOffMRI"_gdc_warp

     mkdir -p "$fMRIFolder"/"$ScoutName"_GradientDistortionUnwarp
     ${RUN} "$GlobalScripts"/GradientDistortionUnwarp.sh \
	 --workingdir="$fMRIFolder"/"$ScoutName"_GradientDistortionUnwarp \
	 --coeffs="$GradientDistortionCoeffs" \
	 --in="$fMRIFolder"/"$OrigScoutName" \
	 --out="$fMRIFolder"/"$ScoutName"_gdc \
	 --owarp="$fMRIFolder"/"$ScoutName"_gdc_warp
else
    echo "NOT PERFORMING GRADIENT DISTORTION CORRECTION"
    ${RUN} ${FSLDIR}/bin/imcp "$fMRIFolder"/"$OrigTCSName" "$fMRIFolder"/"$NameOffMRI"_gdc
    ${RUN} ${FSLDIR}/bin/fslroi "$fMRIFolder"/"$NameOffMRI"_gdc "$fMRIFolder"/"$NameOffMRI"_gdc_warp 0 3
    ${RUN} ${FSLDIR}/bin/fslmaths "$fMRIFolder"/"$NameOffMRI"_gdc_warp -mul 0 "$fMRIFolder"/"$NameOffMRI"_gdc_warp
    ${RUN} ${FSLDIR}/bin/imcp "$fMRIFolder"/"$OrigScoutName" "$fMRIFolder"/"$ScoutName"_gdc
fi


echo "RUNNING MOTIONCORRECTION_FLIRTBASED"
mkdir -p "$fMRIFolder"/MotionCorrection_MCFLIRTbased
### ERIC'S DEBUGGING ECHO ###
${RUN} "$PipelineScripts"/MotionCorrection.sh \
    "$fMRIFolder"/MotionCorrection_MCFLIRTbased \
    "$fMRIFolder"/"$NameOffMRI"_gdc \
    "$fMRIFolder"/"$ScoutName"_gdc \
    "$fMRIFolder"/"$NameOffMRI"_mc \
    "$fMRIFolder"/"$MovementRegressor" \
    "$fMRIFolder"/"$MotionMatrixFolder" \
    "$MotionMatrixPrefix" \
    "MCFLIRT"

if [ ${FakeScout} = "True" ] ; then
  fslmaths "$fMRIFolder"/"$NameOffMRI"_mc -Tmean "$fMRIFolder"/"$ScoutName"_gdc
  invwarp -r "$fMRIFolder"/"$NameOffMRI"_gdc_warp -w "$fMRIFolder"/"$NameOffMRI"_gdc_warp -o "$fMRIFolder"/"$NameOffMRI"_gdc_invwarp
  applywarp --interp=spline -i "$fMRIFolder"/"$ScoutName"_gdc -r "$fMRIFolder"/"$ScoutName"_gdc -w "$fMRIFolder"/"$NameOffMRI"_gdc_invwarp -o "$fMRIFolder"/"$OrigScoutName"
fi


#EPI Distortion Correction and EPI to T1w Registration
if [ -e ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased ] ; then
  rm -r ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased
fi
mkdir -p ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased

if [ $DistortionCorrection = FIELDMAP ]; then
### ERIC'S DEBUGGING ECHO ###
# INSERTING MANUAL MASK IF IT IS FOUND IN PATH...
if [ -e ${fMRIFolder}/../masks/${Subject}_${NameOffMRI}_mask.nii.gz ]; then
  echo "using manual mask for this subject..."
  InputMaskImage=${fMRIFolder}/../masks/${Subject}_${NameOffMRI}_mask.nii.gz
fi


${RUN} ${PipelineScripts}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased.sh \
    --workingdir=${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased \
    --scoutin=${fMRIFolder}/${ScoutName}_gdc \
    --t1=${T1wFolder}/${T1wImage} \
    --t1restore=${T1wFolder}/${T1wRestoreImage} \
    --t1brain=${T1wFolder}/${T1wRestoreImageBrain} \
    --fmapmag=${MagnitudeInputName} \
    --fmapphase=${PhaseInputName} \
    --echodiff=${deltaTE} \
    --SEPhaseNeg=${SpinEchoPhaseEncodeNegative} \
    --SEPhasePos=${SpinEchoPhaseEncodePositive} \
    --echospacing=${DwellTime} \
    --unwarpdir=${UnwarpDir} \
    --owarp=${T1wFolder}/xfms/${fMRI2strOutputTransform} \
    --biasfield=${T1wFolder}/${BiasField} \
    --oregim=${fMRIFolder}/${RegOutput} \
    --freesurferfolder=${T1wFolder} \
    --freesurfersubjectid=${Subject} \
    --gdcoeffs=${GradientDistortionCoeffs} \
    --qaimage=${fMRIFolder}/${QAImage} \
    --method=${DistortionCorrection} \
    --topupconfig=${TopupConfig} \
    --ojacobian=${fMRIFolder}/${JacobianOut} \
    --ce=${ContrastEnhanced} \
    --inputmask=$InputMaskImage


elif [ $DistortionCorrection = TOPUP ]; then
	mkdir ${fMRIFolder}/FieldMap 2> /dev/null
  if ! ${PreviousRegistration:-false}; then
  if ${useRevEpi:-false}; then
    SpinEchoPhaseEncodePositive=${fMRIFolder}/${ScoutName}_gdc
  fi
	echo  ${HCPPIPEDIR_Global}/TopupPreprocessingAll.sh \
      --workingdir=${fMRIFolder}/FieldMap \
      --phaseone=${SpinEchoPhaseEncodePositive} \
      --phasetwo=${SpinEchoPhaseEncodeNegative} \
      --scoutin=${fMRIFolder}/${ScoutName}_gdc \
      --echospacing=${DwellTime} \
      --unwarpdir=${SEUnwarpDir} \
      --ofmapmag=${fMRIFolder}/Magnitude \
      --ofmapmagbrain=${fMRIFolder}/Magnitude_brain \
      --ofmap=${T1wFolder}/xfms/${fMRI2strOutputTransform} \
      --ojacobian=${fMRIFolder}/${JacobianOut} \
      --gdcoeffs=${GradientDistortionCoeffs} \
      --topupconfig=${TopupConfig}
	${HCPPIPEDIR_Global}/TopupPreprocessingAll.sh \
      --workingdir=${fMRIFolder}/FieldMap \
      --phaseone=${SpinEchoPhaseEncodeNegative} \
      --phasetwo=${SpinEchoPhaseEncodePositive} \
      --scoutin=${fMRIFolder}/${ScoutName}_gdc \
      --echospacing=${DwellTime} \
      --unwarpdir=${UnwarpDir} \
      --ofmapmag=${fMRIFolder}/Magnitude \
      --ofmapmagbrain=${fMRIFolder}/Magnitude_brain \
      --owarp=${fMRIFolder}/WarpField \
      --ojacobian=${fMRIFolder}/${JacobianOut} \
      --gdcoeffs=${GradientDistortionCoeffs} \
      --topupconfig=${TopupConfig}

###########################################################################################################################################################################
##Bene Changes: Use T2 instead of T1
  #if useT2=none fake T2 and make T2=T2wRestoreImage and apply T1 mask to make T2wRestoreImageBrain  
  #TODO 
  #Here is how I have been faking the T2 and it seems to be working better than using the T1 brain because of the high intensity eyes. 
  #${FSLDIR}/bin/fslmaths ${T1wFolder}/${T1wRestoreImage} -mul -1 ${T1wFolder}/FakeT2Head.nii.gz
  #${FSLDIR}/bin/fslmaths ${T1wFolder}/FakeT2Head.nii.gz -add 500 ${T1wFolder}/FakeT2Head.nii.gz
  #${FSLDIR}/bin/fslmaths ${T1wFolder}/FakeT2Head.nii.gz -uthrp 95 ${T1wFolder}/FakeT2Head.nii.gz
  #${FSLDIR}/bin/fslmaths ${T1wFolder}/FakeT2Head.nii.gz -mas ${T1wFolder}/T1w_acpc_brain_mask.nii.gz ${T1wFolder}/FakeT2brain.nii.gz
  #TODO define T2 images (need to make this better but hard code for now)
  echo "this has only been tested with T2, if we don't have one, fake it here"
  #Create fake "T2" if it doesn't exist
  #if [ $useT2 = "True" ] ; then
  if [[ "TRUE"==${useT2^^} ]]; then
    T2wRestoreImage=T2w_acpc_dc_restore
    T2wRestoreImageBrain=T2w_acpc_dc_restore_brain
  else
    ${FSLDIR}/bin/fslmaths ${T1wFolder}/${T1wRestoreImage} -mul -1 ${T1wFolder}/T2w_acpc_dc_restore.nii.gz
    ${FSLDIR}/bin/fslmaths ${T1wFolder}/T2w_acpc_dc_restore.nii.gz -add 500 ${T1wFolder}/T2w_acpc_dc_restore.nii.gz
    ${FSLDIR}/bin/fslmaths ${T1wFolder}/T2w_acpc_dc_restore.nii.gz -uthrp 95 ${T1wFolder}/T2w_acpc_dc_restore.nii.gz
    ${FSLDIR}/bin/fslmaths ${T1wFolder}/T2w_acpc_dc_restore.nii.gz -mas ${T1wFolder}/T1w_acpc_brain_mask.nii.gz ${T1wFolder}/T2w_acpc_dc_restore_brain.nii.gz
    T2wRestoreImage=T2w_acpc_dc_restore
    T2wRestoreImageBrain=T2w_acpc_dc_restore_brain
  fi


  ${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/${ScoutName}_gdc -r ${fMRIFolder}/${ScoutName}_gdc -w ${fMRIFolder}/WarpField.nii.gz -o ${fMRIFolder}/${ScoutName}_gdc_undistorted
  # apply Jacobian correction to scout image (optional)
  ${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted -mul ${fMRIFolder}/FieldMap/Jacobian ${fMRIFolder}/${ScoutName}_gdc_undistorted
  # register undistorted scout image to T2w head
 ${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/${ScoutName}_gdc_undistorted -ref ${T1wFolder}/${T2wRestoreImage} -omat "$fMRIFolder"/Scout2T2w.mat -out ${fMRIFolder}/Scout2T2w.nii.gz -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo
  ${FSLDIR}/bin/convert_xfm -omat "$fMRIFolder"/T2w2Scout.mat -inverse "$fMRIFolder"/Scout2T2w.mat
  ${FSLDIR}/bin/applywarp --interp=nn -i ${T1wFolder}/${T2wRestoreImageBrain} -r ${fMRIFolder}/${ScoutName}_gdc_undistorted --premat="$fMRIFolder"/T2w2Scout.mat -o ${fMRIFolder}/Scout_brain_mask.nii.gz
  ${FSLDIR}/bin/fslmaths ${fMRIFolder}/Scout_brain_mask.nii.gz -bin ${fMRIFolder}/Scout_brain_mask.nii.gz
  ${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted -mas ${fMRIFolder}/Scout_brain_mask.nii.gz ${fMRIFolder}/Scout_brain_dc.nii.gz
  ## Added step here to make it work better, re-registering the maked brain to the T2 brain: This is ca;;ed undistorted2T1w even though it's registered to T2. but wanted to keep naming the same for future checks. 
  echo " ${ScoutName}_gdc_undistorted2T1w_init.mat is technically ${ScoutName}_gdc_undistorted2T2w_init.mat "
  ${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${fMRIFolder}/Scout_brain_dc.nii.gz -ref ${T1wFolder}/${T2wRestoreImageBrain} -omat "$fMRIFolder"/${ScoutName}_gdc_undistorted2T1w_init.mat -out ${fMRIFolder}/${ScoutName}_gdc_undistorted2T2w_init -searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo
  #Taking out epi_reg because it is really bad at registering especially with contrast images. 
  #  ${FSLDIR}/bin/epi_reg -v --epi=${fMRIFolder}/Scout_brain2T1w.nii.gz --pedir=${UnwarpDir} --t1=${T1wFolder}/${T1wRestoreImage} --t1brain=${T1wFolder}/${T1wRestoreImageBrain} --out=${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init

  #  generate combined warpfields and spline interpolated images + apply bias field correction
  ${FSLDIR}/bin/convertwarp --relout --rel -r ${T1wFolder}/${T2wRestoreImage} --warp1=${fMRIFolder}/WarpField --postmat=${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.mat -o ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init_warp

  #this gives me a blank image, because the jacobian is empty. Trying other Jacobian in FieldMap folder which works. This is because Jacobian gets overwritten with this file later so if this step doesn't work its not going to work.But should work next time when the above is fixed. 
  ${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/Jacobian.nii.gz -r ${T1wFolder}/${T2wRestoreImage} --premat=${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.mat -o ${fMRIFolder}/Jacobian2T1w.nii.gz 
 #${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/FieldMap/Jacobian.nii.gz -r ${T1wFolder}/${T2wRestoreImage} --premat=${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.mat -o ${fMRIFolder}/Jacobian2T1w.nii.gz


  ${FSLDIR}/bin/applywarp --rel --interp=spline -i ${fMRIFolder}/${ScoutName}_gdc -r ${T1wFolder}/${T2wRestoreImage} -w ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init_warp -o ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init
  # apply Jacobian correction to scout image (optional)
  ${FSLDIR}/bin/fslmaths ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init -div ${T1wFolder}/${BiasField} -mul ${fMRIFolder}/Jacobian2T1w.nii.gz ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.nii.gz
  SUBJECTS_DIR=${T1wFolder}

##Done with Bene's Changes #########################################################################################################################################################################

  #echo ${FREESURFER_HOME}/bin/bbregister --s ${Subject} --mov ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.nii.gz --surf white --init-reg ${T1wFolder}/mri/transforms/eye.dat --bold --reg ${fMRIFolder}/EPItoT1w.dat --o ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w.nii.gz
  #${FREESURFER_HOME}/bin/bbregister --s ${Subject} --mov ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.nii.gz --surf white --init-reg ${T1wFolder}/mri/transforms/eye.dat --bold --reg    ${fMRIFolder}/EPItoT1w.dat --o ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w.nii.gz
  # Create FSL-style matrix and then combine with existing warp fields




  #echo ${FREESURFER_HOME}/bin/tkregister2 --noedit --reg ${fMRIFolder}/EPItoT1w.dat --mov ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.nii.gz --targ ${T1wFolder}/${T1wRestoreImageBrain}.nii.gz --fslregout ${fMRIFolder}/fMRI2str.mat
  #${FREESURFER_HOME}/bin/tkregister2 --noedit --reg ${fMRIFolder}/EPItoT1w.dat --mov ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init.nii.gz --targ ${T1wFolder}/${T1wRestoreImageBrain}.nii.gz --fslregout ${fMRIFolder}/fMRI2str.mat

  #${FSLDIR}/bin/convertwarp --relout --rel --warp1=${fMRIFolder}/${ScoutName}_undistorted2T1w_init_warp.nii.gz --ref=${T1wFolder}/${T1wImage} --postmat=${fMRIFolder}/fMRI2str.mat --out=${T1wFolder}/xfms/${fMRI2strOutputTransform}

  #@TODO re-evaluate: this xfm may be lackluster compared to a proper bbr.  We could try the resolved bbr from WashU's pipe.
  cp ${fMRIFolder}/${ScoutName}_gdc_undistorted2T1w_init_warp.nii.gz ${T1wFolder}/xfms/${fMRI2strOutputTransform}.nii.gz
  imcp ${fMRIFolder}/Jacobian2T1w.nii.gz ${fMRIFolder}/$JacobianOut #  this is the proper "JacobianOut" for input into OneStepResampling.

  elif ${PreviousRegistration}; then
    #  take bold results, as they tend to be more accurate transforms until we can improve them.  Combine rigid ferumox -> bold
    echo "using ${PreviousTask} to calculate ${NameOffMRI} registration to anatomical"
    PrevTaskFolder="$Path"/${PreviousTask}
    Lin2PrevTask="${fMRIFolder}"/${PreviousTask}_2_${NameOffMRI}.mat
    flirt -in "${fMRIFolder}"/Scout_orig.nii.gz -cost mutualinfo -dof 6 -ref "${PrevTaskFolder}"/Scout_orig.nii.gz -omat ${Lin2PrevTask}
    PrevTaskTransform=${PreviousTask}2str
    imcp "$PrevTaskFolder"/"$JacobianOut" "$fMRIFolder"/"$JacobianOut"
    convertwarp --rel --relout --out=${T1wFolder}/xfms/${fMRI2strOutputTransform}.nii.gz --warp1=${T1wFolder}/xfms/${PrevTaskTransform}.nii.gz --premat=${Lin2PrevTask} --ref=${T1wFolder}/${T1wImage}
  fi

else
	# fake jacobian out
	# DFM is still being applied from CYA, will put DFM procedure here later.
	fslmaths ${T1wFolder}/${T1wImage} -abs -add 1 -bin ${fMRIFolder}/${JacobianOut}
fi


echo "RUNNING ONE STEP RESAMPLING"
#One Step Resampling
mkdir -p ${fMRIFolder}/OneStepResampling
echo ${RUN} ${PipelineScripts}/OneStepResampling.sh \
    --workingdir=${fMRIFolder}/OneStepResampling \
    --infmri=${fMRIFolder}/${OrigTCSName}.nii.gz \
    --t1=${AtlasSpaceFolder}/${T1wAtlasName} \
    --fmriresout=${FinalfMRIResolution} \
    --fmrifolder=${fMRIFolder} \
    --fmri2structin=${T1wFolder}/xfms/${fMRI2strOutputTransform} \
    --struct2std=${AtlasSpaceFolder}/xfms/${AtlasTransform} \
    --owarp=${AtlasSpaceFolder}/xfms/${OutputfMRI2StandardTransform} \
    --oiwarp=${AtlasSpaceFolder}/xfms/${Standard2OutputfMRITransform} \
    --motionmatdir=${fMRIFolder}/${MotionMatrixFolder} \
    --motionmatprefix=${MotionMatrixPrefix} \
    --ofmri=${fMRIFolder}/${NameOffMRI}_nonlin \
    --freesurferbrainmask=${AtlasSpaceFolder}/${FreeSurferBrainMask} \
    --biasfield=${AtlasSpaceFolder}/${BiasFieldMNI} \
    --gdfield=${fMRIFolder}/${NameOffMRI}_gdc_warp \
    --scoutin=${fMRIFolder}/${OrigScoutName} \
    --scoutgdcin=${fMRIFolder}/${ScoutName}_gdc \
    --oscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin \
    --jacobianin=${fMRIFolder}/${JacobianOut} \
    --ojacobian=${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution}

${RUN} ${PipelineScripts}/OneStepResampling.sh \
    --workingdir=${fMRIFolder}/OneStepResampling \
    --infmri=${fMRIFolder}/${OrigTCSName}.nii.gz \
    --t1=${AtlasSpaceFolder}/${T1wAtlasName} \
    --fmriresout=${FinalfMRIResolution} \
    --fmrifolder=${fMRIFolder} \
    --fmri2structin=${T1wFolder}/xfms/${fMRI2strOutputTransform} \
    --struct2std=${AtlasSpaceFolder}/xfms/${AtlasTransform} \
    --owarp=${AtlasSpaceFolder}/xfms/${OutputfMRI2StandardTransform} \
    --oiwarp=${AtlasSpaceFolder}/xfms/${Standard2OutputfMRITransform} \
    --motionmatdir=${fMRIFolder}/${MotionMatrixFolder} \
    --motionmatprefix=${MotionMatrixPrefix} \
    --ofmri=${fMRIFolder}/${NameOffMRI}_nonlin \
    --freesurferbrainmask=${AtlasSpaceFolder}/${FreeSurferBrainMask} \
    --biasfield=${AtlasSpaceFolder}/${BiasFieldMNI} \
    --gdfield=${fMRIFolder}/${NameOffMRI}_gdc_warp \
    --scoutin=${fMRIFolder}/${OrigScoutName} \
    --scoutgdcin=${fMRIFolder}/${ScoutName}_gdc \
    --oscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin \
    --jacobianin=${fMRIFolder}/${JacobianOut} \
    --ojacobian=${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution}


echo "RUNNING INTENSITY NORMALIZATION & BIAS REMOVAL"
#Intensity Normalization and Bias Removal
### ERIC'S DEBUGGING ECHO ###
echo ${RUN} ${PipelineScripts}/IntensityNormalization.sh \
    --infmri=${fMRIFolder}/${NameOffMRI}_nonlin \
    --biasfield=${fMRIFolder}/${BiasFieldMNI}.${FinalfMRIResolution} \
    --jacobian=${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution} \
    --brainmask=${fMRIFolder}/${FreeSurferBrainMask}.${FinalfMRIResolution} \
    --ofmri=${fMRIFolder}/${NameOffMRI}_nonlin_norm \
    --inscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin \
    --oscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin_norm \
    --usejacobian=false
${RUN} ${PipelineScripts}/IntensityNormalization.sh \
    --infmri=${fMRIFolder}/${NameOffMRI}_nonlin \
    --biasfield=${fMRIFolder}/${BiasFieldMNI}.${FinalfMRIResolution} \
    --jacobian=${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution} \
    --brainmask=${fMRIFolder}/${FreeSurferBrainMask}.${FinalfMRIResolution} \
    --ofmri=${fMRIFolder}/${NameOffMRI}_nonlin_norm \
    --inscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin \
    --oscout=${fMRIFolder}/${NameOffMRI}_SBRef_nonlin_norm \
    --usejacobian=false

mkdir -p ${ResultsFolder}
# MJ QUERY: WHY THE -r OPTIONS BELOW?
${RUN} cp -r ${fMRIFolder}/${NameOffMRI}_nonlin_norm.nii.gz ${ResultsFolder}/${NameOffMRI}.nii.gz
${RUN} cp -r ${fMRIFolder}/${MovementRegressor}.txt ${ResultsFolder}/${MovementRegressor}.txt
${RUN} cp -r ${fMRIFolder}/${MovementRegressor}_dt.txt ${ResultsFolder}/${MovementRegressor}_dt.txt
${RUN} cp -r ${fMRIFolder}/${NameOffMRI}_SBRef_nonlin_norm.nii.gz ${ResultsFolder}/${NameOffMRI}_SBRef.nii.gz
${RUN} cp -r ${fMRIFolder}/${JacobianOut}_MNI.${FinalfMRIResolution}.nii.gz ${ResultsFolder}/${NameOffMRI}_${JacobianOut}.nii.gz
###Add stuff for RMS###
${RUN} cp -r ${fMRIFolder}/Movement_RelativeRMS.txt ${ResultsFolder}/Movement_RelativeRMS.txt
${RUN} cp -r ${fMRIFolder}/Movement_AbsoluteRMS.txt ${ResultsFolder}/Movement_AbsoluteRMS.txt
${RUN} cp -r ${fMRIFolder}/Movement_RelativeRMS_mean.txt ${ResultsFolder}/Movement_RelativeRMS_mean.txt
${RUN} cp -r ${fMRIFolder}/Movement_AbsoluteRMS_mean.txt ${ResultsFolder}/Movement_AbsoluteRMS_mean.txt
###Add stuff for RMS###

echo "-------------------------------"
echo "END OF fMRI-VOLUME-PROCESSING.sh SCRIPT"
echo "Please Verify Clean Error File"
