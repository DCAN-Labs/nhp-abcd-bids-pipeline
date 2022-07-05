#!/bin/bash
# args
if [ $# -lt 1 ]; then
    echo -e "Usage: `basename $0` <SUBJECT T1W DIRECTORY> [METHOD]"
    exit 1
fi

SOURCE_DIR=$(readlink -f ${BASH_SOURCE%/*})
echo SOURCE_DIR=${SOURCE_DIR}

subjectdir=$1
NormMethod=$2
NormGMStdDevScale=$3
NormWMStdDevScale=$4
NormCSFStdDevScale=$5
if [ -z  "${NormMethod}" ] ; then
    # Default is to use the adult grey matter intensity profile.
    NormMethod="ADULT_GM_IP"
fi

cd ${subjectdir}

${SOURCE_DIR}/make_WMGMCSF_masks.sh T1w_acpc_dc_restore.nii.gz aseg_acpc.nii.gz

if [[ "${NormMethod^^}" == "ROI_IPS" ]] ; then
    # Call the old script that changes each ROI's intensity profile and puts them back together.
    ${SOURCE_DIR}/ChangeROIs2AdultIntensity.bash T1w_acpc_dc_restore ${HCPPIPEDIR_Templates}/means_RB_all ${NormGMStdDevScale} ${NormWMStdDevScale} ${NormCSFStdDevScale}
else
    # Default: call script to change whole brain based on grey matter in adult ref.
    ${SOURCE_DIR}/Change2AdultIntensity.bash T1w_acpc_dc_restore ${HCPPIPEDIR_Templates}/means_RB_all ${NormGMStdDevScale} ${NormWMStdDevScale} 
fi
mv T1w_acpc_dc_restore_AdultInt_thr.nii.gz T1wN_acpc.nii.gz
${FSLDIR}/bin/fslmaths T1wN_acpc.nii.gz -mas T1w_acpc_dc_restore_brain.nii.gz T1wN_acpc_brain.nii.gz

