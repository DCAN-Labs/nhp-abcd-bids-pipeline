#!/bin/bash -x

set -ex
export OMP_NUM_THREADS=1
export PATH=$(echo $PATH | sed 's|freesurfer/|freesurfer53/|g')

# Requirements for this script
#  installed versions of: FSL5.0.1 or higher , FreeSurfer (version 5 or higher) , gradunwarp (python code from MGH)
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR , PATH (for gradient_unwarp.py)

# make pipeline engine happy...
if [ $# -eq 1 ]; then
  echo "Version unknown..."
  exit 0
fi

########################################## PIPELINE OVERVIEW ##########################################

#TODO

########################################## OUTPUT DIRECTORIES ##########################################

## NB: NO assumption is made about the input paths with respect to the output directories - they can be totally different.  All input are taken directly from the input variables without additions or modifications.
# NB: Output directories T1wFolder and T2wFolder MUST be different (as various output subdirectories containing standardly named files, e.g. full2std.mat, would overwrite each other) so if this script is modified, then keep these output directories distinct
# Output path specifiers:
#
# ${StudyFolder} is an input parameter
# ${Subject} is an input parameter
#
# Main output directories
# T1wFolder=${StudyFolder}/T1w
# T2wFolder=${StudyFolder}/T2w
# AtlasSpaceFolder=${StudyFolder}/MNINonLinear
#
# All outputs are within the directory: ${StudyFolder}/
# The list of output directories are the following
#
#    T1w/T1w${i}_GradientDistortionUnwarp
#    T1w/AverageT1wImages
#    T1w/ACPCAlignment
#    T1w/BrainExtraction_FNIRTbased
# and the above for T2w as well (s/T1w/T2w/g)
#
#    T2w/T2wToT1wDistortionCorrectAndReg
#    T1w/BiasFieldCorrection_sqrtT1wXT1w
#    MNINonLinear
#
# Also exist:
#    T1w/xfms/
#    T2w/xfms/
#    MNINonLinear/xfms/
#

# Paths for scripts etc (uses variables defined in SetUpHCPPipeline.sh)
PipelineScripts=${HCPPIPEDIR_PreFS}
GlobalScripts=${HCPPIPEDIR_Global}

###################################### LOAD FUNCTION LIBRARIES ######################################

source $GlobalScripts/log.shlib  # Logging related functions
source $GlobalScripts/opts.shlib # Command line option functions

#  Establish tool name for logging
log_SetToolName "PreFreeSurferPipeline.sh"

########################################## SUPPORT FUNCTIONS ##########################################
# function for parsing options
getopt1() {
  sopt="$1"
  shift 1
  for fn in $@; do
    if [ $(echo $fn | grep -- "^${sopt}=" | wc -w) -gt 0 ]; then
      echo $fn | sed "s/^${sopt}=//"
      return 0
    fi
  done
}
defaultopt() {
  echo $1
}

# Supply a file's path. Optionally, supply the line number.
assert_file_exists() {
  if [ -e ${1} ]; then
    : # all is well
  else
    # Assertion failed.
    log_Msg "Error. File does not exist: ${1}"
    if [ -n "${2}" ]; then
      log_Msg "$0, line $2"
    fi
    exit 1
  fi
}

################################################## OPTION PARSING #####################################################

# Input Variables
StudyFolder=$(getopt1 "--path" $@)                     # "$1" #Path to subject's data folder
Subject=$(getopt1 "--subject" $@)                      # "$2" #SubjectID
T1wInputImages=$(getopt1 "--t1" $@)                    # "$3" #T1w1@T1w2@etc..
T2wInputImages=$(getopt1 "--t2" $@)                    # "$4" #T2w1@T2w2@etc..
T1wTemplate=$(getopt1 "--t1template" $@)               # "$5" #MNI template
T1wTemplateBrain=$(getopt1 "--t1templatebrain" $@)     # "$6" #Brain extracted MNI T1wTemplate
T1wTemplate2mm=$(getopt1 "--t1template2mm" $@)         # "$7" #MNI2mm T1wTemplate
T2wTemplate=$(getopt1 "--t2template" $@)               # "${8}" #MNI T2wTemplate
T2wTemplateBrain=$(getopt1 "--t2templatebrain" $@)     # "$9" #Brain extracted MNI T2wTemplate
T2wTemplate2mm=$(getopt1 "--t2template2mm" $@)         # "${10}" #MNI2mm T2wTemplate
TemplateMask=$(getopt1 "--templatemask" $@)            # "${11}" #Brain mask MNI Template
Template2mmMask=$(getopt1 "--template2mmmask" $@)      # "${12}" #Brain mask MNI2mm Template
BrainSize=$(getopt1 "--brainsize" $@)                  # "${13}" #StandardFOV mask for averaging structurals
FNIRTConfig=$(getopt1 "--fnirtconfig" $@)              # "${14}" #FNIRT 2mm T1w Config
MagnitudeInputName=$(getopt1 "--fmapmag" $@)           # "${16}" #Expects 4D magitude volume with two 3D timepoints
MagnitudeInputBrainName=$(getopt1 "--fmapmagbrain" $@) # If you've already masked the magnitude.
PhaseInputName=$(getopt1 "--fmapphase" $@)             # "${17}" #Expects 3D phase difference volume
TE=$(getopt1 "--echodiff" $@)                          # "${18}" #delta TE for field map
SpinEchoPhaseEncodeNegative=$(getopt1 "--SEPhaseNeg" $@)
SpinEchoPhaseEncodePositive=$(getopt1 "--SEPhasePos" $@)
DwellTime=$(getopt1 "--echospacing" $@)
SEUnwarpDir=$(getopt1 "--seunwarpdir" $@)
T1wSampleSpacing=$(getopt1 "--t1samplespacing" $@)  # "${19}" #DICOM field (0019,1018)
T2wSampleSpacing=$(getopt1 "--t2samplespacing" $@)  # "${20}" #DICOM field (0019,1018)
UnwarpDir=$(getopt1 "--unwarpdir" $@)               # "${21}" #z appears to be best
GradientDistortionCoeffs=$(getopt1 "--gdcoeffs" $@) # "${25}" #Select correct coeffs for scanner or "NONE" to turn off
AvgrdcSTRING=$(getopt1 "--avgrdcmethod" $@)         # "${26}" #Averaging and readout distortion correction methods: "NONE" = average any repeats with no readout correction "FIELDMAP" = average any repeats and use field map for readout correction "TOPUP" = average and distortion correct at the same time with topup/applytopup only works for 2 images currently
TopupConfig=$(getopt1 "--topupconfig" $@)           # "${27}" #Config for topup or "NONE" if not used
BiasFieldSmoothingSigma=$(getopt1 "--bfsigma" $@)   # "$9"
RUN=$(getopt1 "--printcom" $@)                      # use ="echo" for just printing everything and not running the commands (default is to run)
useT2=$(getopt1 "--useT2" $@)                       # useT2 flag added for excluding or including T2 processing, grabbed from batch file
T1wNormalized=$(getopt1 "--t1normalized" $@)        # brain normalized to matter intensities
useReverseEpi=$(getopt1 "--revepi" $@)
MultiTemplateDir=$(getopt1 "--multitemplatedir" $@)
T1BrainMask=$(getopt1 "--t1brainmask" $@) # optional user-specified T1 mask
T2BrainMask=$(getopt1 "--t2brainmask" $@) # optional user-specified T2 mask
StudyTemplate=$(getopt1 "--StudyTemplate" $@) # optional user-specified study template
StudyTemplateBrain=$(getopt1 "--StudyTemplateBrain" $@) # optional user-specified study template brain
ASegDir=$(getopt1 "--asegdir" $@) # directory of optional user-specified segmentation (aseg_acpc.nii.gz)
T1RegMethod=$(getopt1 "--t1regmethod" $@) # method to register T1w to reference (choices: FLIRT_FNIRT, ANTS, ANTS_NO_INTERMEDIATE)

if [ -n "${T1BrainMask}" ] && [[ "${T1BrainMask^^}" == "NONE" ]]; then
  unset T1BrainMask
elif [ -n "${T1BrainMask}" ]; then
  log_Msg User supplied T1BrainMask is ${T1BrainMask}.
  assert_file_exists ${T1BrainMask} ${LINENO}
fi

if [ -n "${T2BrainMask}" ] && [[ "${T2BrainMask^^}" == "NONE" ]]; then
  unset T2BrainMask
elif [ -n "${T2BrainMask}" ]; then
  log_Msg User supplied T2BrainMask is ${T2BrainMask}.
  assert_file_exists ${T2BrainMask} ${LINENO}
fi

# Defaults
T1wNormalized=${T1wNormalized:-"NONE"}

echo "$StudyFolder $Subject"
pushd ${StudyFolder}

# Naming Conventions ... OMD these will likely have to be modified for OHSU
T1wImage="T1w"
T1wFolder="T1w" #Location of T1w images
if $useT2; then
  T2wImage="T2w"
  T2wFolder="T2w"
fi
#**T1wNFolder="T1wN" #Location of T1w Normalized Images
if [ ! $T1wNormalized = "NONE" ]; then
  T1wNImage="T1wN"
fi
AtlasSpaceFolder="MNINonLinear"

# Build Paths, OMD: Outputs, ie calculated data
T1wFolder=${StudyFolder}/${T1wFolder}
if $useT2; then
  T2wImage="T2w"
  T2wFolder=${StudyFolder}/${T2wFolder}
fi
#**T1wNFolder=${StudyFolder}/${T1wNFolder}
AtlasSpaceFolder=${StudyFolder}/${AtlasSpaceFolder}

echo "$T1wFolder $T2wFolder $T1wNFolder $AtlasSpaceFolder"

# Unpack List of Images
T1wInputImages=$(echo ${T1wInputImages} | sed 's/@/ /g')                     #File and path to the T1 MPRG, space separated, OMD
if $useT2; then T2wInputImages=$(echo ${T2wInputImages} | sed 's/@/ /g'); fi #File and path to the T2 MPRG, space separated, OMD

pushd ${StudyFolder}/

if [ ! -e ${T1wFolder}/xfms ]; then
  echo "mkdir -p ${T1wFolder}/xfms/"
  mkdir -p ${T1wFolder}/xfms/
fi
# Placing T1wN niftis in T1w folder -Dakota 10/26/17
# if [ ! -e ${T1wNFolder}/xfms ]; then
#   echo "mkdir -p ${T1wNFolder}/xfms/"
#   mkdir -p ${T1wNFolder}/xfms/
#fi
if $useT2; then
  if [ ! -e ${T2wFolder}/xfms ]; then
    echo "mkdir -p ${T2wFolder}/xfms/"
    mkdir -p ${T2wFolder}/xfms/
  fi
fi

if [ ! -e ${AtlasSpaceFolder}/xfms ]; then
  echo "mkdir -p ${AtlasSpaceFolder}/xfms/"
  mkdir -p ${AtlasSpaceFolder}/xfms/
fi

echo "POSIXLY_CORRECT="${POSIXLY_CORRECT}

########################################## DO WORK ##########################################

######## LOOP over the same processing for T1w and T2w (just with different names) ########
if $useT2; then Modalities="T1w T2w"; else Modalities="T1w"; fi #Removed T1wN -Dakota 10/26/17
#bene added T1wN to modalities 6-20-17 but commented it out for now as I didn't know if that makes sense.
#if $useT2; then Modalities="T1w T2w T1wN"; else Modalities="T1w T1wN"; fi
#commented out T1wN steps -Dakota 10/26/17

for TXw in ${Modalities}; do
  # set up appropriate input variables
  if [ $TXw = T1w ]; then
    TXwInputImages="${T1wInputImages}"
    TXwFolder=${T1wFolder}
    TXwImage=${T1wImage}       #T1W, OMD
    TXwTemplate=${T1wTemplate} # It points to the template at 0.7 mm skull+brain, OMD (Remember, scan was performed at 0.7mm isotropic)
    TXwTemplateBrain=${T1wTemplateBrain}
    TXwTemplate2mm=${T1wTemplate2mm} # It points to the template at 2.0 mm skull+brain, OMD (Remember, scan was performed at 0.7mm isotropic)
    TXwExt=${Subject}_T1w_MPR_average
    if [ -n "${T1BrainMask}" ]; then
      TXwBrainMask=${T1BrainMask}
    fi
  elif [ $TXw = T2w ]; then
    TXwInputImages="${T2wInputImages}"
    TXwFolder=${T2wFolder}
    TXwImage=${T2wImage}
    TXwTemplate=${T2wTemplate}
    TXwTemplateBrain=${T2wTemplateBrain}
    TXwTemplate2mm=${T2wTemplate2mm}
    TXwExt=${Subject}_T2w_SPC_average
    if [ -n "${T2BrainMask}" ]; then
      TXwBrainMask=${T2BrainMask}
    fi
  #**  elif [ $TXw = T1wN ]; then
  #    TXwInputImages="${T1wNInputImages}"
  #    TXwFolder=${T1wNFolder}
  #    TXwImage=${T1wNImage} #T1W  Normalized
  #    TXwTemplate=${T1wTemplate} # It points to the template at 0.7 mm skull+brain, OMD (Remember, scan was performed at 0.7mm isotropic)
  #    TXwTemplateBrain=${T1wTemplateBrain}
  #    TXwTemplate2mm=${T1wTemplate2mm} # It points to the template at 2.0 mm skull+brain, OMD (Remember, scan was performed at 0.7mm isotropic)
  #    TXwExt=${Subject}_T1w_MPR_average_AdultInt
  fi
  OutputTXwImageSTRING=""

  #### Gradient nonlinearity correction  (for T1w and T2w) ####

  if [ ! $GradientDistortionCoeffs = "NONE" ]; then
    i=1
    for Image in $TXwInputImages; do
      wdir=${TXwFolder}/${TXwImage}${i}_GradientDistortionUnwarp
      echo "mkdir -p $wdir"
      mkdir -p $wdir
      ${RUN} ${FSLDIR}/bin/fslreorient2std $Image ${wdir}/${TXwImage}${i} #Make sure input axes are oriented the same as the templates
      ${RUN} ${GlobalScripts}/GradientDistortionUnwarp.sh \
      --workingdir=${wdir} \
      --coeffs=$GradientDistortionCoeffs \
      --in=${wdir}/${TXwImage}${i} \
      --out=${TXwFolder}/${TXwImage}${i}_gdc \
      --owarp=${TXwFolder}/xfms/${TXwImage}${i}_gdc_warp
      OutputTXwImageSTRING="${OutputTXwImageSTRING}${TXwFolder}/${TXwImage}${i}_gdc "
      i=$(($i + 1))
    done

  else
    echo "NOT PERFORMING GRADIENT DISTORTION CORRECTION"
    i=1
    for Image in $TXwInputImages; do
      ${RUN} ${FSLDIR}/bin/fslreorient2std $Image ${TXwFolder}/${TXwImage}${i}_gdc
      OutputTXwImageSTRING="${OutputTXwImageSTRING}${TXwFolder}/${TXwImage}${i}_gdc "
      i=$(($i + 1))
    done
  fi

  #### Average Like Scans ####

  if [ $(echo $TXwInputImages | wc -w) -gt 1 ]; then
    mkdir -p ${TXwFolder}/Average${TXw}Images
    #if [ ${AvgrdcSTRING} = "TOPUP" ] ; then
    #    echo "PERFORMING TOPUP READOUT DISTORTION CORRECTION AND AVERAGING"
    #    ${RUN} ${PipelineScripts}/TopupDistortionCorrectAndAverage.sh ${TXwFolder}/Average${TXw}Images "${OutputTXwImageSTRING}" ${TXwFolder}/${TXwImage} ${TopupConfig}
    #else
    echo "PERFORMING SIMPLE AVERAGING"
    ${RUN} ${PipelineScripts}/AnatomicalAverage.sh -o ${TXwFolder}/${TXwImage} -s ${TXwTemplate} -m ${TemplateMask} \
    -n -w ${TXwFolder}/Average${TXw}Images --noclean -v -b $BrainSize $OutputTXwImageSTRING
    #fi
    ###Added by Bene to use created warp above and apply it to the brain
    ${FSLDIR}/bin/fslmaths ${TXwFolder}/${TXwImage}_brain -bin ${TXwFolder}/${TXwImage}_mask
    ${FSLDIR}/bin/fslmaths ${TXwFolder}/${TXwImage}_brain -bin ${TXwFolder}/${TXwImage}_mask_rot2first #take this out once done testing just something for QC for now
    $FSLDIR/bin/applywarp --rel -i ${TXwFolder}/${TXwImage}_mask --premat=${TXwFolder}/Average${TXw}Images/ToHalfTrans0001.mat -r ${TXwFolder}/${TXwImage} -o ${TXwFolder}/${TXwImage}_mask --interp=nn
    ${FSLDIR}/bin/fslmaths ${TXwFolder}/${TXwImage} -mas ${TXwFolder}/${TXwImage}_mask ${TXwFolder}/${TXwImage}_brain
    ### Done with edits by Bene
  else
    echo "ONLY ONE AVERAGE FOUND: COPYING"
    ${RUN} ${FSLDIR}/bin/imcp ${TXwFolder}/${TXwImage}1_gdc ${TXwFolder}/${TXwImage}
  fi

  #### ACPC align T1w and T2w image to 0.7mm MNI T1wTemplate to create native volume space ####
  #**  if [ ! $TXw = "T1wN" ]; then
  mkdir -p ${TXwFolder}/ACPCAlignment
  # Assume Brain has been placed in T1w from Prep stage.
  ${RUN} ${PipelineScripts}/ACPCAlignment.sh \
  --workingdir=${TXwFolder}/ACPCAlignment \
  --in=${TXwFolder}/${TXwImage}_brain \
  --ref=${TXwTemplateBrain} \
  --out=${TXwFolder}/${TXwImage}_acpc_brain \
  --omat=${TXwFolder}/xfms/acpc.mat \
  --brainsize=${BrainSize}
  # Apply linear transform to head.
  #  flirt -in ${TXwFolder}/${TXwImage}_brain -ref ${TXwTemplate} -applyxfm -init ${TXwFolder}/xfms/acpc.mat -out ${TXwFolder}/${TXwImage}_acpc_brain
  #  ${FSLDIR}/bin/fslmaths ${TXwFolder}/${TXwImage}_acpc_brain -bin ${TXwFolder}/${TXwImage}_acpc_brain_mask
  #**  else
  # ensure that the same T1w transform is applied to normed brain.
  #    echo "applying acpc warp to Normalized image"
  #    cp ${T1wFolder}/xfms/acpc.mat ${TXwFolder}/xfms/acpc.mat
  #    ${FSLDIR}/bin/applywarp --rel --interp=spline -i "${TXwFolder}/${TXwImage}" -r "${TXwTemplate}" \
  #    --premat="${TXwFolder}/xfms/acpc.mat" -o "${TXwFolder}/${TXwImage}_acpc"
  #  fi

  #### Brain Extraction (FNIRT-based Masking) ####

  ############ FNL - this is performed using ANTs in Prep
  #  mkdir -p ${TXwFolder}/BrainExtraction_FNIRTbased
  #  ${RUN} ${PipelineScripts}/BrainExtraction_FNIRTbased.sh \
  #			--workingdir=${TXwFolder}/BrainExtraction_ANTsbased \
  #			--in=${TXwFolder}/${TXwImage}_acpc \
  #			--ref=${TXwTemplate} \
  #			--refmask=${TemplateMask} \
  #			--ref2mm=${TXwTemplate2mm} \
  #			--ref2mmmask=${Template2mmMask} \
  #			--outbrain=${TXwFolder}/${TXwImage}_acpc_brain \
  #			--outbrainmask=${TXwFolder}/${TXwImage}_acpc_brain_mask \
  #			--fnirtconfig=${FNIRTConfig};
  #    ${FSLDIR}/bin/flirt -in ${TXwFolder}/${TXwImage}_brain -ref ${TXwTemplate} -applyxfm -init ${TXwFolder}/xfms/acpc.mat -out ${TXwFolder}/${TXwImage}_acpc_brain
  #    ${FSLDIR}/bin/fslmaths ${TXwFolder}/${TXwImage}_acpc_brain -bin ${TXwFolder}/${TXwImage}_acpc_brain_mask
  #**   if [ $TXw = T1wN ]; then ${FSLDIR}/bin/fslmaths ${TXwFolder}/${TXwImage}_acpc -mas ${T1wFolder}/${T1wImage}_acpc_brain_mask ${TXwFolder}/${TXwImage}_acpc_brain; fi
  #apply acpc.mat to head
  ${FSLDIR}/bin/applywarp --rel --interp=spline -i "${TXwFolder}/${TXwImage}" -r "${TXwTemplate}" \
  --premat="${TXwFolder}/xfms/acpc.mat" -o "${TXwFolder}/${TXwImage}_acpc"

  # Thomas edit 12/23/2020: use user-specified mask
  if [ -n "${TXwBrainMask}" ]; then
    # The user has supplied a TXw brain mask.
    # Extract the TXw brain.

    # Copy the user-supplied mask to ${TXwFolder}/${TXwImage}_brain_mask.
    imcp ${TXwBrainMask} ${TXwFolder}/${TXwImage}_brain_mask

    # The TXw head was ACPC aligned above. Use the resulting
    # acpc.mat to align the mask.
    ${FSLDIR}/bin/applywarp --rel --interp=nn -i ${TXwFolder}/${TXwImage}_brain_mask -r ${TXwTemplateBrain} --premat=${TXwFolder}/xfms/acpc.mat -o ${TXwFolder}/${TXwImage}_acpc_brain_mask

    # Use the ACPC aligned TXw brain mask to extract the TXw brain.
    ${FSLDIR}/bin/fslmaths ${TXwFolder}/${TXwImage}_acpc -mas ${TXwFolder}/${TXwImage}_acpc_brain_mask ${TXwFolder}/${TXwImage}_acpc_brain

  else
    #Bene alternative fix added: apply warp to mask, then make brain mask and use it to mask T1w acpc
    ${FSLDIR}/bin/applywarp --rel --interp=nn -i ${TXwFolder}/${TXwImage}_mask -r ${TXwTemplateBrain} --premat=${TXwFolder}/xfms/acpc.mat -o ${TXwFolder}/${TXwImage}_acpc_brain_mask
    ${FSLDIR}/bin/fslmaths ${TXwFolder}/${TXwImage}_acpc -mas ${TXwFolder}/${TXwImage}_acpc_brain_mask ${TXwFolder}/${TXwImage}_acpc_brain
    #make brain mask taken out by Bene and replaced with above
    #${FSLDIR}/bin/fslmaths ${TXwFolder}/${TXwImage}_acpc_brain -bin ${TXwFolder}/${TXwImage}_acpc_brain_mask
  fi
done

######## END LOOP over T1w and T2w #########

#Orient T1wN image to standard and create ACPC aligned T1wN image
if [ ! $T1wNormalized = "NONE" ]; then
  pushd ${T1wFolder} >/dev/null
  cp ${T1wNormalized} ./${T1wNImage}.nii.gz
  ${RUN} ${FSLDIR}/bin/fslreorient2std ./${T1wNImage} ${T1wFolder}/${T1wNImage}1_gdc
  ${RUN} ${FSLDIR}/bin/imcp ${T1wFolder}/${T1wNImage}1_gdc ${T1wFolder}/${T1wNImage}

  ${FSLDIR}/bin/applywarp --rel --interp=spline -i "${T1wFolder}/${T1wNImage}" -r "${T1wTemplate}" \
  --premat="${T1wFolder}/xfms/acpc.mat" -o "${T1wFolder}/${T1wNImage}_acpc"
  ${FSLDIR}/bin/fslmaths ${T1wFolder}/${T1wNImage}_acpc -mas ${T1wFolder}/${T1wImage}_acpc_brain_mask ${T1wFolder}/${T1wNImage}_acpc_brain
  popd >/dev/null
fi

if ${useReverseEpi:-false}; then
  #  Time is too long for Resting State, so we average it first.
  mcflirt "$SpinEchoPhaseEncodeNegative" -out "$T1wFolder"/tmp_REST_mc.nii.gz
  fslmaths "$T1wFolder"/tmp_REST_mc.nii.gz -Tmean "$T1wFolder"/PEForwardScout.nii.gz
  SpinEchoPhaseEncodeNegative="$T1wFolder"/PEForwardScout.nii.gz
  rm "$T1wFolder"/tmp_REST_mc.nii.gz
fi

#### T2w to T1w Registration and Optional Readout Distortion Correction ####
if $useT2; then
  if [[ ${AvgrdcSTRING} = "FIELDMAP" || ${AvgrdcSTRING} = "TOPUP" ]]; then
    echo "PERFORMING ${AvgrdcSTRING} READOUT DISTORTION CORRECTION"
    wdir=${T2wFolder}/T2wToT1wDistortionCorrectAndReg
    if [ -d ${wdir} ]; then
      # DO NOT change the following line to "rm -r ${wdir}" because the chances of something going wrong with that are much higher, and rm -r always needs to be treated with the utmost caution
      rm -r ${T2wFolder}/T2wToT1wDistortionCorrectAndReg
    fi
    mkdir -p ${wdir}

    ${RUN} ${PipelineScripts}/T2wToT1wDistortionCorrectAndReg.sh \
    --workingdir=${wdir} \
    --t1=${T1wFolder}/${T1wImage}_acpc \
    --t1brain=${T1wFolder}/${T1wImage}_acpc_brain \
    --t2=${T2wFolder}/${T2wImage}_acpc \
    --t2brain=${T2wFolder}/${T2wImage}_acpc_brain \
    --fmapmag=${MagnitudeInputName} \
    --fmapmagbrain=${MagnitudeInputBrainName} \
    --fmapphase=${PhaseInputName} \
    --echodiff=${TE} \
    --SEPhaseNeg=${SpinEchoPhaseEncodeNegative} \
    --SEPhasePos=${SpinEchoPhaseEncodePositive} \
    --echospacing=${DwellTime} \
    --seunwarpdir=${SEUnwarpDir} \
    --t1sampspacing=${T1wSampleSpacing} \
    --t2sampspacing=${T2wSampleSpacing} \
    --unwarpdir=${UnwarpDir} \
    --ot1=${T1wFolder}/${T1wImage}_acpc_dc \
    --ot1brain=${T1wFolder}/${T1wImage}_acpc_dc_brain \
    --ot1warp=${T1wFolder}/xfms/${T1wImage}_dc \
    --ot2=${T1wFolder}/${T2wImage}_acpc_dc \
    --ot2warp=${T1wFolder}/xfms/${T2wImage}_reg_dc \
    --method=${AvgrdcSTRING} \
    --topupconfig=${TopupConfig} \
    --gdcoeffs=${GradientDistortionCoeffs}
  else
    wdir=${T2wFolder}/T2wToT1wReg
    if [ -e ${wdir} ]; then
      # DO NOT change the following line to "rm -r ${wdir}" because the chances of something going wrong with that are much higher, and rm -r always needs to be treated with the utmost caution
      rm -r ${T2wFolder}/T2wToT1wReg
    fi
    mkdir -p ${wdir}
    ${RUN} ${PipelineScripts}/T2wToT1wReg.sh \
    ${wdir} \
    ${T1wFolder}/${T1wImage}_acpc \
    ${T1wFolder}/${T1wImage}_acpc_brain \
    ${T2wFolder}/${T2wImage}_acpc \
    ${T2wFolder}/${T2wImage}_acpc_brain \
    ${T1wFolder}/${T1wImage}_acpc_dc \
    ${T1wFolder}/${T1wImage}_acpc_dc_brain \
    ${T1wFolder}/xfms/${T1wImage}_dc \
    ${T1wFolder}/${T2wImage}_acpc_dc \
    ${T1wFolder}/xfms/${T2wImage}_reg_dc
  fi
else
  imcp ${T1wFolder}/${T1wImage}_acpc ${T1wFolder}/${T1wImage}_acpc_dc
  imcp ${T1wFolder}/${T1wImage}_acpc_brain ${T1wFolder}/${T1wImage}_acpc_dc_brain
fi

#### Bias Field Correction: Calculate bias field using square root of the product of T1w and T2w iamges.  ####
if $useT2; then
  if [ ! -z ${BiasFieldSmoothingSigma} ]; then
    BiasFieldSmoothingSigma="--bfsigma=${BiasFieldSmoothingSigma}"
  fi
  mkdir -p ${T1wFolder}/BiasFieldCorrection_sqrtT1wXT1w
  ${RUN} ${PipelineScripts}/BiasFieldCorrection_sqrtT1wXT1w.sh \
  --workingdir=${T1wFolder}/BiasFieldCorrection_sqrtT1wXT1w \
  --T1im=${T1wFolder}/${T1wImage}_acpc_dc \
  --T1brain=${T1wFolder}/${T1wImage}_acpc_dc_brain \
  --T2im=${T1wFolder}/${T2wImage}_acpc_dc \
  --obias=${T1wFolder}/BiasField_acpc_dc \
  --oT1im=${T1wFolder}/${T1wImage}_acpc_dc_restore \
  --oT1brain=${T1wFolder}/${T1wImage}_acpc_dc_restore_brain \
  --oT2im=${T1wFolder}/${T2wImage}_acpc_dc_restore \
  --oT2brain=${T1wFolder}/${T2wImage}_acpc_dc_restore_brain \
  ${BiasFieldSmoothingSigma}
else
  imcp ${T1wFolder}/${T1wImage}_acpc_dc ${T1wFolder}/${T1wImage}_acpc_dc_restore
  imcp ${T1wFolder}/${T1wImage}_acpc_dc_brain ${T1wFolder}/${T1wImage}_acpc_dc_restore_brain
fi

# Run ANTS Atlas Registration using T1w acpc brain mask

if [ "${T1RegMethod}" = "ANTS_NO_INTERMEDIATE" ] ; then
  # ------------------------------------------------------------------------------
  #  Atlas Registration to MNI152: ANTs-based (no intermediate registration)
  #  Also applies registration to T1w and T2w images
  #  Modified 20170330 by EF to include the option for a native mask in registration
  # ------------------------------------------------------------------------------
  log_Msg "Performing Atlas Registration to MNI152 (ANTs-based)"
  ${RUN} ${PipelineScripts}/AtlasRegistrationToMNI152_ANTs_UseMasked.sh \
  --workingdir=${AtlasSpaceFolder} \
  --t1=${T1wFolder}/${T1wImage}_acpc_dc.nii.gz \
  --t1rest=${T1wFolder}/${T1wImage}_acpc_dc_restore.nii.gz \
  --t1restbrain=${T1wFolder}/${T1wImage}_acpc_dc_restore_brain.nii.gz \
  --t1mask=${T1wFolder}/${T1wImage}_acpc_brain_mask.nii.gz \
  --t2=${T1wFolder}/${T2wImage}_acpc_dc.nii.gz \
  --t2rest=${T1wFolder}/${T2wImage}_acpc_dc_restore.nii.gz \
  --t2restbrain=${T1wFolder}/${T2wImage}_acpc_dc_restore_brain.nii.gz \
  --ref=${T1wTemplate} \
  --refbrain=${T1wTemplateBrain} \
  --refmask=${TemplateMask} \
  --ref2mm=${T1wTemplate2mm} \
  --ref2mmbrain=${T1wTemplate2mmBrain} \
  --ref2mmmask=${Template2mmMask} \
  --owarp=${AtlasSpaceFolder}/xfms/acpc_dc2standard.nii.gz \
  --oinvwarp=${AtlasSpaceFolder}/xfms/standard2acpc_dc.nii.gz \
  --ot1=${AtlasSpaceFolder}/${T1wImage} \
  --ot1rest=${AtlasSpaceFolder}/${T1wImage}_restore \
  --ot1restbrain=${AtlasSpaceFolder}/${T1wImage}_restore_brain \
  --ot2=${AtlasSpaceFolder}/${T2wImage} \
  --ot2rest=${AtlasSpaceFolder}/${T2wImage}_restore \
  --ot2restbrain=${AtlasSpaceFolder}/${T2wImage}_restore_brain \
  --fnirtconfig=${FNIRTConfig} \
  --useT2=${useT2} \
  --T1wFolder=${T1wFolder}
  log_Msg "Completed"
  
elif [ "${T1RegMethod}" = "ANTS" ]; then
  # ------------------------------------------------------------------------------
  #  Atlas Registration to MNI152: ANTs with Intermediate Template
  #  Also applies registration to T1w and T2w images
  #  Modified 20170330 by EF to include the option for a native mask in registration
  # ------------------------------------------------------------------------------
  log_Msg "Performing Atlas Registration to MNI152 (ANTs-based with intermediate template)"
  ${RUN} ${PipelineScripts}/AtlasRegistrationToMNI152_ANTsIntermediateTemplate_UseMasked.sh \
  --workingdir=${AtlasSpaceFolder} \
  --t1=${T1wFolder}/${T1wImage}_acpc_dc.nii.gz \
  --t1rest=${T1wFolder}/${T1wImage}_acpc_dc_restore.nii.gz \
  --t1restbrain=${T1wFolder}/${T1wImage}_acpc_dc_restore_brain.nii.gz \
  --t1mask=${T1wFolder}/${T1wImage}_acpc_brain_mask.nii.gz \
  --t2=${T1wFolder}/${T2wImage}_acpc_dc.nii.gz \
  --t2rest=${T1wFolder}/${T2wImage}_acpc_dc_restore.nii.gz \
  --t2restbrain=${T1wFolder}/${T2wImage}_acpc_dc_restore_brain.nii.gz \
  --studytemplate=${StudyTemplate} \
  --studytemplatebrain=${StudyTemplateBrain} \
  --ref=${T1wTemplate} \
  --refbrain=${T1wTemplateBrain} \
  --refmask=${TemplateMask} \
  --ref2mm=${T1wTemplate2mm} \
  --ref2mmbrain=${T1wTemplate2mmBrain} \
  --ref2mmmask=${Template2mmMask} \
  --owarp=${AtlasSpaceFolder}/xfms/acpc_dc2standard.nii.gz \
  --oinvwarp=${AtlasSpaceFolder}/xfms/standard2acpc_dc.nii.gz \
  --ot1=${AtlasSpaceFolder}/${T1wImage} \
  --ot1rest=${AtlasSpaceFolder}/${T1wImage}_restore \
  --ot1restbrain=${AtlasSpaceFolder}/${T1wImage}_restore_brain \
  --ot2=${AtlasSpaceFolder}/${T2wImage} \
  --ot2rest=${AtlasSpaceFolder}/${T2wImage}_restore \
  --ot2restbrain=${AtlasSpaceFolder}/${T2wImage}_restore_brain \
  --fnirtconfig=${FNIRTConfig} \
  --useT2=${useT2} \
  --T1wFolder=${T1wFolder}
  log_Msg "Completed"
elif [ "${T1RegMethod}" = "FLIRT_FNIRT" ]; then
  #### Atlas Registration to MNI152: FLIRT + FNIRT  #Also applies registration to T1w and T2w images ####
  #Consider combining all transforms and recreating files with single resampling steps
  ${RUN} ${PipelineScripts}/AtlasRegistrationToMNI152_FLIRTandFNIRT.sh \
  --workingdir=${AtlasSpaceFolder} \
  --t1=${T1wFolder}/${T1wImage}_acpc_dc \
  --t1rest=${T1wFolder}/${T1wImage}_acpc_dc_restore \
  --t1restbrain=${T1wFolder}/${T1wImage}_acpc_dc_restore_brain \
  --t2=${T1wFolder}/${T2wImage}_acpc_dc \
  --t2rest=${T1wFolder}/${T2wImage}_acpc_dc_restore \
  --t2restbrain=${T1wFolder}/${T2wImage}_acpc_dc_restore_brain \
  --ref=${T1wTemplate} \
  --refbrain=${T1wTemplateBrain} \
  --refmask=${TemplateMask} \
  --ref2mm=${T1wTemplate2mm} \
  --ref2mmmask=${Template2mmMask} \
  --owarp=${AtlasSpaceFolder}/xfms/acpc_dc2standard.nii.gz \
  --oinvwarp=${AtlasSpaceFolder}/xfms/standard2acpc_dc.nii.gz \
  --ot1=${AtlasSpaceFolder}/${T1wImage} \
  --ot1rest=${AtlasSpaceFolder}/${T1wImage}_restore \
  --ot1restbrain=${AtlasSpaceFolder}/${T1wImage}_restore_brain \
  --ot2=${AtlasSpaceFolder}/${T2wImage} \
  --ot2rest=${AtlasSpaceFolder}/${T2wImage}_restore \
  --ot2restbrain=${AtlasSpaceFolder}/${T2wImage}_restore_brain \
  --fnirtconfig=${FNIRTConfig} \
  --useT2=${useT2}
else
  echo "invalid T1w registration method ${T1RegMethod} specified!" 
  echo "Valid options: {FLIRT_FNIRT,ANTS,ANTS_NO_INTERMEDIATE}"
fi

MultiTemplateT1wBrain=T1w_brain.nii.gz
MultiTemplateSeg=Segmentation.nii.gz
Council=($(ls "$MultiTemplateDir")) # we have to make sure only subdirectories are inside...
cmd="${HCPPIPEDIR_PreFS}/run_JLF.sh --working-dir=${T1wFolder}/TemplateLabelFusion2 \
        --target=$T1wFolder/${T1wImage}_acpc_dc_restore_brain.nii.gz \
        --refdir=${MultiTemplateDir} --output=${T1wFolder}/aseg_acpc.nii.gz --ncores=${OMP_NUM_THREADS:-1}"
for ((i = 0; i < ${#Council[@]}; i++)); do
  cmd=${cmd}" -g ${Council[$i]}/$MultiTemplateT1wBrain -l ${Council[$i]}/$MultiTemplateSeg"
done
echo $cmd
$cmd

if ! [ -z ${ASegDir} ] && [ ${ASegDir} != ${T1wFolder} ]; then
    if [ -d ${ASegDir} ] && [ -e ${ASegDir}/aseg_acpc.nii.gz ] ; then
        # We also have a supplied aseg file for this subject.
        echo Using supplied aseg file: ${ASegDir}/aseg_acpc.nii.gz
        # Rename (but keep) the one we just generated....
        mv ${T1wFolder}/aseg_acpc.nii.gz ${T1wFolder}/aseg_acpc_dcan-derived.nii.gz
        # Copy the one that was supplied; it will be used from here on....
        cp -p ${ASegDir}/aseg_acpc.nii.gz ${T1wFolder}/aseg_acpc.nii.gz
    else
        echo Using aseg file generated with JLF.
    fi
fi

#### Next stage: FreeSurfer/FreeSurferPipeline.sh
echo "-------------------------------"
echo "END OF PRE-FREESURFER.sh SCRIPT"
echo "Please Verify Clean Error File"
