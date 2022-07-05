#!/bin/bash 

Subjlist="M126 M128 M129 M131 M132" #Space delimited list of subject IDs
StudyFolder="/media/myelin/brainmappers/Connectome_Project/InVivoMacaques" #Location of Subject folders (named by subjectID)
EnvironmentScript="/media/2TBB/Connectome_Project/Pipelines/Examples/Scripts/SetUpHCPPipeline.sh" #Pipeline environment script

# Requirements for this script
#  installed versions of: FSL5.0.2 or higher , FreeSurfer (version 5.2 or higher) , gradunwarp (python code from MGH)
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR , PATH (for gradient_unwarp.py)

#Set up pipeline environment variables and software
. ${EnvironmentScript}

# Log the originating call
echo "$@"

#if [ X$SGE_ROOT != X ] ; then
    QUEUE="-q long.q"
#fi

PRINTCOM=""
#PRINTCOM="echo"
#QUEUE="-q veryshort.q"


########################################## INPUTS ########################################## 

#Scripts called by this script do assume they run on the outputs of the PreFreeSurfer Pipeline

######################################### DO WORK ##########################################

for Subject in $Subjlist ; do
  #Input Variables
  SubjectID="$Subject" #FreeSurfer Subject ID Name
  SubjectDIR="${StudyFolder}/T1w" #Location to Put FreeSurfer Subject's Folder
  T1wImage="${StudyFolder}/T1w/T1w_acpc_dc_restore_brain.nii.gz" #T1w FreeSurfer Input (Full Resolution)
  T1wImageBrain="${StudyFolder}/T1w/T1w_acpc_dc_restore_brain.nii.gz" #T1w FreeSurfer Input (Full Resolution)
  T2wImage="${StudyFolder}/T1w/T2w_acpc_dc_restore_brain.nii.gz" #T2w FreeSurfer Input (Full Resolution)
  FSLinearTransform="${HCPPIPEDIR_Templates}/fs_xfms/eye.xfm" #Identity
  GCAdir="${HCPPIPEDIR_Templates}/MacaqueYerkes19" #Template Dir with FreeSurfer NHP GCA and TIF files
  RescaleVolumeTransform="${HCPPIPEDIR_Templates}/fs_xfms/Macaque_rescale" #Transforms to undo the effects of faking the dimensions to 1mm
  AsegEdit="NONE" #Volume containing Aseg Edits to be applied to a rerun

  ${FSLDIR}/bin/fsl_sub ${QUEUE} \
     ${HCPPIPEDIR}/FreeSurfer/FreeSurferPipelineNHP.sh \
      --subject="$Subject" \
      --subjectDIR="$SubjectDIR" \
      --t1="$T1wImage" \
      --t1brain="$T1wImageBrain" \
      --t2="$T2wImage" \
      --fslinear="$FSLinearTransform" \
      --gcadir="$GCAdir" \
      --rescaletrans="$RescaleVolumeTransform" \
      --asegedit="$AsegEdit" \
      --printcom=$PRINTCOM
      
  # The following lines are used for interactive debugging to set the positional parameters: $1 $2 $3 ...

  echo "set -- --subject="$Subject" \
      --subjectDIR="$SubjectDIR" \
      --t1="$T1wImage" \
      --t1brain="$T1wImageBrain" \
      --t2="$T2wImage" \
      --fslinear="$FSLinearTransform" \
      --gcadir="$GCAdir" \
      --rescaletrans="$RescaleVolumeTransform" \
      --asegedit="$AsegEdit" \
      --printcom=$PRINTCOM"

  echo ". ${EnvironmentScript}"

done

