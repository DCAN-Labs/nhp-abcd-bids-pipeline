import os
import logging
import shutil
from typing import Tuple

import numpy as np
import nibabel as nib
from memori import Stage
from memori.helpers import create_output_path, working_directory
from memori.pathman import PathManager
from omni.pipelines.logging import setup_logging
from omni.pipelines.func.align import deoblique_func
from omni.pipelines.preprocessing import synthunwarp
from omni.interfaces.common import run_process
from omni.interfaces.ants import N4BiasFieldCorrection
from omni.affine import deoblique
from omni.io import convert_affine_file
from omni.preprocessing import normalization
from omni.warp import convert_warp

from nhp_abcd.shim import DCANPipeline
from nhp_abcd.helpers import get_contrast_agent, get_fmriname, ijk_to_xyz, get_relpath
from .pipelines import ParameterSettings


# get environment variables to HCP pipeline stuff
pipeline_scripts = os.environ.get("HCPPIPEDIR_fMRIVol", False)
global_scripts = os.environ.get("HCPPIPEDIR_Global", False)
# raise Exception if any of these are not set
if not all([pipeline_scripts, global_scripts]):
    raise Exception("HCP pipeline environment variables not set!")

# Global Naming Conventions
# These were copied over from the original shell script
# TODO: don't use these, instead we want to pass information
# to each stage of the pipeline through non-global variable means
T1wImage = "T1w_acpc_dc"
T1wBrainMask = "T1w_acpc_brain_mask"
T1wRestoreImage = "T1w_acpc_dc_restore"
T1wRestoreImageBrain = "T1w_acpc_dc_restore_brain"
T2wRestoreImage = "T2w_acpc_dc_restore"
T2wRestoreImageBrain = "T2w_acpc_dc_restore_brain"
T1wFolder = "T1w"  # Location of T1w images
AtlasSpaceFolder = "MNINonLinear"
ResultsFolder = "Results"
BiasField = "BiasField_acpc_dc"
BiasFieldMNI = "BiasField"
T1wAtlasName = "T1w_restore"
MovementRegressor = "Movement_Regressors"  # No extension, .txt appended
MotionMatrixFolder = "MotionMatrices"
MotionMatrixPrefix = "MAT_"
FieldMapOutputName = "FieldMap"
MagnitudeOutputName = "Magnitude"
MagnitudeBrainOutputName = "Magnitude_brain"
ScoutName = "Scout"
OrigScoutName = f"{ScoutName}_orig"
FreeSurferBrainMask = f"brainmask_fs"
RegOutput = "Scout2T1w"
AtlasTransform = "acpc_dc2standard"
QAImage = "T1wMulEPI"
JacobianOut = "Jacobian"


@create_output_path
def intensity_normalization(
    output_path: str,
    func_atlas: str,
    scout_atlas: str,
    bias_field: str,
    jacobian: str,
    brain_mask: str,
) -> Tuple[str, str]:
    """Intensity Normalization

    Parameters
    ----------
    output_path : str
        Output path.
    func_atlas : str
        Functional in atlas space.
    scout_atlas : str
        Scout in atlas space.
    bias_field : str
        bias field correction.
    jacobian : str
        Jacobian of final transformation
    brain_mask : str
        Atlas brain mask.

    Returns
    -------
    str
        Normalized functional.
    str
        Normalized scout.
    """
    # define paths
    func_atlas_norm = PathManager(func_atlas).repath(output_path).append_suffix("_norm").get_path_and_prefix().path
    scout_atlas_norm = PathManager(scout_atlas).repath(output_path).append_suffix("_norm").get_path_and_prefix().path
    func_atlas = PathManager(func_atlas).get_path_and_prefix().path
    scout_atlas = PathManager(scout_atlas).get_path_and_prefix().path

    # run intensity normalization
    run_process(
        f"{pipeline_scripts}/IntensityNormalization.sh "
        f"--infmri={func_atlas} "
        f"--biasfield={bias_field} "
        f"--jacobian={jacobian} "
        f"--brainmask={brain_mask} "
        f"--ofmri={func_atlas_norm} "
        f"--inscout={scout_atlas} "
        f"--oscout={scout_atlas_norm} "
        f"--usejacobian=false "
    )

    # add back in extensions
    func_atlas_norm += ".nii.gz"
    scout_atlas_norm += ".nii.gz"

    # return intensity normalized data
    return func_atlas_norm, scout_atlas_norm


@create_output_path
def one_step_resampling(
    output_path: str,
    func: str,
    scout: str,
    scout_gdc: str,
    jacobian: str,
    t1_atlas: str,
    fmri2struct: str,
    struct2std: str,
    freesurfer_brain_mask: str,
    bias_field: str,
    gdc_warp: str,
    fmriresout: float = 1.5,
) -> Tuple[str, str, str]:
    """Resample the functional data to the atlas space.

    Parameters
    ----------
    output_path : str
        Output path.
    func : str
        Full functional time series data.
    scout : str
        Reference frame.
    scout_gdc : str
        Reference frame with GDC applied.
    jacobian : str
        Jacobian of distortion correction warp (currently doesn't work)
    t1_atlas : str
        T1 in atlas space.
    fmri2struct : str
        functional to anatomical transform.
    struct2std : str
        anatomical to standard space transform.
    freesurfer_brain_mask : str
        Freesurfer brain mask.
    bias_field : str
        bias field correction.
    gdc_warp : str
        Gradient Distortion Correction warp.
    fmriresout : float, optional
        Resolution of final output, by default 1.5

    Returns
    -------
    str
        functional image in atlas space.
    str
        scout image in atlas space.
    str
        jacobian image in atlas space.
    """
    # set working directory
    working_dir = os.path.join(output_path, "OneStepResampling")

    # set paths
    OutputfMRI2StandardTransform = f"{output_path}2standard"
    Standard2OutputfMRITransform = f"standard2{output_path}"
    func_atlas = PathManager(func).repath(output_path).append_suffix("_nonlin").get_path_and_prefix().path
    scout_atlas = PathManager(func).repath(output_path).append_suffix("_SBRef_nonlin").get_path_and_prefix().path
    jacobian_out = (
        PathManager(jacobian).repath(output_path).get_path_and_prefix().append_suffix(f"_MNI.{fmriresout}").path
    )

    # run resampling code
    run_process(
        f"{pipeline_scripts}/OneStepResampling.sh "
        f"--workingdir={working_dir} "
        f"--infmri={func} "
        f"--t1={t1_atlas} "
        f"--fmriresout={fmriresout} "
        f"--fmrifolder={output_path} "
        f"--fmri2structin={fmri2struct} "
        f"--struct2std={struct2std} "
        f"--owarp={AtlasSpaceFolder}/xfms/{OutputfMRI2StandardTransform} "
        f"--oiwarp={AtlasSpaceFolder}/xfms/{Standard2OutputfMRITransform} "
        f"--motionmatdir={output_path}/{MotionMatrixFolder} "
        f"--motionmatprefix={MotionMatrixPrefix} "
        f"--ofmri={func_atlas} "
        f"--freesurferbrainmask={freesurfer_brain_mask} "
        f"--biasfield={bias_field} "
        f"--gdfield={gdc_warp} "
        f"--scoutin={scout} "
        f"--scoutgdcin={scout_gdc} "
        f"--oscout={scout_atlas} "
        f"--jacobianin={jacobian} "
        f"--ojacobian={jacobian_out} "
    )

    # add suffix
    func_atlas += ".nii.gz"
    scout_atlas += ".nii.gz"
    jacobian_out += ".nii.gz"

    # return atlas aligned stuff
    return (func_atlas, scout_atlas, jacobian_out)


@create_output_path
def synth_distortion_correction(
    output_path: str,
    t1_nm: str,
    t2_nm: str,
    anat_brain_mask: str,
    scout: str,
    scout_debias_ab: str,
    func_brain_mask_ab: str,
    func_nm_ab: str,
    warpfield_afni_ab: str,
    anat_2_func_xfm_omni: str,
    fmap_skip: bool = False,
    skip_synth: bool = False,
) -> str:
    """Synth Distortion Correction.

    Parameters
    ----------
    output_path : str
        Output path.
    t1_nm : str
        Normalized, Debiased T1.
    t2_nm : str
        Normalized, Debiased T2.
    anat_brain_mask : str
        Anatomical brain mask.
    scout : str
        Reference functional to align/unwarp.
    scout_debias_ab : str
        Autoboxed, Debiased scout.
    func_brain_mask_ab : str
        Autoboxed, functional brain mask.
    func_nm_ab : str
        Autoboxed, normalized functional.
    warpfield_afni_ab : str
        Warpfield from topup, Autoboxed and in AFNI format.
    anat_2_func_xfm_omni : str
        Anatomical to functional transform in omni format.
    fmap_skip : bool
        skip distortion correction, returning previous transform
    skip_synth : bool
        skips synth distortion correction, returning topup transform

    Returns
    -------
    str
        functioanal to anatomical transform (Fsl format, fully concatenated).
    """
    # define paths
    func_2_anat_xfm_fsl = os.path.join(output_path, "func_2_anat_xfm.mat")
    func_2_anat_warp_afni = os.path.join(output_path, "SynthOutput", "func_to_anat_warp_afni.nii.gz")
    func_2_anat_warp_fsl = os.path.join(output_path, "func_to_anat_warp.nii.gz")
    afni_output = os.path.join(output_path, "SynthOutput", "Scout_undistorted_to_anat_afni.nii.gz")
    fsl_output = os.path.join(output_path, "SynthOutput", "Scout_undistorted_to_anat_fsl.nii.gz")
    func_2_anat_transform = os.path.join(output_path, "func_2_anat_transform.nii.gz")
    jacobian = os.path.join(output_path, "jacobian_Synth.nii.gz")
    jacobian_anat = os.path.join(output_path, "jacobian_anat.nii.gz")

    # if fmap skip enabled, just return the existing transform
    if fmap_skip:
        return func_2_anat_transform, jacobian_anat

    # if skip synth enabled, just return the existing transform
    if skip_synth:
        # convert omni affine to fsl format
        convert_affine_file(
            func_2_anat_xfm_fsl, anat_2_func_xfm_omni, "fsl", invert=True, target=scout_debias_ab, source=t1_nm
        )
        # resample the warp from Autobox dims to standard dims
        run_process(
            f"3dresample -prefix {func_2_anat_warp_afni} "
            f"-master {scout} -input {warpfield_afni_ab} -rmode Cu -overwrite"
        )
        # convert the warp to fsl format
        convert_warp(nib.load(func_2_anat_warp_afni), "afni", "fsl", invert=False, target=nib.load(scout)).to_filename(
            func_2_anat_warp_fsl
        )
    else:
        # run Synth unwarping
        results = synthunwarp(
            output_path=os.path.join(output_path, "SynthOutput"),
            t1_debias=t1_nm,
            t2_debias=t2_nm,
            anat_bet_mask=anat_brain_mask,
            anat_eye_mask=None,
            ref_epi=scout_debias_ab,
            ref_epi_bet_mask=func_brain_mask_ab,
            epi=func_nm_ab,
            bandwidth=4,
            resample_resolution=0.5,
            resolution_pyramid=[0.5],
            dilation_size=30,
            skip_synthtarget_affine=True,
            synthtarget_max_iterations=[100],
            synthtarget_err_tol=[5e-4],
            synthtarget_step_size=[1e-3],
            distortion_correction_smoothing="0x0",
            distortion_correction_shrink_factors="2x1",
            distortion_correction_step_size=[1.5, 1, 0.5, 0.1],
            noise_mask_iterations=1,
            initial_warp_field=warpfield_afni_ab,
            initial_affine=anat_2_func_xfm_omni,
        )

        # get the func to anat transforms
        func_2_anat_xfm = results["final_epi_to_anat_affine"]
        func_2_anat_warp = results["final_epi_to_synth_warp"]

        # convert the affine into fsl format
        convert_affine_file(func_2_anat_xfm_fsl, func_2_anat_xfm, "fsl", invert=False, target=t1_nm, source=scout)

        # resample the warp from Autobox dims to standard dims
        run_process(
            f"3dresample -prefix {func_2_anat_warp_afni} -master {scout} -input {func_2_anat_warp} -rmode Cu -overwrite"
        )
        # convert the warp to fsl format
        convert_warp(nib.load(func_2_anat_warp_afni), "afni", "fsl", invert=False, target=nib.load(scout)).to_filename(
            func_2_anat_warp_fsl
        )

    # sanity check: these two results should be the same
    run_process(
        f"3dNwarpApply "
        f"-nwarp {func_2_anat_xfm} {func_2_anat_warp_afni} "
        f"-prefix {afni_output} "
        f"-master {t2_nm} "
        f"-source {scout} "
        "-overwrite"
    )
    run_process(
        f"applywarp "
        f"-i {scout} "
        f"-r {t2_nm} "
        f"-o {fsl_output} "
        f"--postmat={func_2_anat_xfm_fsl} "
        f"-w {func_2_anat_warp_fsl} "
        "--interp=sinc -v"
    )

    # get the jacobian of the warp
    run_process(
        "convertwarp --rel --relout -v "
        f"--ref={scout} "
        f"--warp1={func_2_anat_warp_fsl} "
        f"--out=temp.nii.gz "
        f"--jacobian={jacobian}"
    )

    # transform jacobian to anatomical space
    run_process(
        "applywarp --rel --interp=spline "
        f"-i {jacobian} "
        f"-r {t2_nm} "
        f"--premat={func_2_anat_xfm_fsl} "
        f"-o {jacobian_anat}"
    )

    # combine transforms
    run_process(
        f"convertwarp --relout --rel "
        f"-r {t2_nm} "
        f"--warp1={func_2_anat_warp_fsl} "
        f"--postmat={func_2_anat_xfm_fsl} "
        f"-o {func_2_anat_transform}"
    )

    # return transforms
    return func_2_anat_transform, jacobian_anat


@create_output_path
def synth_setup(
    output_path: str,
    t1: str,
    t2: str,
    scout: str,
    func_brain_mask: str,
    func: str,
    warpfield: str,
    func_2_anat_xfm: str,
    fmap_skip: bool = False,
) -> Tuple[str]:
    """Setup stage for Synth distortion correction.

    Parameters
    ----------
    output_path : str
        Output path.
    t1 : str
        Debiased T1.
    t2 : str
        Debiased T2.
    scout : str
        Reference functional to align unwarp.
    func_brain_mask : str
        Brain mask of functional.
    func : str
        Full functional time series data.
    warpfield : str
        Distortion correction from topup.
    func_2_anat_xfm : str
        functional to anatomical transform (linear only).
    fmap_skip : bool
        skip distortion correction, returning previous transform

    Returns
    -------
    str
        Normalized, Debiased T1.
    str
        Normalized, Debiased T2.
    str
        Autoboxed, Debiased scout.
    str
        Autoboxed, functional brain mask.
    str
        Autoboxed, normalized functional.
    str
        Warpfield from topup, Autoboxed and in AFNI format.
    str
        Anatomical to functional transform in omni format.
    """
    # define paths
    t1_nm = PathManager(t1).repath(output_path).append_suffix("_nm").path
    t2_nm = PathManager(t2).repath(output_path).append_suffix("_nm").path
    scout_nm = PathManager(scout).repath(output_path).append_suffix("_nm").path
    func_nm = PathManager(func).repath(output_path).append_suffix("_nm").path
    scout_10000 = PathManager(scout_nm).repath(output_path).append_suffix("_10000").path
    scout_debias = PathManager(scout_nm).repath(output_path).append_suffix("_debias").path
    scout_debias_ab = PathManager(scout_debias).repath(output_path).append_suffix("_ab").path
    func_nm_ab = PathManager(func_nm).repath(output_path).append_suffix("_ab").path
    func_brain_mask_ab = PathManager(func_brain_mask).repath(output_path).append_suffix("_ab").path
    anat_2_func_xfm_omni = (
        PathManager(func_2_anat_xfm).repath(output_path).append_suffix("_omni_inv").get_path_and_prefix().path
        + ".affine"
    )
    warpfield_afni = PathManager(warpfield).repath(output_path).append_suffix("_afni").path
    warpfield_afni_ab = PathManager(warpfield_afni).repath(output_path).append_suffix("_ab").path

    # if fmap skip enabled, just return the existing transform
    if fmap_skip:
        return t1_nm, t2_nm, scout_debias_ab, func_brain_mask_ab, func_nm_ab, warpfield_afni_ab, anat_2_func_xfm_omni

    # normalize images
    logging.info("Normalizing images...")
    normalization(nib.load(t1)).to_filename(t1_nm)
    normalization(nib.load(t2)).to_filename(t2_nm)
    normalization(nib.load(scout)).to_filename(scout_nm)
    normalization(nib.load(func)).to_filename(func_nm)

    # debias the scout
    logging.info("Debiasing scout...")
    run_process(f"fslmaths {scout_nm} -mul 10000 {scout_10000}")
    N4BiasFieldCorrection(scout_debias, scout_10000, bspline_fit="[150,3,1x1x1,3]")
    normalization(nib.load(scout_debias)).to_filename(scout_debias)  # renormalize

    # autobox the debiased scout and functional
    autobox_size = 10
    run_process(f"3dAutobox -input {scout_debias} -prefix {scout_debias_ab} -overwrite -npad {autobox_size}")

    # do the same fpr functional and mask
    run_process(f"3dresample -prefix {func_nm_ab} -master {scout_debias_ab} -input {func_nm} -rmode Cu -overwrite")
    run_process(
        f"3dresample "
        f"-prefix {func_brain_mask_ab} "
        f"-master {scout_debias_ab} "
        f"-input {func_brain_mask} "
        "-rmode NN -overwrite"
    )

    # convert transforms to afni format
    convert_affine_file(anat_2_func_xfm_omni, func_2_anat_xfm, "omni", invert=True, target=t1, source=scout)
    convert_warp(nib.load(warpfield), "fsl", "afni", invert=False, target=nib.load(scout)).to_filename(warpfield_afni)

    # resample the warp so that it matches the autoboxed functional
    run_process(
        f"3dresample "
        f"-prefix {warpfield_afni_ab} "
        f"-master {scout_debias_ab} "
        f"-input {warpfield_afni} "
        "-rmode Cu -overwrite"
    )
    # add vector intent code to warp
    warp = nib.load(warpfield_afni_ab)
    warp.header.set_intent("vector")
    warp.to_filename(warpfield_afni_ab)

    # return preprocessed files for Synth
    return (
        t1_nm,
        t2_nm,
        scout_debias_ab,
        func_brain_mask_ab,
        func_nm_ab,
        warpfield_afni_ab,
        anat_2_func_xfm_omni,
    )


@create_output_path
def distortion_correction(
    output_path: str,
    scout_gdc: str,
    dwell_time: float = None,
    unwarp_direction: str = None,
    distortion_correction_method: str = None,
    sephasepos: str = None,
    sephaseneg: str = None,
    gdcoeffs: str = None,
    t2: str = None,
    t2_brain: str = None,
    fmap_skip: bool = False,
) -> Tuple[str, str]:
    """Distortion Correction with FieldMaps

    Parameters
    ----------
    output_path : str
        Output path.
    scout_gdc : str
        Scout image.
    dwell_time : float, optional
        Effective Echo Spacing, by default None
    unwarp_direction : str, optional
        Unwarping direction, by default None
    distortion_correction_method : str, optional
        Correction method (can be FIELDMAP, TOPUP or None), by default None
    sephasepos : str, optional
        Positive Spin Echo Image, by default None
    sephaseneg : str, optional
        Negative Spin Echo Image, by default None
    gdcoeffs : str, optional
        GDC coefficients, by default None
    t2 : str, optional
        Use T2 for Scout to anatomical alignment, by default None
    t2_brain : str, optional
        Use T2 for Scout to anatomical alignment (brain extracted), by default None
    fmap_skip : bool, optional
        Skip FieldMap processing and resue existing output

    Returns
    -------
    str
        Distortion Correction warp field
    str
        Scout to anatomical transform after distortion correction
    str
        Jacobian of the distortion correction
    str
        brain mask for scout image
    """

    # declare paths
    magnitude = os.path.join(output_path, "Magnitude")
    magnitude_brain = os.path.join(output_path, "Magnitude_brain")
    warpfield = os.path.join(output_path, "WarpField")
    jacobian = os.path.join(output_path, f"{JacobianOut}")

    # check if fmap_skip is set
    if not fmap_skip:
        # check distortion correction method
        if distortion_correction_method == "FIELDMAP":
            raise NotImplementedError()
        elif distortion_correction_method == "TOPUP":
            # set gdcoeff if None
            gdcoeffs = gdcoeffs if gdcoeffs else "NONE"

            # make working dir
            working_dir = os.path.join(output_path, "Fieldmap")
            os.makedirs(working_dir, exist_ok=True)

            # run topup
            run_process(
                f"{global_scripts}/TopupPreprocessingAll.sh "
                f"--workingdir={working_dir} "
                f"--phaseone={sephaseneg} "
                f"--phasetwo={sephasepos} "
                f"--scoutin={scout_gdc} "
                f"--echospacing={dwell_time} "
                f"--unwarpdir={unwarp_direction} "
                f"--ofmapmag={magnitude} "
                f"--ofmapmagbrain={magnitude_brain} "
                f"--owarp={warpfield} "
                f"--ojacobian={jacobian} "
                f"--gdcoeffs={gdcoeffs} "
                "--topupconfig=${HCPPIPEDIR_Config}/b02b0.cnf "
            )

            # add extensions to paths
            warpfield += ".nii.gz"
            jacobian += ".nii.gz"

            # apply distortion correction to scout
            scout_gdc_undistorted = PathManager(scout_gdc).repath(output_path).append_suffix("_undistorted").path
            run_process(
                f"applywarp "
                "--rel --interp=spline "
                f"-i {scout_gdc} "
                f"-r {scout_gdc} "
                f"-w {warpfield} "
                f"-o {scout_gdc_undistorted}"
            )

            # apply Jacobian correction to scout
            scout_gdc_undistorted_jacmod = PathManager(scout_gdc_undistorted).append_suffix("_jacmod").path
            run_process(
                f"fslmaths {scout_gdc_undistorted} " f"-mul {output_path}/{JacobianOut} {scout_gdc_undistorted_jacmod}"
            )

            # register undistorted scout image to T2w head
            # then generate a brain mask using the inverse transform
            # applied to T2w brain extraction
            scout_2_t2 = os.path.join(output_path, "Scout_2_T2w.nii.gz")
            scout_2_t2_xfm = os.path.join(output_path, "Scout_2_T2w.mat")
            run_process(
                "flirt -interp spline -dof 6 "
                f"-in {scout_gdc_undistorted_jacmod} "
                f"-ref {t2} "
                f"-omat {scout_2_t2_xfm} "
                f"-out {scout_2_t2} "
                "-searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo"
            )
            t2_2_scout_xfm = os.path.join(output_path, "Scout_2_T2w.mat")
            run_process(f"convert_xfm -omat {scout_2_t2_xfm} -inverse {t2_2_scout_xfm}")
            scout_brain_mask = os.path.join(output_path, "Scout_brain_mask.nii.gz")
            run_process(
                "applywarp --interp=nn "
                f"-i {t2_brain} "
                f"-r {scout_gdc_undistorted_jacmod} "
                f"-o {scout_brain_mask} "
                f"--premat={t2_2_scout_xfm}"
            )
            run_process(f"fslmaths {scout_brain_mask} -bin {scout_brain_mask}")
            scout_gdc_undistorted_jacmod_bet = PathManager(scout_gdc_undistorted_jacmod).append_suffix("_bet").path
            run_process(
                f"fslmaths {scout_gdc_undistorted_jacmod} "
                f"-mas {scout_brain_mask} "
                f"{scout_gdc_undistorted_jacmod_bet}"
            )

            # now reregister using the brain extracted version of the scout
            scout_undistorted_2_t2 = os.path.join(output_path, "Scout_undistorted_2_T2w.nii.gz")
            scout_undistorted_2_t2_xfm = os.path.join(output_path, "Scout_undistorted_2_T2w.mat")
            run_process(
                "flirt -interp spline -dof 6 "
                f"-in {scout_gdc_undistorted_jacmod_bet} "
                f"-ref {t2_brain} "
                f"-omat {scout_undistorted_2_t2_xfm} "
                f"-out {scout_undistorted_2_t2} "
                "-searchrx -30 30 -searchry -30 30 -searchrz -30 30 -cost mutualinfo"
            )
        else:
            raise NotImplementedError()
    else:  # reuse existing fieldmap outputs
        # add extensions to paths
        warpfield += ".nii.gz"
        jacobian += ".nii.gz"
        scout_undistorted_2_t2_xfm = os.path.join(output_path, "Scout_undistorted_2_T2w.mat")
        scout_brain_mask = os.path.join(output_path, "Scout_brain_mask.nii.gz")

    return warpfield, scout_undistorted_2_t2_xfm, jacobian, scout_brain_mask


@create_output_path
def motion_correction(
    output_path: str,
    func: str,
    scout: str,
    gdc_warp: str,
    fake_scout: bool = True,
) -> Tuple[str, str, str, str]:
    """Framewise Motion Correction

    Parameters
    ----------
    output_path : str
        Output path
    func : str
        Functional to motion correct.
    scout : str
        Scout image to align to.
    func_warp : str
        GDC warp.
    fake_scout : bool, optional
        If True, recreate a new scout image with motion corrected functional.

    Returns
    -------
    str
        motion corrected functional
    str
        movement regressor
    str
        motion matrix folder
    str
        final scout image to use for analysis
    """
    # setup paths
    func_mc = PathManager(func).append_suffix("_mc").repath(output_path).get_path_and_prefix().path
    movement_regressor = os.path.join(output_path, MovementRegressor)
    motion_matrix_folder = os.path.join(output_path, MotionMatrixFolder)
    scout_gdc = os.path.join(output_path, f"{ScoutName}_gdc.nii.gz")

    # create working dir
    os.makedirs(f"{output_path}/MotionCorrection_MCFLIRTbased", exist_ok=True)

    # run motion correction
    run_process(
        f"{pipeline_scripts}/MotionCorrection.sh "
        f"{output_path}/MotionCorrection_MCFLIRTbased "
        f"{func} "
        f"{scout} "
        f"{func_mc} "
        f"{movement_regressor} "
        f"{motion_matrix_folder} "
        f"{MotionMatrixPrefix} MCFLIRT"
    )

    # add extension to func_mc
    func_mc += ".nii.gz"

    # replace Scout with mean of fmri
    if fake_scout:
        gdc_invwarp = PathManager(gdc_warp).replace_suffix("_invwarp").path
        run_process(f"fslmaths {func_mc} -Tmean {scout_gdc}")
        run_process(f"invwarp -r {gdc_warp} -w {gdc_warp} -o {gdc_invwarp}")
    else:  # just copy over the scout to scout_gdc
        run_process(f"imcp {scout} {scout_gdc}")

    # return files and paths
    return func_mc, movement_regressor, motion_matrix_folder, scout_gdc


@create_output_path
def gradient_distortion_correction(
    output_path: str,
    in_file: str,
    coeffs_path: str,
) -> Tuple[str, str]:
    """Gradient distortion correction.

    Parameters
    ----------
    output_path : str
        Output directory.
    in_file : str
        File to gdc.
    coeffs_path : str
        Path to coefficients file.

    Returns
    -------
    out_file : str
        Output file.
    out_warp : str
        Output file for warp.
    """
    # make paths
    in_file_pm = PathManager(in_file)
    out_file = in_file_pm.append_suffix("_gdc").repath(output_path).path
    out_warp = in_file_pm.append_suffix("_gdc_warp").repath(output_path).path

    # skip gradient distortion correction if no coefficients file is provided
    if coeffs_path is None:
        logging.info("No gdc coefficients file provided.")
        logging.info("Not performing Gradient Distortion Correction.")
        # just make copies of files
        run_process(f"imcp {in_file} {out_file}")
        # load the in_file
        in_file_img = nib.load(in_file)
        # create a fake warp the same size as in_file
        data = np.zeros((*in_file_img.shape[:3], 3))
        # write warp to file
        nib.Nifti1Image(data, in_file_img.affine).to_filename(out_warp)
    else:  # else do gradient distortion correction
        # get in_file prefix
        in_suffix = in_file_pm.get_prefix().path

        # make working directory
        working_dir_pm = PathManager(output_path) / in_suffix + "_GradientDistortionUnwarp"
        working_dir_pm.mkdir(parents=True, exist_ok=True)
        working_dir = working_dir_pm.path

        run_process(
            f"{global_scripts}/GradientDistortionUnwarp.sh "
            f"--workingdir={working_dir} "
            f"--coeffs={coeffs_path} "
            f"--in={in_file} "
            f"--out={out_file} "
            f"--owarp={out_warp}"
        )

    # return output files
    return out_file, out_warp


@create_output_path
def make_scout(output_path: str, func: str, scout: str = None) -> str:
    """Create a scout image from a functional image.

    Parameters
    ----------
    output_path : str
        Output directory.
    func : str
        Functional image to create scout image from.
    scout : str
        Existing scout image to use.

    Returns
    -------
    str
        Scout image.
    """
    if scout is None:
        scout = (PathManager(output_path) / (OrigScoutName + ".nii.gz")).path
        run_process(f"fslroi {func} {scout} 0 1")
    else:
        scout_do = PathManager(scout).append_suffix("_deobliqued").repath(output_path).path
        scout_img = nib.load(scout)
        deoblique(scout_img).to_filename(scout_do)
        scout = scout_do
    return scout


class FMRIVolume(DCANPipeline):
    """FMRIVolume is a DCAN compatible Stage using the memori framework

    Parameters
    ----------
    session_spec : ParameterSettings
        The session spec to use for this pipeline
    """

    def __init__(self, session_spec: ParameterSettings):
        """Constructor for FMRI Volume Pipeline"""
        # setup logging
        setup_logging()

        # save session spec as config
        self.config = session_spec

        # get the output path from the session spec
        self.output_path = PathManager(session_spec.path)

        # define the stages for processing

        # deoblique
        self.deoblique_stage = Stage(
            deoblique_func,
            stage_outputs=["func"],
            aliases={"in_file": "func"},
        )

        # create scout
        self.scout_stage = Stage(
            make_scout,
            stage_outputs=["scout"],
            aliases={"in_file": "scout"},
        )

        # gradient distortion correction
        self.func_gdc_stage = Stage(
            gradient_distortion_correction,
            stage_outputs=["func_gdc", "func_gdc_warp"],
            stage_name="func_gdc",
            aliases={"func": "func_gdc", "gdc_warp": "func_gdc_warp"},
        )
        self.scout_gdc_stage = Stage(
            gradient_distortion_correction,
            stage_outputs=["scout_gdc", "scout_gdc_warp"],
            stage_name="scout_gdc",
            aliases={"scout": "scout_gdc"},
        )

        # motion correction
        self.motion_correction_stage = Stage(
            motion_correction,
            stage_outputs=["func_mc", "movement_regressor", "motion_matrix_folder", "scout_gdc"],
            aliases={"scout": "scout_gdc", "func": "func_mc"},
        )

        # distortion correction
        self.distortion_correction_stage = Stage(
            distortion_correction,
            stage_outputs=["dc_warp", "func_2_anat_xfm", "jacobian", "func_brain_mask"],
            aliases={"warpfield": "dc_warp"},
        )

        # Synth
        self.synth_setup_stage = Stage(
            synth_setup,
            stage_outputs=[
                "t1_nm",
                "t2_nm",
                "scout_debias_ab",
                "func_brain_mask_ab",
                "func_nm_ab",
                "warpfield_afni_ab",
                "anat_2_func_xfm_omni",
            ],
        )
        self.synth_stage = Stage(
            synth_distortion_correction,
            stage_outputs=["fmri2struct", "jacobian"],
        )

        # resampling
        self.resample_stage = Stage(
            one_step_resampling,
            stage_outputs=["func_atlas", "scout_atlas", "jacobian_out"],
            aliases={"jacobian": "jacobian_out"},
        )

        # intensity normalization
        self.intensity_norm_stage = Stage(
            intensity_normalization,
            stage_outputs=["func_atlas_norm", "scout_atlas_norm"],
        )

        # now construct the pipeline
        super().__init__(
            [
                ("start", self.deoblique_stage),
                (self.deoblique_stage, self.scout_stage),
                (self.deoblique_stage, self.func_gdc_stage),
                (self.scout_stage, self.scout_gdc_stage),
                ((self.func_gdc_stage, self.scout_gdc_stage), self.motion_correction_stage),
                (self.motion_correction_stage, self.distortion_correction_stage),
                ((self.motion_correction_stage, self.distortion_correction_stage), self.synth_setup_stage),
                ((self.motion_correction_stage, self.synth_setup_stage), self.synth_stage),
                (
                    (
                        self.func_gdc_stage,
                        self.scout_gdc_stage,
                        self.deoblique_stage,
                        self.scout_stage,
                        self.distortion_correction_stage,
                        self.synth_stage,
                    ),
                    self.resample_stage,
                ),
                (self.resample_stage, self.intensity_norm_stage),
            ]
        )

    def run(self, number_of_threads=1):
        """Run the functional volume processing pipeline.

        Parameters
        ==========
        number_of_threads : int
            Number of threads to use for the pipeline
        """
        # get the fmri runs from the session config
        fmri_runs = sorted(self.config.get_bids("func"), key=lambda x: (int("_ce-" in x), x))
        fmri_metadata = [meta for meta in self.config.get_bids("func_metadata")]

        # keep track of already run field maps
        field_maps_processed = []

        # change the working directory to the output path
        with working_directory(self.output_path):
            # loop over each run
            for fmri, meta in zip(fmri_runs, fmri_metadata):
                # set ts parameters
                fmriname = get_fmriname(fmri)
                seunwarpdir = ijk_to_xyz(meta["PhaseEncodingDirection"])
                sephasepos, sephaseneg = self._get_intended_sefmaps(fmri)
                ce = get_contrast_agent(fmri)

                # check if field maps have already been processed
                if sephasepos in field_maps_processed and sephaseneg in field_maps_processed:
                    fmap_skip = True
                else:  # add to list of already processed field maps
                    field_maps_processed.append(sephasepos)
                    field_maps_processed.append(sephaseneg)
                    fmap_skip = False

                # setup output paths
                hash_output = (PathManager(fmriname) / "hashes").path

                # update the stage inputs

                # deoblique
                self.deoblique_stage.hash_output = hash_output
                self.deoblique_stage.set_stage_arg("output_path", fmriname)
                self.deoblique_stage.set_stage_arg("func", fmri)

                # create scout
                self.scout_stage.hash_output = hash_output
                self.scout_stage.set_stage_arg("output_path", fmriname)

                # gradient distortion correction
                self.func_gdc_stage.hash_output = hash_output
                self.func_gdc_stage.set_stage_arg("output_path", fmriname)
                self.func_gdc_stage.set_stage_arg("coeffs_path", self.config.gdcoeffs)
                self.scout_gdc_stage.hash_output = hash_output
                self.scout_gdc_stage.set_stage_arg("output_path", fmriname)
                self.scout_gdc_stage.set_stage_arg("coeffs_path", self.config.gdcoeffs)

                # motion correction
                self.motion_correction_stage.hash_output = hash_output
                self.motion_correction_stage.set_stage_arg("output_path", fmriname)
                self.motion_correction_stage.set_stage_arg("fake_scout", True)

                # distortion correction
                fmap_prefix = (
                    PathManager(sephasepos).get_prefix().path + "_+_" + PathManager(sephaseneg).get_prefix().path
                )
                self.distortion_correction_stage.hash_output = os.path.join("FieldMaps", "hashes", fmriname)
                self.distortion_correction_stage.set_stage_arg("output_path", os.path.join("FieldMaps", fmap_prefix))
                self.distortion_correction_stage.set_stage_arg("distortion_correction_method", self.config.dcmethod)
                self.distortion_correction_stage.set_stage_arg("dwell_time", self.config.echospacing)
                self.distortion_correction_stage.set_stage_arg("sephasepos", sephasepos)
                self.distortion_correction_stage.set_stage_arg("sephaseneg", sephaseneg)
                self.distortion_correction_stage.set_stage_arg("unwarp_direction", seunwarpdir)
                self.distortion_correction_stage.set_stage_arg("gdcoeffs", self.config.gdcoeffs)
                self.distortion_correction_stage.set_stage_arg(
                    "t2", os.path.join(T1wFolder, T2wRestoreImage + ".nii.gz")
                )
                self.distortion_correction_stage.set_stage_arg(
                    "t2_brain", os.path.join(T1wFolder, T2wRestoreImageBrain + ".nii.gz")
                )
                self.distortion_correction_stage.set_stage_arg("fmap_skip", fmap_skip)

                # Synth setup
                self.synth_setup_stage.hash_output = os.path.join("FieldMaps", "hashes", fmriname)
                self.synth_setup_stage.set_stage_arg("output_path", os.path.join("FieldMaps", fmap_prefix))
                self.synth_setup_stage.set_stage_arg("t1", os.path.join(T1wFolder, T1wRestoreImage + ".nii.gz"))
                self.synth_setup_stage.set_stage_arg("t2", os.path.join(T1wFolder, T2wRestoreImage + ".nii.gz"))
                self.synth_setup_stage.set_stage_arg("fmap_skip", fmap_skip)

                # Synth
                self.synth_stage.hash_output = os.path.join("FieldMaps", "hashes", fmriname)
                self.synth_stage.set_stage_arg("output_path", os.path.join("FieldMaps", fmap_prefix))
                self.synth_stage.set_stage_arg("anat_brain_mask", os.path.join(T1wFolder, T1wBrainMask + ".nii.gz"))
                self.synth_stage.set_stage_arg("fmap_skip", fmap_skip)
                self.synth_stage.set_stage_arg("skip_synth", self.config.skip_synth)

                # resample
                fmrires = self.config.fmrires
                self.resample_stage.hash_output = hash_output
                self.resample_stage.set_stage_arg("output_path", fmriname)
                self.resample_stage.set_stage_arg("t1_atlas", os.path.join(f"{AtlasSpaceFolder}", f"{T1wAtlasName}"))
                self.resample_stage.set_stage_arg(
                    "struct2std", os.path.join(f"{AtlasSpaceFolder}", "xfms", f"{AtlasTransform}")
                )
                self.resample_stage.set_stage_arg(
                    "freesurfer_brain_mask", os.path.join(f"{AtlasSpaceFolder}", f"{FreeSurferBrainMask}")
                )
                self.resample_stage.set_stage_arg("bias_field", os.path.join(f"{AtlasSpaceFolder}", f"{BiasFieldMNI}"))
                self.resample_stage.set_stage_arg("fmriresout", fmrires)

                # intensity normalization
                self.intensity_norm_stage.hash_output = hash_output
                self.intensity_norm_stage.set_stage_arg("output_path", fmriname)
                self.intensity_norm_stage.set_stage_arg(
                    "bias_field", os.path.join(fmriname, f"{BiasFieldMNI}.{fmrires}")
                )
                self.intensity_norm_stage.set_stage_arg(
                    "brain_mask", os.path.join(fmriname, f"{FreeSurferBrainMask}.{fmrires}")
                )

                # run the pipeline
                super().run()

                # get results
                results = self.results

                # form path to results folder
                results_folder = os.path.join(f"{AtlasSpaceFolder}", f"{ResultsFolder}", f"{fmriname}")

                # copy results
                os.makedirs(f"{results_folder}", exist_ok=True)
                shutil.copy2(results["func_atlas_norm"], f"{results_folder}/{fmriname}.nii.gz")
                shutil.copy2(results["scout_atlas_norm"], f"{results_folder}/{fmriname}_SBRef.nii.gz")
                shutil.copy2(results["movement_regressor"] + ".txt", f"{results_folder}/{MovementRegressor}.txt")
                shutil.copy2(f"{fmriname}/{MovementRegressor}_dt.txt", f"{results_folder}/{MovementRegressor}_dt.txt")
                shutil.copy2(results["jacobian_out"], f"{results_folder}/{fmriname}_{JacobianOut}.nii.gz")

                # Add stuff for RMS
                shutil.copy2(f"{fmriname}/Movement_RelativeRMS.txt", f"{results_folder}/Movement_RelativeRMS.txt")
                shutil.copy2(f"{fmriname}/Movement_AbsoluteRMS.txt", f"{results_folder}/Movement_AbsoluteRMS.txt")
                shutil.copy2(
                    f"{fmriname}/Movement_RelativeRMS_mean.txt", f"{results_folder}/Movement_RelativeRMS_mean.txt"
                )
                shutil.copy2(
                    f"{fmriname}/Movement_AbsoluteRMS_mean.txt", f"{results_folder}/Movement_AbsoluteRMS_mean.txt"
                )

    def _get_intended_sefmaps(self, fmri: str) -> Tuple[str, str]:
        """Search the IntendedFor field from sidecar json to determine the appropriate field map pair

            This method searches the IntendedFor field in the sidecar json to obtain the field map
            data for a given fMRI run. If no such field is found, the default field map pair is
            the first spin echo pair.

        Parameters
        ----------
        fmri : str
            functional run to search for field map data

        Returns
        -------
        Tuple[str, str]
            field map pair to use for this run
        """
        intended_idx = {}
        for direction in ["positive", "negative"]:
            for idx, sefm in enumerate(self.config.get_bids("fmap_metadata", direction)):
                intended_targets = sefm.get("IntendedFor", [])
                if get_relpath(fmri) in " ".join(intended_targets):
                    intended_idx[direction] = idx
                    break
            else:
                if idx != 1:
                    print(
                        "WARNING: the intended %s spin echo for anatomical "
                        "distortion correction is not explicitly defined in "
                        "the sidecar json." % direction
                    )
                intended_idx[direction] = 0

        return self.config.get_bids("fmap", "positive", intended_idx["positive"]), self.config.get_bids(
            "fmap", "negative", intended_idx["negative"]
        )
