#!/bin/bash
trap 'cleanup' EXIT SIGTERM

function cleanup() {
  if [ -d ${ScratchFolder:-/dev/null} ]; then
    rsync -vrt ${ScratchFolder}/T1w/ ${StudyFolder}/T1w
    rm -rf $ScratchFolder
  fi
}

get_batch_options() {
    local arguments=("$@")

    unset command_line_specified_study_folder
    unset command_line_specified_subj
    unset command_line_specified_run_local

    local index=0
    local numArgs=${#arguments[@]}
    local argument

    while [ ${index} -lt ${numArgs} ]; do
        argument=${arguments[index]}

        case ${argument} in
            --StudyFolder=*)
                command_line_specified_study_folder=${argument#*=}
                index=$(( index + 1 ))
                ;;
            --Subject=*)
                command_line_specified_subj=${argument#*=}
                index=$(( index + 1 ))
                ;;
            --runlocal)
                command_line_specified_run_local="TRUE"
                index=$(( index + 1 ))
                ;;
	    *)
		echo ""
		echo "ERROR: Unrecognized Option: ${argument}"
		echo ""
		exit 1
		;;
        esac
    done
}

get_batch_options "$@"

StudyFolder="${HOME}/projects/Pipelines_ExampleData" #Location of Subject folders (named by subjectID)
Subjlist="100307" #Space delimited list of subject IDs
EnvironmentScript="${HOME}/projects/Pipelines/Examples/Scripts/SetUpHCPPipeline.sh" #Pipeline environment script

if [ -n "${command_line_specified_study_folder}" ]; then
    StudyFolder="${command_line_specified_study_folder}"
fi

if [ -n "${command_line_specified_subj}" ]; then
    Subjlist="${command_line_specified_subj}"
fi

# Requirements for this script
#  installed versions of: FSL (version 5.0.6), FreeSurfer (version 5.3.0-HCP), gradunwarp (HCP version 1.0.2)
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR , PATH (for gradient_unwarp.py)

#Set up pipeline environment variables and software
source ${EnvironmentScript}

# Log the originating call
echo "$@"

#if [ X$SGE_ROOT != X ] ; then
#    QUEUE="-q long.q"
    QUEUE="-q hcp_priority.q"
#fi

PRINTCOM=""
#PRINTCOM="echo"
#QUEUE="-q veryshort.q"


########################################## INPUTS ########################################## 

#Scripts called by this script do assume they run on the outputs of the PreFreeSurfer Pipeline

######################################### DO WORK ##########################################
useT2=${useT2:-true} # sets the useT2 flag default to "true" - AP 20162111
for Subject in $Subjlist ; do
  echo $Subject

  #  Make directory in scratch space
  ScratchFolder=$(echo "$StudyFolder" | sed "s|/home/exacloud/lustre1/fnl_lab/data/HCP/|/mnt/scratch/temp_$(whoami)|g")
  mkdir -p ${ScratchFolder} && {

  echo "temporary directory created at ${ScratchFolder}"
  rsync -vLt "${StudyFolder}"/T1w/T?w_acpc_dc_restore*.nii.gz "${ScratchFolder}/T1w/"
  rsync -vLt "${StudyFolder}"/T1w/T1wN_acpc*.nii.gz "${ScratchFolder}/T1w/"
  rsync -vLt "${StudyFolder}/T1w/aseg_acpc.nii.gz" "${ScratchFolder}/T1w/"

  #Input Variables
  SubjectID="$Subject" #FreeSurfer Subject ID Name
  SubjectDIR="${ScratchFolder}/T1w" #Location to Put FreeSurfer Subject's Folder
  T1wImage="${ScratchFolder}/T1w/T1w_acpc_dc_restore.nii.gz" #T1w FreeSurfer Input (Full Resolution)
  T1wImageBrain="${ScratchFolder}/T1w/T1w_acpc_dc_restore_brain.nii.gz" #T1w FreeSurfer Input (Full Resolution)
  T2wImage="${ScratchFolder}/T1w/T2w_acpc_dc_restore.nii.gz" #T2w FreeSurfer Input (Full Resolution)
  Aseg="${ScratchFolder}/T1w/aseg_acpc.nii.gz"
  T1wNImage="${ScratchFolder}/T1w/T1wN_acpc.nii.gz"
  T1wNImageBrain="${ScratchFolder}/T1w/T1wN_acpc_brain.nii.gz"

  }
  #  If scratch space failed, try running normally.
  if (($?)); then
    SubjectID="$Subject" #FreeSurfer Subject ID Name
    SubjectDIR="${StudyFolder}/T1w" #Location to Put FreeSurfer Subject's Folder
    T1wImage="${StudyFolder}/T1w/T1w_acpc_dc_restore.nii.gz" #T1w FreeSurfer Input (Full Resolution)
    T1wImageBrain="${StudyFolder}/T1w/T1w_acpc_dc_restore_brain.nii.gz" #T1w FreeSurfer Input (Full Resolution)
    T2wImage="${StudyFolder}/T1w/T2w_acpc_dc_restore.nii.gz" #T2w FreeSurfer Input (Full Resolution)
    Aseg="${StudyFolder}/T1w/aseg_acpc.nii.gz"
    T1wNImage="${StudyFolder}/T1w/T1wN_acpc.nii.gz"
    T1wNImageBrain="${StudyFolder}/T1w/T1wN_acpc_brain.nii.gz"
  fi

  if [ -n "${command_line_specified_run_local}" ] ; then
      echo "About to run ${HCPPIPEDIR}/FreeSurfer/FreeSurferPipeline.sh"
      queuing_command=""
  else
      echo "About to use fsl_sub to queue or run ${HCPPIPEDIR}/FreeSurfer/FreeSurferPipeline.sh"
      queuing_command="${FSLDIR}/bin/fsl_sub ${QUEUE}"
  fi

  ${queuing_command} ${HCPPIPEDIR}/FreeSurfer/FNL_FreeGreyPipeline.sh \
      --subject="$Subject" \
      --subjectDIR="$SubjectDIR" \
      --t1="$T1wImage" \
      --t1brain="$T1wImageBrain" \
      --t2="$T2wImage" \
      --t1n="$T1wNImage" \
      --t1nbrain="$T1wNImageBrain" \
      --gca="$GCA_freesurfer" \
      --aseg="$Aseg" \
      --useT2="$useT2" \
      --printcom=$PRINTCOM
  
  # The following lines are used for interactive debugging to set the positional parameters: $1 $2 $3 ...

  echo "set -- --subject="$Subject" \
      --subjectDIR="$SubjectDIR" \
      --t1="$T1wImage" \
      --t1brain="$T1wImageBrain" \
      --t2="$T2wImage" \
      --gca=$GCA \
      --Aseg=$Aseg \
      --useT2="$useT2" \
      --printcom=$PRINTCOM"

  echo ". ${EnvironmentScript}"

done



