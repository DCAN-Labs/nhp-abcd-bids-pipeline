#!/bin/bash 
set -ex

export OMP_NUM_THREADS=1
export PATH=`echo $PATH | sed 's|freesurfer/|freesurfer53/|g'`

echo
# Requirements for this script
#  installed versions of: FSL5.0.5 or higher , FreeSurfer (version 5.2 or higher) ,
#  environment: FSLDIR , FREESURFER_HOME , HCPPIPEDIR , CARET7DIR 

# make pipeline engine happy...
if [ $# -eq 1 ] ; then
    echo "Version unknown..."
    exit 0
fi

########################################## PIPELINE OVERVIEW ########################################## 

#TODO

########################################## OUTPUT DIRECTORIES ########################################## 

#TODO

########################################## SUPPORT FUNCTIONS ########################################## 

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

# Input Variables
SubjectID=`getopt1 "--subject" $@` #FreeSurfer Subject ID Name
SubjectDIR=`getopt1 "--subjectDIR" $@` #Location to Put FreeSurfer Subject's Folder
T1wImage=`getopt1 "--t1" $@` #T1w FreeSurfer Input (Full Resolution)
T1wImageBrain=`getopt1 "--t1brain" $@` 
T2wImage=`getopt1 "--t2" $@` #T2w FreeSurfer Input (Full Resolution)
T2wType=`getopt1 "--t2type" $@` #T2w or FLAIR: default T2w

T2wType=`defaultopt $T2wType T2w`

T1wImageFile=`remove_ext $T1wImage`;
T1wImageBrainFile=`remove_ext $T1wImageBrain`;

PipelineScripts=${HCPPIPEDIR_FS}

if [ -e "$SubjectDIR"/scripts/IsRunning.lh+rh ] ; then
  rm "$SubjectDIR"/scripts/IsRunning.lh+rh
fi

export OMP_NUM_THREADS=1
#Make Spline Interpolated Downsample to 1mm
Mean=`fslstats $T1wImageBrain -M`
flirt -interp spline -in "$T1wImage" -ref "$T1wImage" -applyisoxfm 1 -out "$T1wImageFile"_1mm.nii.gz
applywarp --rel --interp=spline -i "$T1wImage" -r "$T1wImageFile"_1mm.nii.gz --premat=$FSLDIR/etc/flirtsch/ident.mat -o "$T1wImageFile"_1mm.nii.gz
applywarp --rel --interp=nn -i "$T1wImageBrain" -r "$T1wImageFile"_1mm.nii.gz --premat=$FSLDIR/etc/flirtsch/ident.mat -o "$T1wImageBrainFile"_1mm.nii.gz
fslmaths "$T1wImageFile"_1mm.nii.gz -div $Mean -mul 150 -abs "$T1wImageFile"_1mm.nii.gz

#Initial Recon-all Steps
#-skullstrip of FreeSurfer not reliable for Phase II data because of poor FreeSurfer mri_em_register registrations with Skull on, run registration with PreFreeSurfer masked data and then generate brain mask as usual
echo "Starting Initial Recon-all Steps at line 74 of $0"
$FREESURFER_HOME/bin/recon-all -i "$T1wImageFile"_1mm.nii.gz -subjid $SubjectID -sd $SubjectDIR -motioncor -talairach -nuintensitycor -normalization
echo "Finishing recon-all step at line 74 of $0"
echo "Starting mri_convert step at line 77 of $0"
$FREESURFER_HOME/bin/mri_convert "$T1wImageBrainFile"_1mm.nii.gz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz --conform
echo "Ending mri_convert step at line 77 of $0"

export OMP_NUM_THREADS=1
echo "Starting mri_em_register step at line 82 of $0"
$FREESURFER_HOME/bin/mri_em_register -mask "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz "$SubjectDIR"/"$SubjectID"/mri/nu.mgz $FREESURFER_HOME/average/RB_all_2008-03-26.gca "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach_with_skull.lta
echo "Ending mri_em_register step at line 82 of $0"
echo "Starting mri_watershed step at line 85 of $0"
$FREESURFER_HOME/bin/mri_watershed -T1 -brain_atlas $FREESURFER_HOME/average/RB_all_withskull_2008-03-26.gca "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach_with_skull.lta "$SubjectDIR"/"$SubjectID"/mri/T1.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.auto.mgz 
echo "Ending mri_watershed step at line 85 of $0"

rm -f "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz 
cp "$SubjectDIR"/"$SubjectID"/mri/brainmask.auto.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz 

echo "Starting  Recon-all Steps at line 92 of $0"
$FREESURFER_HOME/bin/recon-all -subjid $SubjectID -sd $SubjectDIR -autorecon2 -nosmooth2 -noinflate2 -nocurvstats -nosegstats
echo "Finishing Initial Recon-all Steps at line 92 of $0"

#Highres white stuff and Fine Tune T2w to T1w Reg
"$PipelineScripts"/FreeSurferHiresWhite.sh "$SubjectID" "$SubjectDIR" "$T1wImage" "$T2wImage" "$T2wType"

export OMP_NUM_THREADS=1
#Intermediate Recon-all Steps
$FREESURFER_HOME/bin/recon-all -subjid $SubjectID -sd $SubjectDIR -smooth2 -inflate2 -curvstats -sphere -surfreg -jacobian_white -avgcurv -cortparc
echo "Intermediate Recon-all Steps at line 103 of $0"
echo "RECON-ALL FINISHED"

#Highres pial stuff (this module adjusts the pial surface based on the the T2w image)
"$PipelineScripts"/FreeSurferHiresPial.sh "$SubjectID" "$SubjectDIR" "$T1wImage" "$T2wImage"
echo "Highres pial stuff at line 107 of $0"
echo "FreeSurferHiresPial.sh SCRIPT FINISHED"

#Final Recon-all Steps
export OMP_NUM_THREADS=1
$FREESURFER_HOME/bin/recon-all -subjid $SubjectID -sd $SubjectDIR -surfvolume -parcstats -cortparc2 -parcstats2 -cortribbon -segstats -aparc2aseg -wmparc -balabels -label-exvivo-ec
echo "Final Recon-all Steps at line 113 of $0"

echo "RECON-ALL ALL STEPS FINISHED"
echo "-------------------------------"
echo "END OF FREESURFER.sh SCRIPT"
echo "Please Verify Clean Error File"
