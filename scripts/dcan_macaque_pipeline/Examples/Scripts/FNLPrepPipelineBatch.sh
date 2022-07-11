#!/bin/bash

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

# Function: main
# Description: main processing work of this script
main()
{
	get_batch_options "$@"
	
	# Set variable values that locate and specify data to process
	StudyFolder="${HOME}/projects/Pipelines_ExampleData" # Location of Subject folders (named by subjectID)
	Subjlist="100307"                                    # Space delimited list of subject IDs

	# Set variable value that set up environment
	EnvironmentScript="${HOME}/projects/Pipelines/Examples/Scripts/SetUpHCPPipeline.sh" # Pipeline environment script

	# Use any command line specified options to override any of the variable settings above
	if [ -n "${command_line_specified_study_folder}" ]; then
		StudyFolder="${command_line_specified_study_folder}"
	fi

	if [ -n "${command_line_specified_subj}" ]; then
		Subjlist="${command_line_specified_subj}"
	fi

	# Report major script control variables to user
	echo "StudyFolder: ${StudyFolder}"
	echo "Subjlist: ${Subjlist}"
	echo "EnvironmentScript: ${EnvironmentScript}"
	echo "Run locally: ${command_line_specified_run_local}"

	# Set up pipeline environment variables and software
	source ${EnvironmentScript}

	# Define processing queue to be used if submitted to job scheduler
	# if [ X$SGE_ROOT != X ] ; then
	#    QUEUE="-q long.q"
	#    QUEUE="-q veryshort.q"
    QUEUE="-q hcp_priority.q"
	# fi

	# If PRINTCOM is not a null or empty string variable, then
    # this script and other scripts that it calls will simply
	# print out the primary commands it otherwise would run.
	# This printing will be done using the command specified
	# in the PRINTCOM variable
	PRINTCOM=""
	# PRINTCOM="echo"

	#
	# Inputs:
	#
	# Scripts called by this script do NOT assume anything about the form of the
	# input names or paths. This batch script assumes the HCP raw data naming
	# convention, e.g.
	#
	# ${StudyFolder}/unprocessed/3T/T1w_MPR1/${Subject}_3T_T1w_MPR1.nii.gz
	# ${StudyFolder}/unprocessed/3T/T1w_MPR2/${Subject}_3T_T1w_MPR2.nii.gz
	#
	# ${StudyFolder}/unprocessed/3T/T2w_SPC1/${Subject}_3T_T2w_SPC1.nii.gz
	# ${StudyFolder}/unprocessed/3T/T2w_SPC2/${Subject}_3T_T2w_SPC2.nii.gz
	#
	# ${StudyFolder}/unprocessed/3T/T1w_MPR1/${Subject}_3T_FieldMap_Magnitude.nii.gz
	# ${StudyFolder}/unprocessed/3T/T1w_MPR1/${Subject}_3T_FieldMap_Phase.nii.gz

	# Scan settings:
	#
	# Change the Scan Settings (e.g. Sample Spacings and $UnwarpDir) to match your
	# images. These are set to match the HCP Protocol by default.

	# Readout Distortion Correction:
	#
	# You have the option of using either gradient echo field maps or spin echo
	# field maps to perform readout distortion correction on your structural
	# images, or not to do readout distortion correction at all.
	#
	# The HCP Pipeline Scripts currently support the use of gradient echo field
	# maps or spin echo field maps as they are produced by the Siemens Connectom
	# Scanner. They also support the use of gradient echo field maps as generated
	# by General Electric scanners.
	#
	# Change either the gradient echo field map or spin echo field map scan
	# settings to match your data. This script is setup to use gradient echo
	# field maps from the Siemens Connectom Scanner using the HCP Protocol.

	# Gradient Distortion Correction:
	#
	# If using gradient distortion correction, use the coefficents from your
	# scanner. The HCP gradient distortion coefficents are only available through
	# Siemens. Gradient distortion in standard scanners like the Trio is much
	# less than for the HCP Skyra.

	# DO WORK

	# Cycle through specified subjects
    useT2=${useT2:-true} # sets the useT2 flag default to "true" - AP 20162111
	for Subject in $Subjlist ; do
		echo $Subject

		# Input Images

		# Detect Number of T1w Images and build list of full paths to
		# T1w images
		numT1ws=`ls ${StudyFolder}/unprocessed/3T | grep 'T1w_MPR' | wc -l` #removed .$ from 'T1w_MPR.$' AP 20161129
		echo "Found ${numT1ws} T1w Images for subject ${Subject}"
		T1wInputImages=""
		i=1
		while [ $i -le $numT1ws ] ; do
			T1wInputImages=`echo "${T1wInputImages}${StudyFolder}/unprocessed/3T/T1w_MPR${i}/${Subject}_3T_T1w_MPR${i}.nii.gz@"`
			i=$(($i+1))
		done

        if $useT2; then
		# Detect Number of T2w Images and build list of full paths to
		# T2w images
		numT2ws=`ls ${StudyFolder}/unprocessed/3T | grep 'T2w_SPC' | wc -l` #removed .$ from 'T2w_SPC.$' - AP 20161129
		echo "Found ${numT2ws} T2w Images for subject ${Subject}"
		T2wInputImages=""
		i=1
		while [ $i -le $numT2ws ] ; do
			T2wInputImages=`echo "${T2wInputImages}${StudyFolder}/unprocessed/3T/T2w_SPC${i}/${Subject}_3T_T2w_SPC${i}.nii.gz@"`
			i=$(($i+1))
		done
        fi

		# Readout Distortion Correction:
		#
		#   Currently supported Averaging and readout distortion correction
		#   methods: (i.e. supported values for the AvgrdcSTRING variable in this
		#   script and the --avgrdcmethod= command line option for the
		#   PreFreeSurferPipeline.sh script.)
		#
		#   "NONE"
		#     Average any repeats but do no readout distortion correction
		#
		#   "FIELDMAP"
		#     This value is equivalent to the "SiemensFieldMap" value described
		#     below. Use of the "SiemensFieldMap" value is prefered, but
		#     "FIELDMAP" is included for backward compatibility with the versions
		#     of these scripts that only supported use of Siemens-specific
		#     Gradient Echo Field Maps and did not support Gradient Echo Field
		#     Maps from any other scanner vendor.
		#
		#   "TOPUP"
		#     Average any repeats and use Spin Echo Field Maps for readout
		#     distortion correction
		#
		#   "GeneralElectricFieldMap"
		#     Average any repeats and use General Electric specific Gradient
		#     Echo Field Map for readout distortion correction
		#
		#   "SiemensFieldMap"
		#     Average any repeats and use Siemens specific Gradient Echo
		#     Field Maps for readout distortion correction
		#
		# Current Setup is for Siemens specific Gradient Echo Field Maps
		#
		#   The following settings for AvgrdcSTRING, MagnitudeInputName,
		#   PhaseInputName, and TE are for using the Siemens specific
		#   Gradient Echo Field Maps that are collected and used in the
		#   standard HCP protocol.
		#
		#   Note: The AvgrdcSTRING variable could also be set to the value
		#   "FIELDMAP" which is equivalent to "SiemensFieldMap".
		AvgrdcSTRING="SiemensFieldMap"

		# ----------------------------------------------------------------------
		# Variables related to using Siemens specific Gradient Echo Field Maps
		# ----------------------------------------------------------------------

		# The MagnitudeInputName variable should be set to a 4D magitude volume
		# with two 3D timepoints or "NONE" if not used
		MagnitudeInputName="${StudyFolder}/unprocessed/3T/T1w_MPR1/${Subject}_3T_FieldMap_Magnitude.nii.gz"

		# The PhaseInputName variable should be set to a 3D phase difference
		# volume or "NONE" if not used
		PhaseInputName="${StudyFolder}/unprocessed/3T/T1w_MPR1/${Subject}_3T_FieldMap_Phase.nii.gz"

		# The TE variable should be set to 2.46ms for 3T scanner, 1.02ms for 7T
		# scanner or "NONE" if not using
		# ----------------------------------------------------------------------
		# Variables related to using Spin Echo Field Maps
		# ----------------------------------------------------------------------

		# The following variables would be set to values other than "NONE" for
		# using Spin Echo Field Maps (i.e. when AvgrdcSTRING="TOPUP")

		# The SpinEchoPhaseEncodeNegative variable should be set to the
		# spin echo field map volume with a negative phase encoding direction
		# (LR in 3T HCP data, AP in 7T HCP data), and set to "NONE" if not
		# using Spin Echo Field Maps (i.e. if AvgrdcSTRING is not equal to
		# "TOPUP")
		#
		# Example values for when using Spin Echo Field Maps:
		#   ${StudyFolder}/unprocessed/3T/T1w_MPR1/${Subject}_3T_SpinEchoFieldMap_LR.nii.gz
		#   ${StudyFolder}/unprocessed/3T/T1w_MPR1/${Subject}_3T_SpinEchoFieldMap_AP.nii.gz
		SpinEchoPhaseEncodeNegative="NONE"

		# The SpinEchoPhaseEncodePositive variable should be set to the
		# spin echo field map volume with positive phase encoding direction
		# (RL in 3T HCP data, PA in 7T HCP data), and set to "NONE" if not
		# using Spin Echo Field Maps (i.e. if AvgrdcSTRING is not equal to "TOPUP")
		#
		# Example values for when using Spin Echo Field Maps:
		#   ${StudyFolder}/unprocessed/3T/T1w_MPR1/${Subject}_3T_SpinEchoFieldMap_RL.nii.gz
		#   ${StudyFolder}/unprocessed/3T/T1w_MPR1/${Subject}_3T_SpinEchoFieldMap_PA.nii.gz
		SpinEchoPhaseEncodePositive="NONE"

		# Spin Echo Unwarping Direction
		# x or y (minus or not does not matter)
		# "NONE" if not used
		#
		# Example values for when using Spin Echo Field Maps: x, -x, y, -y
		# Note: +x or +y are not supported. For positive values, DO NOT include the + sign
		SEUnwarpDir="NONE"

    #if $useT2; then
    #  break
    #fi

		# Establish queuing command based on command line option
		if [ -n "${command_line_specified_run_local}" ] ; then
			echo "About to run ${HCPPIPEDIR}/PreFreeSurfer/PreFreeSurferPipeline.sh"
			queuing_command=""
		else
			echo "About to use fsl_sub to queue or run ${HCPPIPEDIR}/PreFreeSurfer/PreFreeSurferPipeline.sh"
			queuing_command="${FSLDIR}/bin/fsl_sub ${QUEUE}"
		fi

    ${queuing_command} ${HCPPIPEDIR}/HCPPrep/hcp_fnl_prep.sh \
      --path="$StudyFolder" \
      --subject="$Subject" \
      --sshead="$StudyAtlasHead" \
      --ssbrain="$StudyAtlasBrain" \
      --ssaseg="$StudyAtlasAseg" \
      --fieldmap="$AvgrdcSTRING" \
      --ferumoxytol="$Ferumoxytol" \
      --mtdir="$MultiAtlasFolder"
    echo "set -- ${queuing_command} ${HCPPIPEDIR}/HCPPrep/hcp_fnl_prep.sh \
      --path="$StudyFolder" \
      --subject="$Subject" \
      --sshead="$StudyAtlasHead" \
      --ssbrain="$StudyAtlasBrain" \
      --ssaseg="$StudyAtlasAseg" \
      --fieldmap="$AvgrdcSTRING" \
      --ferumoxytol="$Ferumoxytol" \
      --mtdir="$MultiAtlasFolder""
  done
}

# Invoke the main function to get things started
main "$@"
