#!/bin/bash
# takes a T1 or T2 input with asegs and returns name_WM.nii.gz, name_GM.nii.gz, and name_CSF.nii.gz in the working directory.

struct_name=`remove_ext $1`
aseg=$2

WM=${struct_name}_WM.nii.gz
GM=${struct_name}_GM.nii.gz
CSF=${struct_name}_CSF.nii.gz

#fslmaths $aseg -thr 2 -uthr 2 tmp.nii.gz
#fslmaths $aseg -thr 41 -uthr 41 -add tmp.nii.gz -bin -mul $struct_name $WM
fslmaths $aseg -thr 3 -uthr 3 tmp.nii.gz
fslmaths $aseg -thr 42 -uthr 42 -add tmp.nii.gz -bin -mul $struct_name $GM
fslmaths $aseg -thr 17 -uthr 17 -mul $struct_name -bin -add $GM $GM
fslmaths $aseg -thr 18 -uthr 18 -mul $struct_name -bin -add $GM $GM
fslmaths $aseg -thr 53 -uthr 53 -mul $struct_name -bin -add $GM $GM
fslmaths $aseg -thr 54 -uthr 54 -mul $struct_name -bin -add $GM $GM
fslmaths $GM -bin -mul $struct_name $GM
fslmaths $GM -binv -mul $struct_name $WM
fslmaths $aseg -binv -mul $struct_name $CSF
fslmaths $CSF -binv tmp.nii.gz
fslmaths $WM -mas tmp.nii.gz $WM
rm tmp.nii.gz
