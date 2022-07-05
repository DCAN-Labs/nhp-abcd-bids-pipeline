#!/bin/bash
set -ex
# Last edited by Darrick 11/9/2016 added Pial
# Last edited by Darrick 12/7/2016, replaced T1wImage usage in the code with T1wImageBrain

source $HCPPIPEDIR/global/scripts/log.shlib  # Logging related functions
source $HCPPIPEDIR/global/scripts/opts.shlib # Command line option functions

source ${FREESURFER_HOME}/SetUpFreeSurfer.sh

log_SetToolName "FNL_FreeGreyPipeline.sh"

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
    show_usage
fi

log_Msg "Parsing Command Line Options"

# Input Variables
SubjectID=`opts_GetOpt1 "--subject" $@` #FreeSurfer Subject ID Name
SubjectDIR=`opts_GetOpt1 "--subjectDIR" $@` #Location to Put FreeSurfer Subject's Folder
T1wImage=`opts_GetOpt1 "--t1" $@` #T1w FreeSurfer Input (Full Resolution)
T1wImageBrain=`opts_GetOpt1 "--t1brain" $@`
T2wImage=`opts_GetOpt1 "--t2" $@` #T2w FreeSurfer Input (Full Resolution)
recon_all_seed=`opts_GetOpt1 "--seed" $@`
Aseg=`opts_GetOpt1 "--aseg" $@` #DS 20170419
GCA=`opts_GetOpt1 "--gca" $@`
useT2=`opts_GetOpt1 "--useT2" $@` #AP 20162111
MaxThickness=`opts_GetOpt1 "--maxThickness" $@` # Max threshold for thickness measurements (default = 5mm)
NormMethod=`opts_GetOpt1 "--normalizationMethod" $@` # Normalization method to be used (or none)
hypernormalize=`opts_GetOpt1 "--hypernormalize" $@` #deprecated - lose after BIDSApp doesn't use it anymore.
NormGMStdDevScale=`opts_GetOpt1 "--normgmstddevscale" $@` # normalized GM std dev scale factor
NormWMStdDevScale=`opts_GetOpt1 "--normwmstddevscale" $@` # normalized WM std dev scale factor
NormCSFStdDevScale=`opts_GetOpt1 "--normcsfstddevscale" $@` # normalized CSF std dev scale factor

# option to make white surface from adult-normalized T1w (if it exists)
MakeWhiteFromNormT1=`opts_GetOpt1 "--makewhitefromnormt1" $@`
MakeWhiteFromNormT1="$(echo ${MakeWhiteFromNormT1} | tr '[:upper:]' '[:lower:]')" # to lower case

# option to keep the pial surface generated from initial pass of mris_make_surfaces 
# (using the hypernormalized brain.AN.mgz T1w image, unless hypernormalization was omitted)
# instead of using it as a prior for a 2nd pass of mris_make_surfaces
# (2nd pass uses the non-hypernormalized brain.finalsurfs.mgz T1w by default)
SinglePassPial=`opts_GetOpt1 "--singlepasspial" $@` 
SinglePassPial="$(echo ${SinglePassPial} | tr '[:upper:]' '[:lower:]')" # to lower case

if [ -z "${NormMethod}" ] ; then
    # Default is to use the adult grey matter intensity profile.
    NormMethod="ADULT_GM_IP"
fi

if [[ "${NormMethod^^}" == "NONE" ]] ; then
    Modalities="T1w"
else
    Modalities="T1w T1wN"
fi

if [ -z "${MaxThickness}" ] ; then
    MaxThickness=5     # FreeSurfer default is 5 mm
fi
MAXTHICKNESS="-max ${MaxThickness}"

######## FNL CODE #######
echo "`basename $0` $@"
echo "START: `basename $0`"
SUBJECTS_DIR=$SubjectDIR
cd $SubjectDIR
rm -rf $SUBJECTS_DIR/${SubjectID}; rm -rf $SUBJECTS_DIR/${SubjectID}_1mm; rm -rf $SUBJECTS_DIR/${SubjectID}N
Subnum=$SubjectID

if [[ "${NormMethod^^}" == "NONE" ]] ; then
    echo Skipping hyper-normalization step per request.
else
    ${HCPPIPEDIR_FS}/hypernormalize.sh ${SubjectDIR} ${NormMethod^^} ${NormGMStdDevScale} ${NormWMStdDevScale} ${NormCSFStdDevScale}
    T1wNImage="T1wN_acpc.nii.gz"
    T1wNImageBrain="T1wN_acpc_brain.nii.gz"
    echo T1wNImage=$T1wNImage
    echo T1wNImageBrain=$T1wNImageBrain
    T1wNImageFile=`remove_ext $T1wNImage`
    T1wNImageBrainFile=`remove_ext $T1wNImageBrain`
fi

echo "freegrey_norm mode(s): "$Modalities
for TXw in $Modalities; do
  if [ $TXw = "skip" ]; then
    break
  fi
  if [ $TXw = "T1w" ]; then
    TXwImage=`basename "$T1wImage"`
    TXwImageBrain=`basename "$T1wImageBrain"`
    T1wImageFile=`remove_ext $TXwImage`;
    T1wImageBrainFile=`remove_ext $TXwImageBrain`;
    SubjectID=$Subnum
  fi
  if [ $TXw = "T1wN" ]; then
    TXwImage=`basename "$T1wNImage"`
    TXwImageBrain=`basename "$T1wNImageBrain"`
    SubjectID=${Subnum}N
    imcp $T1wNImage ${SubjectDIR} || true
    imcp $T1wNImageBrain ${SubjectDIR} || true
  fi
  TXwImageFile=`remove_ext $TXwImage`;
  TXwImageBrainFile=`remove_ext $TXwImageBrain`;
  AsegFile=`remove_ext ${Aseg}`;
  mksubjdirs ${SubjectID}
  if true; then
      echo "data not conformed, tricking nifti header information..."
      Mean=`fslstats $TXwImageBrain -M`
      res=`fslorient -getsform $TXwImageBrain | cut -d " " -f 1 | cut -d "-" -f 2`
      oldsform=`fslorient -getsform $TXwImageBrain`
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

    cp "$TXwImageBrain" "$TXwImageBrainFile"_1mm.nii.gz
    fslorient -setsform $newsform "$TXwImageBrainFile"_1mm.nii.gz
    fslhd -x "$TXwImageBrainFile"_1mm.nii.gz | sed s/"dx = '${res}'"/"dx = '1'"/g | sed s/"dy = '${res}'"/"dy = '1'"/g | sed s/"dz = '${res}'"/"dz = '1'"/g | fslcreatehd - "$TXwImageBrainFile"_1mm_head.nii.gz
    fslmaths "$TXwImageBrainFile"_1mm_head.nii.gz -add "$TXwImageBrainFile"_1mm.nii.gz "$TXwImageBrainFile"_1mm.nii.gz
    fslorient -copysform2qform "$TXwImageBrainFile"_1mm.nii.gz
    rm "$TXwImageBrainFile"_1mm_head.nii.gz
    dimex=`fslval "$TXwImageBrainFile"_1mm dim1`
    dimey=`fslval "$TXwImageBrainFile"_1mm dim2`
    dimez=`fslval "$TXwImageBrainFile"_1mm dim3`
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
      fslcreatehd $oddx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$TXwImageBrainFile"_1mm_pad1x
      fslcreatehd $padx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$TXwImageBrainFile"_1mm_padx
      fslmerge -x "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_pad1x "$TXwImageBrainFile"_1mm_padx "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_padx
      rm "$TXwImageBrainFile"_1mm_pad1x.nii.gz "$TXwImageBrainFile"_1mm_padx.nii.gz
    else
      fslcreatehd $padx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$TXwImageBrainFile"_1mm_padx
      fslmerge -x "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_padx "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_padx
      rm "$TXwImageBrainFile"_1mm_padx.nii.gz
    fi

    if [ $oddy -eq 1 ] ; then
      fslcreatehd 256 $oddy $dimez 1 1 1 1 1 0 0 0 16 "$TXwImageBrainFile"_1mm_pad1y
      fslcreatehd 256 $pady $dimez 1 1 1 1 1 0 0 0 16 "$TXwImageBrainFile"_1mm_pady
      fslmerge -y "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_pad1y "$TXwImageBrainFile"_1mm_pady "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_pady
      rm "$TXwImageBrainFile"_1mm_pad1y.nii.gz "$TXwImageBrainFile"_1mm_pady.nii.gz
    else
      fslcreatehd 256 $pady $dimez 1 1 1 1 1 0 0 0 16 "$TXwImageBrainFile"_1mm_pady
      fslmerge -y "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_pady "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_pady
      rm "$TXwImageBrainFile"_1mm_pady.nii.gz
    fi

    if [ $oddz -eq 1 ] ; then
      fslcreatehd 256 256 $oddz 1 1 1 1 1 0 0 0 16 "$TXwImageBrainFile"_1mm_pad1z
      fslcreatehd 256 256 $padz 1 1 1 1 1 0 0 0 16 "$TXwImageBrainFile"_1mm_padz
      fslmerge -z "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_pad1z "$TXwImageBrainFile"_1mm_padz "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_padz
      rm "$TXwImageBrainFile"_1mm_pad1z.nii.gz "$TXwImageBrainFile"_1mm_padz.nii.gz
    else
      fslcreatehd 256 256 $padz 1 1 1 1 1 0 0 0 16 "$TXwImageBrainFile"_1mm_padz
      fslmerge -z "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_padz "$TXwImageBrainFile"_1mm "$TXwImageBrainFile"_1mm_padz
      rm "$TXwImageBrainFile"_1mm_padz.nii.gz
    fi

    fslorient -setsformcode 1 "$TXwImageBrainFile"_1mm
    fslorient -setsform -1 0 0 `echo "$originx + $padx" | bc -l` 0 1 0 `echo "$originy - $pady" | bc -l` 0 0 1 `echo "$originz - $padz" | bc -l` 0 0 0 1 "$TXwImageBrainFile"_1mm

  #in FSL, matrix is identity, will not be in other conventions
    fslmaths "$TXwImageBrainFile"_1mm.nii.gz -div $Mean -mul 150 -abs "$TXwImageBrainFile"_1mm.nii.gz
    #Mean=`fslstats $TXwImageBrainBrain -M`
    res=`fslorient -getsform $Aseg | cut -d " " -f 1 |     cut -d "-" -f 2`
    oldsform=`fslorient -getsform $Aseg`
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

    cp "$Aseg" "$AsegFile"_1mm.nii.gz
    fslorient -setsform $newsform "$AsegFile"_1mm.nii.gz
    fslhd -x "$AsegFile"_1mm.nii.gz | sed s/"dx = '${res}'"/"dx = '1'"/g | sed s/"dy = '${res}'"/"dy = '1'"/g | sed s/"dz = '${res}'"/"dz = '1'"/g | fslcreatehd - "$AsegFile"_1mm_head.nii.gz
    fslmaths "$AsegFile"_1mm_head.nii.gz -add "$AsegFile"_1mm.nii.gz "$AsegFile"_1mm.nii.gz
    fslorient -copysform2qform "$AsegFile"_1mm.nii.gz
    rm "$AsegFile"_1mm_head.nii.gz
    dimex=`fslval "$AsegFile"_1mm dim1`
    dimey=`fslval "$AsegFile"_1mm dim2`
    dimez=`fslval "$AsegFile"_1mm dim3`
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
      fslcreatehd $oddx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$AsegFile"_1mm_pad1x
      fslcreatehd $padx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$AsegFile"_1mm_padx
      fslmerge -x "$AsegFile"_1mm "$AsegFile"_1mm_pad1x "$AsegFile"_1mm_padx "$AsegFile"_1mm "$AsegFile"_1mm_padx
      rm "$AsegFile"_1mm_pad1x.nii.gz "$AsegFile"_1mm_padx.nii.gz
    else
      fslcreatehd $padx $dimey $dimez 1 1 1 1 1 0 0 0 16 "$AsegFile"_1mm_padx
      fslmerge -x "$AsegFile"_1mm "$AsegFile"_1mm_padx "$AsegFile"_1mm "$AsegFile"_1mm_padx
      rm "$AsegFile"_1mm_padx.nii.gz
    fi

    if [ $oddy -eq 1 ] ; then
      fslcreatehd 256 $oddy $dimez 1 1 1 1 1 0 0 0 16 "$AsegFile"_1mm_pad1y
      fslcreatehd 256 $pady $dimez 1 1 1 1 1 0 0 0 16 "$AsegFile"_1mm_pady
      fslmerge -y "$AsegFile"_1mm "$AsegFile"_1mm_pad1y "$AsegFile"_1mm_pady "$AsegFile"_1mm "$AsegFile"_1mm_pady
      rm "$AsegFile"_1mm_pad1y.nii.gz "$AsegFile"_1mm_pady.nii.gz
    else
      fslcreatehd 256 $pady $dimez 1 1 1 1 1 0 0 0 16 "$AsegFile"_1mm_pady
      fslmerge -y "$AsegFile"_1mm "$AsegFile"_1mm_pady "$AsegFile"_1mm "$AsegFile"_1mm_pady
      rm "$AsegFile"_1mm_pady.nii.gz
    fi

    if [ $oddz -eq 1 ] ; then
      fslcreatehd 256 256 $oddz 1 1 1 1 1 0 0 0 16 "$AsegFile"_1mm_pad1z
      fslcreatehd 256 256 $padz 1 1 1 1 1 0 0 0 16 "$AsegFile"_1mm_padz
      fslmerge -z "$AsegFile"_1mm "$AsegFile"_1mm_pad1z "$AsegFile"_1mm_padz "$AsegFile"_1mm "$AsegFile"_1mm_padz
      rm "$AsegFile"_1mm_pad1z.nii.gz "$AsegFile"_1mm_padz.nii.gz
    else
      fslcreatehd 256 256 $padz 1 1 1 1 1 0 0 0 16 "$AsegFile"_1mm_padz
      fslmerge -z "$AsegFile"_1mm "$AsegFile"_1mm_padz "$AsegFile"_1mm "$AsegFile"_1mm_padz
      rm "$AsegFile"_1mm_padz.nii.gz
    fi

    fslorient -setsformcode 1 "$AsegFile"_1mm
    fslorient -setsform -1 0 0 `echo "$originx + $padx" | bc -l` 0 1 0 `echo "$originy - $pady" | bc -l` 0 0 1 `echo "$originz - $padz" | bc -l` 0 0 0 1 "$AsegFile"_1mm
  else
    cp ${TXwImageBrain} ${TXwImageBrainFile}_1mm.nii.gz
    cp ${TXwImage} ${TXwImageFile}_1mm.nii.gz
    cp ${Aseg} ${AsegFile}_1mm.nii.gz
  fi
  # if non-conformed data is not faked, this step will resample it.  Beware.
  mri_convert --conform -ns 1 ${TXwImageBrainFile}_1mm.nii.gz ${SubjectID}/mri/001.mgz
  mri_convert --conform -ns 1 ${AsegFile}_1mm.nii.gz ${SubjectID}/mri/aseg.mgz
  cp ${SubjectID}/mri/001.mgz ${SubjectID}/mri/rawavg.mgz
  cp ${SubjectID}/mri/rawavg.mgz ${SubjectID}/mri/orig.mgz
  pushd ${SubjectID}/mri
  mkdir tmp.mri_nu_correct.mni.16177
  mri_convert orig.mgz ./tmp.mri_nu_correct.mni.16177/nu0.mnc -odt float
  nu_correct -clobber ./tmp.mri_nu_correct.mni.16177/nu0.mnc ./tmp.mri_nu_correct.mni.16177/nu1.mnc -tmpdir ./tmp.mri_nu_correct.mni.16177/0/ -iterations 1000 -distance 50
  mri_convert ./tmp.mri_nu_correct.mni.16177/nu1.mnc orig_nu.mgz --like orig.mgz
  cp orig_nu.mgz nu.mgz
  cp nu.mgz brainmask.mgz
  mri_normalize -aseg aseg.mgz -brainmask brainmask.mgz nu.mgz T1.mgz
  cp T1.mgz brainmask.mgz
  mri_convert --conform -ns 1 brainmask.mgz brain.mgz
  mri_mask -T 5 brain.mgz brainmask.mgz brain.finalsurfs.mgz
  mri_em_register -uns 3 -mask brainmask.mgz nu.mgz $GCA transforms/talairach.lta
  mri_ca_normalize -mask brainmask.mgz nu.mgz $GCA transforms/talairach.lta norm.mgz # could add aseg here
  popd
done
SubjectID=$Subnum

#grab white matter
fslmaths ${AsegFile}_1mm.nii.gz -thr 41 -uthr 41 -bin blah41.nii.gz
fslmaths ${AsegFile}_1mm.nii.gz -thr 2 -uthr 2 -bin blah2.nii.gz
fslmaths blah41.nii.gz -add blah2.nii.gz wm_init.nii.gz
fslmaths wm_init.nii.gz -mul 110 wm.nii.gz #is this best?
mri_convert --conform -ns 1 wm.nii.gz wm.seg.mgz
cp wm.seg.mgz ${SubjectID}/mri/wm.seg.mgz
pushd ${SubjectID}/mri
mri_edit_wm_with_aseg -keep-in wm.seg.mgz brain.mgz aseg.mgz wm.asegedit.mgz
mri_pretess wm.asegedit.mgz wm norm.mgz wm.mgz
mri_fill -a ../scripts/ponscc.cut.log -xform transforms/talairach.lta -segmentation aseg.mgz wm.mgz filled.mgz
popd
echo "BEGIN: recon-all"

recon-all -subjid ${SubjectID} -tessellate -smooth1 -inflate1 -qsphere -fix

if [ $MakeWhiteFromNormT1 = true ] && [ ! -z $T1wNImage ]; then
  # make white surfaces from adult-normalized T1w
  echo "Making white surfaces from normalized T1w"
  # copy adult-normalized T1w volume to main subject mri dir 
  cp -T -n ${SubjectID}N/mri/brain.finalsurfs.mgz ${SubjectID}/mri/brain.AN.mgz
  for hemi in l r; do
    mris_make_surfaces -whiteonly -noaparc -mgz -T1 brain.AN ${SubjectID} ${hemi}h
  done
else
    # make white surfaces from non-normalized T1w (same as default recon-all -white)
  for hemi in l r; do
    mris_make_surfaces -whiteonly -noaparc -mgz -T1 brain.finalsurfs ${SubjectID} ${hemi}h
  done
fi

recon-all -subjid ${SubjectID} -smooth2 -inflate2 -sphere
# Using monkey .tif for calculating surface registration.
echo "Registering surface using average.curvature.filled from MacaqueYerkes19"
pushd ${SUBJECTS_DIR}/${SubjectID}/surf
for hemi in l r; do
  mris_register -curv ${hemi}h.sphere ${HCPPIPEDIR_Templates}/MacaqueYerkes19/${hemi}h.average.curvature.filled.buckner40.tif ${hemi}h.sphere.reg
  mris_jacobian ${hemi}h.white ${hemi}h.sphere.reg ${hemi}h.jacobian_white
  mrisp_paint -a 5 ${HCPPIPEDIR_Templates}/MacaqueYerkes19/${hemi}h.average.curvature.filled.buckner40.tif#6 ${hemi}h.sphere.reg ${hemi}h.avg_curv
  mris_ca_label -l ../label/${hemi}h.cortex.label -aseg ../mri/aseg.mgz $SubjectID ${hemi}h ${hemi}h.sphere.reg ${FREESURFER_HOME}/average/${hemi}h.curvature.buckner40.filled.desikan_killiany.2010-03-25.gcs ${hemi}h.aparc.annot
done
popd
cp "$SUBJECTS_DIR"/"$SubjectID"/mri/aseg.mgz "$SUBJECTS_DIR"/"$SubjectID"/mri/wmparc.mgz
cd "$SUBJECTS_DIR"
echo "Using Normalized Brain to make initial pial"
if [ ! -z $T1wNImage ]; then
  cp -T -n ${SubjectID}N/mri/brain.finalsurfs.mgz ${SubjectID}/mri/brain.AN.mgz
  for hemi in l r; do
    # use Pial from Adult-Normalized surface as a prior.
    cp -T -n ${SubjectID}/surf/"${hemi}"h.pial ${SubjectID}/surf/"${hemi}"h.pial.noAN || true
    #mris_make_surfaces ${MAXTHICKNESS} -orig_white white.noAN -white NOWRITE -mgz -T1 brain.AN $SubjectID ${hemi}h
    mris_make_surfaces ${MAXTHICKNESS} -white NOWRITE -mgz -T1 brain.AN $SubjectID ${hemi}h
      # if true, skip 2nd pass of mris_make_surfaces
      # and keep the pial derived from adult-normalized brain as the final surface
    if [ $SinglePassPial = false ]; then 
      mris_make_surfaces ${MAXTHICKNESS} -orig_pial pial -white NOWRITE -mgz -T1 brain.finalsurfs $SubjectID ${hemi}h
    else
      echo "Using single pass pial"
    fi
  done
else
  for hemi in l r; do
    #mris_make_surfaces ${MAXTHICKNESS} -orig_white white.noAN -white NOWRITE -mgz -T1 brain.AN $SubjectID ${hemi}h
    mris_make_surfaces ${MAXTHICKNESS} -white NOWRITE -mgz -T1 brain.finalsurfs $SubjectID ${hemi}h
      # if true, skip 2nd pass of mris_make_surfaces
      # and keep the initial pial as the final surface
    if [ $SinglePassPial = false ]; then
      mris_make_surfaces ${MAXTHICKNESS} -orig_pial pial -white NOWRITE -mgz -T1 brain.finalsurfs $SubjectID ${hemi}h
    else
      echo "Using single pass pial"
    fi
  done
fi

echo "BEGIN final recon-all"
recon-all -subjid ${SubjectID} -surfvolume -pctsurfcon -parcstats -cortparc2 -parcstats2 -cortribbon -segstats -aparc2aseg -wmparc -balabels -label-exvivo-ec
echo "END final recon-all"

if [ $useT2 = true ]; then
  echo "skipping hires stages"
  # Run FreeSurferHiresWhite
#	${HCPPIPEDIR}/FreeSurfer/scripts/FreeSurferHiresWhite.sh ${SubjectID} ${SubjectDIR} ${SubjectDIR}/${T1wImageBrainFile}.nii.gz ${SubjectDIR}/T2w_acpc_dc_restore_brain.nii.gz;
  # Run FreeSurferHiresPial
#  ${HCPPIPEDIR}/FreeSurfer/scripts/FreeSurferHiresPial.sh ${SubjectID} ${SubjectDIR} ${SubjectDIR}/${T1wImageBrainFile}.nii.gz ${SubjectDIR}/T2w_acpc_dc_restore_brain.nii.gz 10;
  #bene inserted lines 289-374 from /group_shares/PSYCH/code/development/pipelines/HCP_NHP_generic/FreeSurfer/FreeSurferPipelineNHP.sh 12-6-16
else
	pushd T1w/${SubjectID}/mri
	mkdir transforms # this xfm may be incorrect here.
	echo "$SubjectID" > transforms/eye.dat
	echo "1" >> transforms/eye.dat
	echo "1" >> transforms/eye.dat
	echo "1" >> transforms/eye.dat
	echo "1 0 0 0" >> transforms/eye.dat
	echo "0 1 0 0" >> transforms/eye.dat
	echo "0 0 1 0" >> transforms/eye.dat
	echo "0 0 0 1" >> transforms/eye.dat
	echo "round" >> transforms/eye.dat
	popd
fi


#  This is always true for monkeys at the moment, maybe with freesurfer 6.0 this will become unnecessary...
if true; then
RescaleVolumeTransform=${HCPPIPEDIR}/global/templates/fs_xfms/Macaque_rescale
cp "$SubjectDIR"/"$SubjectID"/mri/aseg.mgz "$SubjectDIR"/"$SubjectID"/mri/wmparc.mgz

mv "$SubjectDIR"/"$SubjectID" "$SubjectDIR"/"$SubjectID"_1mm
mkdir -p "$SubjectDIR"/"$SubjectID"/mri
mkdir -p "$SubjectDIR"/"$SubjectID"/mri/transforms
mkdir -p "$SubjectDIR"/"$SubjectID"/surf
mkdir -p "$SubjectDIR"/"$SubjectID"/label
#}
#Bad interpolation
# FROM 1MM to 0.5MM AFTER RECON-ALL
mri_convert -rt nearest -at "$RescaleVolumeTransform".xfm -rl ${T1wImageBrainFile}.nii.gz "$SubjectDIR"/"$SubjectID"_1mm/mri/rawavg.mgz "$SubjectDIR"/"$SubjectID"/mri/rawavg.mgz
mri_convert "$SubjectDIR"/"$SubjectID"/mri/rawavg.mgz "$SubjectDIR"/"$SubjectID"/mri/rawavg.nii.gz
# this worked fine.......

mri_convert -rt nearest -at "$RescaleVolumeTransform".xfm -rl ${T1wImageBrainFile}.nii.gz "$SubjectDIR"/"$SubjectID"_1mm/mri/wmparc.mgz "$SubjectDIR"/"$SubjectID"/mri/wmparc.mgz
mri_convert -rt nearest -at "$RescaleVolumeTransform".xfm -rl ${T1wImageBrainFile}.nii.gz "$SubjectDIR"/"$SubjectID"_1mm/mri/brain.finalsurfs.mgz "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz
mri_convert -rt nearest -at "$RescaleVolumeTransform".xfm -rl ${T1wImageBrainFile}.nii.gz "$SubjectDIR"/"$SubjectID"_1mm/mri/orig.mgz "$SubjectDIR"/"$SubjectID"/mri/orig.mgz
mri_convert -rt nearest -at "$RescaleVolumeTransform".xfm -rl ${T1wImageBrainFile}.nii.gz "$SubjectDIR"/"$SubjectID"_1mm/mri/aparc+aseg.mgz "$SubjectDIR"/"$SubjectID"/mri/aparc+aseg.mgz
mri_convert -rt nearest -at "$RescaleVolumeTransform".xfm -rl ${T1wImageBrainFile}.nii.gz "$SubjectDIR"/"$SubjectID"_1mm/mri/aparc.a2009s+aseg.mgz "$SubjectDIR"/"$SubjectID"/mri/aparc.a2009s+aseg.mgz
mri_convert "$SubjectDIR"/"$SubjectID"/mri/aparc+aseg.mgz "$SubjectDIR"/"$SubjectID"/mri/aparc+aseg.nii.gz
mri_convert "$SubjectDIR"/"$SubjectID"/mri/aparc.a2009s+aseg.mgz "$SubjectDIR"/"$SubjectID"/mri/aparc.a2009s+aseg.nii.gz

# Adding ribbon to rescalings
mri_convert -rt nearest -at "$RescaleVolumeTransform".xfm -rl ${T1wImageBrainFile}.nii.gz "$SubjectDIR"/"$SubjectID"_1mm/mri/lh.ribbon.mgz "$SubjectDIR"/"$SubjectID"/mri/lh.ribbon.mgz
mri_convert -rt nearest -at "$RescaleVolumeTransform".xfm -rl ${T1wImageBrainFile}.nii.gz "$SubjectDIR"/"$SubjectID"_1mm/mri/rh.ribbon.mgz "$SubjectDIR"/"$SubjectID"/mri/rh.ribbon.mgz

mri_surf2surf --s "$SubjectID"_1mm --sval-xyz white --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval white_temp --hemi lh
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.white_temp "$SubjectDIR"/"$SubjectID"/surf/lh.white
mri_surf2surf --s "$SubjectID"_1mm --sval-xyz white --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval white_temp --hemi rh
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.white_temp "$SubjectDIR"/"$SubjectID"/surf/rh.white
mri_surf2surf --s "$SubjectID"_1mm --sval-xyz pial --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval pial_temp --hemi lh
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.pial_temp "$SubjectDIR"/"$SubjectID"/surf/lh.pial
mri_surf2surf --s "$SubjectID"_1mm --sval-xyz pial --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval pial_temp --hemi rh
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.pial_temp "$SubjectDIR"/"$SubjectID"/surf/rh.pial

mri_surf2surf --s "$SubjectID"_1mm --sval-xyz white.deformed --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval white.deformed_temp --hemi lh || true
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.white.deformed_temp "$SubjectDIR"/"$SubjectID"/surf/lh.white.deformed || true
mri_surf2surf --s "$SubjectID"_1mm --sval-xyz white.deformed --reg-inv "$RescaleVolumeTransform".dat "$SubjectDIR"/"$SubjectID"/mri/brain.finalsurfs.mgz --tval-xyz --tval white.deformed_temp --hemi rh || true
mv "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.white.deformed_temp "$SubjectDIR"/"$SubjectID"/surf/rh.white.deformed || true


cp "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.sphere "$SubjectDIR"/"$SubjectID"/surf/lh.sphere
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.sphere "$SubjectDIR"/"$SubjectID"/surf/rh.sphere
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.sphere.reg "$SubjectDIR"/"$SubjectID"/surf/lh.sphere.reg
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.sphere.reg "$SubjectDIR"/"$SubjectID"/surf/rh.sphere.reg
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.curv "$SubjectDIR"/"$SubjectID"/surf/lh.curv # this may be incorrect here.
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.curv "$SubjectDIR"/"$SubjectID"/surf/rh.curv #
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/lh.sulc "$SubjectDIR"/"$SubjectID"/surf/lh.sulc #
cp "$SubjectDIR"/"$SubjectID"_1mm/surf/rh.sulc "$SubjectDIR"/"$SubjectID"/surf/rh.sulc #

cp "$SubjectDIR"/"$SubjectID"_1mm/label/* "$SubjectDIR"/"$SubjectID"/label

cp "$RescaleVolumeTransform".mat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/fs2real.mat # this probably needs an adjustment...  it needs to include the coordinate shift.
convert_xfm -omat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/real2fs.mat -inverse "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/fs2real.mat
if [ $useT2 -a ! $old_scans ]; then
convert_xfm -omat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/temp.mat -concat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/T2wtoT1w.mat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/real2fs.mat || true
convert_xfm -omat "$SubjectDIR"/"$SubjectID"/mri/transforms/T2wtoT1w.mat -concat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/fs2real.mat "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/temp.mat || true
rm "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/temp.mat || true
fi
cp "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/eye.dat "$SubjectDIR"/"$SubjectID"/mri/transforms/eye.dat || true
cat "$SubjectDIR"/"$SubjectID"/mri/transforms/eye.dat | sed "s/${SubjectID}/${SubjectID}_1mm/g" > "$SubjectDIR"/"$SubjectID"_1mm/mri/transforms/eye.dat || true # potential issue here.

fslmaths "$T1wImage" -abs -add 1 "$SubjectDIR"/"$SubjectID"/mri/T1w_hires.nii.gz

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

#surf="${SubjectDIR}/${SubjectID}/surf"
#hemi="lh"
#matlab <<M_PROG
#corticalthickness('${surf}','${hemi}');
#M_PROG
#hemi="rh"
#matlab <<M_PROG
#corticalthickness('${surf}','${hemi}');
#M_PROG

fi

echo -e "End: FNL_FreeGrey"
