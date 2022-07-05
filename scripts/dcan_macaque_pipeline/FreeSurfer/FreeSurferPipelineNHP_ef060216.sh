#!/bin/bash
set -e

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
FSLinearTransform=`getopt1 "--fslinear" $@`
GCAdir=`getopt1 "--gcadir" $@`
RescaleVolumeTransform=`getopt1 "--rescaletrans" $@`
AsegEdit=`getopt1 "--asegedit" $@`

T1wImageFile=`remove_ext $T1wImage`;
T1wImageBrainFile=`remove_ext $T1wImageBrain`;
T2wImageFile=`remove_ext $T2wImage`;

PipelineScripts=${HCPPIPEDIR_FS}

export SUBJECTS_DIR="$SubjectDIR"

if [ -e "$SubjectDIR"/"$SubjectID"/scripts/IsRunning.lh+rh ] ; then
  rm "$SubjectDIR"/"$SubjectID"/scripts/IsRunning.lh+rh
fi

### DELETE IF NOT USING ###
#if [ -e "$SubjectDIR"/"$SubjectID" ] ; then
#  rm -r "$SubjectDIR"/"$SubjectID"
#fi

#mv "$SubjectDIR"/"$SubjectID"_1mm "$SubjectDIR"/"$SubjectID"
### DELETE IF NOT USING ###
#function comment {

#Make Spline Interpolated Downsample to 1mm
Mean=`fslstats $T1wImageBrain -M`
res=`fslorient -getsform $T1wImage | cut -d " " -f 1 | cut -d "-" -f 2`
oldsform=`fslorient -getsform $T1wImage`
newsform=""
i=1
while [ $i -le 12 ] ; do
  oldelement=`echo $oldsform | cut -d " " -f $i`
  newelement=`echo "scale=1; $oldelement / $res" | bc -l`
  newsform=`echo "$newsform""$newelement"" "`
  if [ $i -eq 4 ] ; then
    originx="$newelement"
  fi
  if [ $i -eq 8 ] ; then
    originy="$newelement"
  fi
  if [ $i -eq 12 ] ; then
    originz="$newelement"
  fi
  i=$(($i+1))
done
newsform=`echo "$newsform""0 0 0 1" | sed 's/  / /g'`

cp "$T1wImage" "$T1wImageFile"_1mm.nii.gz
fslorient -setsform $newsform "$T1wImageFile"_1mm.nii.gz
fslhd -x "$T1wImageFile"_1mm.nii.gz | sed s/"dx = '${res}'"/"dx = '1'"/g | sed s/"dy = '${res}'"/"dy = '1'"/g | sed s/"dz = '${res}'"/"dz = '1'"/g | fslcreatehd - "$T1wImageFile"_1mm_head.nii.gz
fslmaths "$T1wImageFile"_1mm_head.nii.gz -add "$T1wImageFile"_1mm.nii.gz "$T1wImageFile"_1mm.nii.gz
fslorient -copysform2qform "$T1wImageFile"_1mm.nii.gz
rm "$T1wImageFile"_1mm_head.nii.gz
dimex=`fslval "$T1wImageFile"_1mm dim1`
dimey=`fslval "$T1wImageFile"_1mm dim2`
dimez=`fslval "$T1wImageFile"_1mm dim3`
# ERIC: PADS ASSUME EVEN-NUMBERED DIMENSIONS, odd dimensions do not work.
padx=`echo "(256 - $dimex) / 2" | bc`
pady=`echo "(256 - $dimey) / 2" | bc`
padz=`echo "(256 - $dimez) / 2" | bc`
# ERIC: ADDED ODD DETECTION SECTION
oddx=`echo "(256 - $dimex) % 2" | bc`
oddy=`echo "(256 - $dimey) % 2" | bc`
oddz=`echo "(256 - $dimez) % 2" | bc`

# ERIC: USING ODD DETECTION FOR ALWAYS PADDING CORRECTLY TO 256
if [ $oddx -eq 1 ] ; then
  fslcreatehd $oddx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$T1wImageFile"_1mm_pad1x
  fslcreatehd $padx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$T1wImageFile"_1mm_padx
  fslmerge -x "$T1wImageFile"_1mm "$T1wImageFile"_1mm_pad1x "$T1wImageFile"_1mm_padx "$T1wImageFile"_1mm "$T1wImageFile"_1mm_padx
  rm "$T1wImageFile"_1mm_pad1x.nii.gz "$T1wImageFile"_1mm_padx.nii.gz
else
  fslcreatehd $padx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$T1wImageFile"_1mm_padx
  fslmerge -x "$T1wImageFile"_1mm "$T1wImageFile"_1mm_padx "$T1wImageFile"_1mm "$T1wImageFile"_1mm_padx
  rm "$T1wImageFile"_1mm_padx.nii.gz
fi

if [ $oddy -eq 1 ] ; then
  fslcreatehd 256 $oddy $dimez 1 1 1 1 1 0 0 0 16 "$T1wImageFile"_1mm_pad1y
  fslcreatehd 256 $pady $dimez 1 1 1 1 1 0 0 0 16 "$T1wImageFile"_1mm_pady
  fslmerge -y "$T1wImageFile"_1mm "$T1wImageFile"_1mm_pad1y "$T1wImageFile"_1mm_pady "$T1wImageFile"_1mm "$T1wImageFile"_1mm_pady
  rm "$T1wImageFile"_1mm_pad1y.nii.gz "$T1wImageFile"_1mm_pady.nii.gz
else
  fslcreatehd 256 $pady $dimez 1 1 1 1 1 0 0 0 16 "$T1wImageFile"_1mm_pady
  fslmerge -y "$T1wImageFile"_1mm "$T1wImageFile"_1mm_pady "$T1wImageFile"_1mm "$T1wImageFile"_1mm_pady
  rm "$T1wImageFile"_1mm_pady.nii.gz
fi

if [ $oddz -eq 1 ] ; then
  fslcreatehd 256 256 $oddz 1 1 1 1 1 0 0 0 16 "$T1wImageFile"_1mm_pad1z
  fslcreatehd 256 256 $padz 1 1 1 1 1 0 0 0 16 "$T1wImageFile"_1mm_padz
  fslmerge -z "$T1wImageFile"_1mm "$T1wImageFile"_1mm_pad1z "$T1wImageFile"_1mm_padz "$T1wImageFile"_1mm "$T1wImageFile"_1mm_padz
  rm "$T1wImageFile"_1mm_pad1z.nii.gz "$T1wImageFile"_1mm_padz.nii.gz
else
  fslcreatehd 256 256 $padz 1 1 1 1 1 0 0 0 16 "$T1wImageFile"_1mm_padz
  fslmerge -z "$T1wImageFile"_1mm "$T1wImageFile"_1mm_padz "$T1wImageFile"_1mm "$T1wImageFile"_1mm_padz
  rm "$T1wImageFile"_1mm_padz.nii.gz
fi

fslorient -setsformcode 1 "$T1wImageFile"_1mm
fslorient -setsform -1 0 0 `echo "$originx + $padx" | bc -l` 0 1 0 `echo "$originy - $pady" | bc -l` 0 0 1 `echo "$originz - $padz" | bc -l` 0 0 0 1 "$T1wImageFile"_1mm

cp "$T2wImage" "$T2wImageFile"_1mm.nii.gz
fslorient -setsform $newsform "$T2wImageFile"_1mm.nii.gz
fslhd -x "$T2wImageFile"_1mm.nii.gz | sed s/"dx = '${res}'"/"dx = '1'"/g | sed s/"dy = '${res}'"/"dy = '1'"/g | sed s/"dz = '${res}'"/"dz = '1'"/g | fslcreatehd - "$T2wImageFile"_1mm_head.nii.gz
fslmaths "$T2wImageFile"_1mm_head.nii.gz -add "$T2wImageFile"_1mm.nii.gz "$T2wImageFile"_1mm.nii.gz
fslorient -copysform2qform "$T2wImageFile"_1mm.nii.gz
rm "$T2wImageFile"_1mm_head.nii.gz
dimex=`fslval "$T2wImageFile"_1mm dim1`
dimey=`fslval "$T2wImageFile"_1mm dim2`
dimez=`fslval "$T2wImageFile"_1mm dim3`
# ERIC: PADS ASSUME EVEN-NUMBERED DIMENSIONS, odd dimensions do not work.
padx=`echo "(256 - $dimex) / 2" | bc`
pady=`echo "(256 - $dimey) / 2" | bc`
padz=`echo "(256 - $dimez) / 2" | bc`
# ERIC: ADDED ODD DETECTION SECTION
oddx=`echo "(256 - $dimex) % 2" | bc`
oddy=`echo "(256 - $dimey) % 2" | bc`
oddz=`echo "(256 - $dimez) % 2" | bc`

# ERIC: USED ODD DETECTION FOR ALWAYS PADDING CORRECTLY TO 256
if [ $oddx -eq 1 ] ; then
  fslcreatehd $oddx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$T2wImageFile"_1mm_pad1x
  fslcreatehd $padx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$T2wImageFile"_1mm_padx
  fslmerge -x "$T2wImageFile"_1mm "$T2wImageFile"_1mm_pad1x "$T2wImageFile"_1mm_padx "$T2wImageFile"_1mm "$T2wImageFile"_1mm_padx
  rm "$T2wImageFile"_1mm_pad1x.nii.gz "$T2wImageFile"_1mm_padx.nii.gz
else
  fslcreatehd $padx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$T2wImageFile"_1mm_padx
  fslmerge -x "$T2wImageFile"_1mm "$T2wImageFile"_1mm_padx "$T2wImageFile"_1mm "$T2wImageFile"_1mm_padx
  rm "$T2wImageFile"_1mm_padx.nii.gz
fi

if [ $oddy -eq 1 ] ; then
  fslcreatehd 256 $oddy $dimez 1 1 1 1 1 0 0 0 16 "$T2wImageFile"_1mm_pad1y
  fslcreatehd 256 $pady $dimez 1 1 1 1 1 0 0 0 16 "$T2wImageFile"_1mm_pady
  fslmerge -y "$T2wImageFile"_1mm "$T2wImageFile"_1mm_pad1y "$T2wImageFile"_1mm_pady "$T2wImageFile"_1mm "$T2wImageFile"_1mm_pady
  rm "$T2wImageFile"_1mm_pad1y.nii.gz "$T2wImageFile"_1mm_pady.nii.gz
else
  fslcreatehd 256 $pady $dimez 1 1 1 1 1 0 0 0 16 "$T2wImageFile"_1mm_pady
  fslmerge -y "$T2wImageFile"_1mm "$T2wImageFile"_1mm_pady "$T2wImageFile"_1mm "$T2wImageFile"_1mm_pady
  rm "$T2wImageFile"_1mm_pady.nii.gz
fi

if [ $oddz -eq 1 ] ; then
  fslcreatehd 256 256 $oddz 1 1 1 1 1 0 0 0 16 "$T2wImageFile"_1mm_pad1z
  fslcreatehd 256 256 $padz 1 1 1 1 1 0 0 0 16 "$T2wImageFile"_1mm_padz
  rm "$T2wImageFile"_1mm_pad1z.nii.gz "$T2wImageFile"_1mm_padz.nii.gz
else
  fslcreatehd 256 256 $padz 1 1 1 1 1 0 0 0 16 "$T2wImageFile"_1mm_padz
  fslmerge -z "$T2wImageFile"_1mm "$T2wImageFile"_1mm_padz "$T2wImageFile"_1mm "$T2wImageFile"_1mm_padz
  rm "$T2wImageFile"_1mm_padz.nii.gz
fi

fslorient -setsformcode 1 "$T2wImageFile"_1mm
fslorient -setsform -1 0 0 `echo "$originx + $padx" | bc -l` 0 1 0 `echo "$originy - $pady" | bc -l` 0 0 1 `echo "$originz - $padz" | bc -l` 0 0 0 1 "$T2wImageFile"_1mm
#in FSL, matrix is identity, will not be in other conventions
fslmaths "$T1wImageFile"_1mm.nii.gz -div $Mean -mul 150 -abs "$T1wImageFile"_1mm.nii.gz

#Initial Recon-all Steps
if [ -e "$SubjectDIR"/"$SubjectID" ] ; then
  rm -r "$SubjectDIR"/"$SubjectID"
fi
if [ -e "$SubjectDIR"/"$SubjectID"_1mm ] ; then
  rm -r "$SubjectDIR"/"$SubjectID"_1mm
fi
recon-all -i "$T1wImageFile"_1mm.nii.gz -subjid $SubjectID -sd $SubjectDIR -motioncor 

#Copy in linear transformation matrices
#cp "$FSLinearTransform" "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach.xfm
#tkregister2 --noedit --check-reg --mov "$SubjectDIR"/"$SubjectID"/mri/orig.mgz --targ "$FREESURFER_HOME"/average/mni305.cor.mgz --xfm "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach.xfm --ltaout "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach.lta
#cp "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach.lta "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach_with_skull.lta 
#cp "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach.lta "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach_with_skull_2.lta 

cp "$SubjectDIR"/"$SubjectID"/mri/orig.mgz "$SubjectDIR"/"$SubjectID"/mri/nu.mgz

recon-all -subjid $SubjectID -sd $SubjectDIR -normalization 

#Copy over brainmask, later, consider replacing with skull GCA
cp "$SubjectDIR"/"$SubjectID"/mri/T1.mgz "$SubjectDIR"/"$SubjectID"/mri/brainmask.mgz

recon-all -subjid $SubjectID -sd $SubjectDIR -gcareg -gca-dir $GCAdir
cp "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach.lta "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach_with_skull.lta 
cp "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach.lta "$SubjectDIR"/"$SubjectID"/mri/transforms/talairach_with_skull_2.lta 

#Replace with Chimp GCA
recon-all -subjid $SubjectID -sd $SubjectDIR -canorm -gca-dir $GCAdir

#Replace with Chimp GCA
recon-all -subjid $SubjectID -sd $SubjectDIR -careg -gca-dir $GCAdir

#Replace with Chimp GCA
recon-all -subjid $SubjectID -sd $SubjectDIR -careginv -gca-dir $GCAdir

#Replace with Chimp GCA
#recon-all -subjid $SubjectID -sd $SubjectDIR -calabel -gca-dir $GCAdir 

if [ $AsegEdit = "NONE" ] ; then
  DIR=`pwd`
  cd "$SubjectDIR"/"$SubjectID"/mri
  mri_ca_label -align -nobigventricles -nowmsa norm.mgz transforms/talairach.m3z "$GCAdir"/RB_all_2008-03-26.gca aseg.auto_noCCseg.mgz
  mri_cc -aseg aseg.auto_noCCseg.mgz -o aseg.auto.mgz -lta "$SubjectDIR"/"$SubjectID"/mri/transforms/cc_up.lta "$SubjectID"
  cp aseg.auto.mgz aseg.mgz
  cd $DIR
else
  cp $AsegEdit "$SubjectDIR"/"$SubjectID"/mri/aseg.mgz
  cp $AsegEdit "$SubjectDIR"/"$SubjectID"/mri/aseg.auto_noCCseg.mgz
fi

#recon-all -subjid $SubjectID -sd $SubjectDIR -normalization2 -maskbfs -segmentation -fill -tessellate -smooth1 -inflate1 -qsphere -fix
cp "$SubjectDIR"/"$SubjectID"/mri/norm.mgz "$SubjectDIR"/"$SubjectID"/mri/brain.mgz 
recon-all -subjid $SubjectID -sd $SubjectDIR -maskbfs -segmentation -fill -tessellate -smooth1 -inflate1 -qsphere -fix 


recon-all -subjid $SubjectID -sd $SubjectDIR -white 

#Issues with transform?
#Highres white stuff and Fine Tune T2w to T1w Reg
"$PipelineScripts"/FreeSurferHiresWhite.sh "$SubjectID" "$SubjectDIR" "$T1wImage" "$T2wImage"

#Intermediate Recon-all Steps
recon-all -subjid $SubjectID -sd $SubjectDIR -smooth2 -inflate2 -sphere
#}
#Surface Reg To Chimp Template
recon-all -subjid $SubjectID -sd $SubjectDIR -surfreg -avgcurvtifpath $GCAdir

#More Intermediate Recon-all Steps
recon-all -subjid $SubjectID -sd $SubjectDIR -jacobian_white 

#Is this step needed or could something else, like ?h.cortex.label, be substuted in for cortex label for pial surface
recon-all -subjid $SubjectID -sd $SubjectDIR -cortparc 

#Issues with transform?
#Highres pial stuff (this module adjusts the pial surface based on the the T2w image)
"$PipelineScripts"/FreeSurferHiresPial.sh "$SubjectID" "$SubjectDIR" "$T1wImage" "$T2wImage"

cp "$SubjectDIR"/"$SubjectID"/mri/aseg.mgz "$SubjectDIR"/"$SubjectID"/mri/wmparc.mgz

mv "$SubjectDIR"/"$SubjectID" "$SubjectDIR"/"$SubjectID"_1mm
mkdir -p "$SubjectDIR"/"$SubjectID"/mri
mkdir -p "$SubjectDIR"/"$SubjectID"/mri/transforms
mkdir -p "$SubjectDIR"/"$SubjectID"/surf
mkdir -p "$SubjectDIR"/"$SubjectID"/label
#}
#Bad interpolation
# FROM 1MM to 0.5MM AFTER RECON-ALL
mri_convert -rt cubic -at "$RescaleVolumeTransform".xfm -rl "$T1wImage" "$SubjectDIR"/"$SubjectID"_1mm/mri/rawavg.mgz "$SubjectDIR"/"$SubjectID"/mri/rawavg.mgz
mri_convert "$SubjectDIR"/"$SubjectID"/mri/rawavg.mgz "$SubjectDIR"/"$SubjectID"/mri/rawavg.nii.gz
mri_convert -rt nearest -at "$RescaleVolumeTransform".xfm -rl "$T1wImage" "$SubjectDIR"/"$SubjectID"_1mm/mri/wmparc.mgz "$SubjectDIR"/"$SubjectID"/mri/wmparc.mgz
mri_convert -rt nearest -at "$RescaleVolumeTransform".xfm -rl "$T1wImage" "$SubjectDIR"/"$SubjectID"_1mm/mri/brain.finalsurfs.mgz "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz
mri_convert -rt cubic -at "$RescaleVolumeTransform".xfm -rl "$T1wImage" "$SubjectDIR"/"$SubjectID"_1mm/mri/orig.mgz "$SubjectDIR"/"$SubjectID"/mri/orig.mgz

mri_convert -rl "$SubjectDIR"/"$SubjectID"_1mm/mri/rawavg.mgz "$SubjectDIR"/"$SubjectID"_1mm/mri/wmparc.mgz "$SubjectDIR"/"$SubjectID"_1mm/mri/wmparc.nii.gz
mri_convert -rl "$SubjectDIR"/"$SubjectID"_1mm/mri/rawavg.mgz "$SubjectDIR"/"$SubjectID"_1mm/mri/brain.finalsurfs.mgz "$SubjectDIR"/"$SubjectID"_1mm/mri/brain.finalsurfs.nii.gz
mri_convert -rl "$SubjectDIR"/"$SubjectID"_1mm/mri/rawavg.mgz "$SubjectDIR"/"$SubjectID"_1mm/mri/orig.mgz "$SubjectDIR"/"$SubjectID"_1mm/mri/orig.nii.gz

applywarp --interp=nn -i "$SubjectDIR"/"$SubjectID"_1mm/mri/wmparc.nii.gz -r "$SubjectDIR"/"$SubjectID"/mri/rawavg.nii.gz --premat="$RescaleVolumeTransform".mat -o "$SubjectDIR"/"$SubjectID"/mri/wmparc.nii.gz
applywarp --interp=nn -i "$SubjectDIR"/"$SubjectID"_1mm/mri/brain.finalsurfs.nii.gz -r "$SubjectDIR"/"$SubjectID"/mri/rawavg.nii.gz --premat="$RescaleVolumeTransform".mat -o "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.nii.gz
applywarp --interp=nn -i "$SubjectDIR"/"$SubjectID"_1mm/mri/orig.nii.gz -r "$SubjectDIR"/"$SubjectID"/mri/rawavg.nii.gz --premat="$RescaleVolumeTransform".mat -o "$SubjectDIR"/"$SubjectID"/mri/orig.nii.gz

mri_convert "$SubjectDIR"/"$SubjectID"/mri/wmparc.nii.gz "$SubjectDIR"/"$SubjectID"/mri/wmparc.mgz
mri_convert "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.nii.gz "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz
mri_convert "$SubjectDIR"/"$SubjectID"/mri/orig.nii.gz "$SubjectDIR"/"$SubjectID"/mri/orig.mgz

mri_surf2surf --s "$SubjectID"_1mm --sval-xyz white --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval white_temp --hemi lh
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.white_temp "$SubjectDIR"/"$SubjectID"/surf/lh.white
mri_surf2surf --s "$SubjectID"_1mm --sval-xyz white --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval white_temp --hemi rh
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.white_temp "$SubjectDIR"/"$SubjectID"/surf/rh.white
mri_surf2surf --s "$SubjectID"_1mm --sval-xyz pial --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval pial_temp --hemi lh
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.pial_temp "$SubjectDIR"/"$SubjectID"/surf/lh.pial
mri_surf2surf --s "$SubjectID"_1mm --sval-xyz pial --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval pial_temp --hemi rh
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.pial_temp "$SubjectDIR"/"$SubjectID"/surf/rh.pial

mri_surf2surf --s "$SubjectID"_1mm --sval-xyz white.deformed --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval white.deformed_temp --hemi lh
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.white.deformed_temp "$SubjectDIR"/"$SubjectID"/surf/lh.white.deformed
mri_surf2surf --s "$SubjectID"_1mm --sval-xyz white.deformed --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval white.deformed_temp --hemi rh
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.white.deformed_temp "$SubjectDIR"/"$SubjectID"/surf/rh.white.deformed


cp "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.sphere "$SubjectDIR"/"$SubjectID"/surf/lh.sphere
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.sphere "$SubjectDIR"/"$SubjectID"/surf/rh.sphere
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.sphere.reg "$SubjectDIR"/"$SubjectID"/surf/lh.sphere.reg
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.sphere.reg "$SubjectDIR"/"$SubjectID"/surf/rh.sphere.reg
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.curv "$SubjectDIR"/"$SubjectID"/surf/lh.curv
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.curv "$SubjectDIR"/"$SubjectID"/surf/rh.curv
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.sulc "$SubjectDIR"/"$SubjectID"/surf/lh.sulc
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.sulc "$SubjectDIR"/"$SubjectID"/surf/rh.sulc

cp "$SubjectDIR"/"$SubjectID"_1mm/label/lh.cortex.label "$SubjectDIR"/"$SubjectID"/label/lh.cortex.label
cp "$SubjectDIR"/"$SubjectID"_1mm/label/rh.cortex.label "$SubjectDIR"/"$SubjectID"/label/rh.cortex.label

cp "$RescaleVolumeTransform".mat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/fs2real.mat
convert_xfm -omat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/real2fs.mat -inverse "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/fs2real.mat
convert_xfm -omat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/temp.mat -concat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/T2wtoT1w.mat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/real2fs.mat
convert_xfm -omat "$SubjectDIR"/"$SubjectID"/mri/transforms/T2wtoT1w.mat -concat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/fs2real.mat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/temp.mat
rm "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/temp.mat
cp "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/eye.dat "$SubjectDIR"/"$SubjectID"/mri/transforms/eye.dat
cat "$SubjectDIR"/"$SubjectID"/mri/transforms/eye.dat | sed "s/${SubjectID}/${SubjectID}_1mm/g" > "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/eye.dat


for hemisphere in l r ; do
  cp "$SubjectDIR"/"$SubjectID"_1mm/surf/${hemisphere}h.thickness "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.thickness
  #mris_convert "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.white "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.white.surf.gii
  #mris_convert "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.pial "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.pial.surf.gii
  #mris_convert -c "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.thickness "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.white "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.roi.shape.gii 
  #${CARET7DIR}/wb_command -surface-to-surface-3d-distance "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.white.surf.gii "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.pial.surf.gii "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.thickness.shape.gii
  #${CARET7DIR}/wb_command -metric-math "roi * min(thickness, 6)" "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.thickness.shape.gii -var thickness "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.thickness.shape.gii -var roi "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.roi.shape.gii
  #mris_convert -c "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.thickness.shape.gii "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.white "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.thickness.asc 
  #rm "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.white.surf.gii "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.pial.surf.gii "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.thickness.shape.gii "$SubjectDIR"/"$SubjectID"/surf/${hemisphere}h.roi.shape.gii  
done 
surf="${SubjectDIR}/${SubjectID}/surf"
hemi="lh"
matlab <<M_PROG
corticalthickness('${surf}','${hemi}');
M_PROG
hemi="rh"
matlab <<M_PROG
corticalthickness('${surf}','${hemi}');
M_PROG


