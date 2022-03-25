#!/usr/bin/env python3

__doc__ = \
"""The Developmental Cognition and Neuroimaging (DCAN) lab Macaque fMRI
Pipeline [1].  This BIDS application initiates a functional MRI processing
pipeline built upon the Human Connectome Project's minimal processing
pipelines [2].  The application requires only a dataset conformed to the BIDS
specification, and little-to-no additional configuration on the part of the
user. BIDS format and applications are explained in detail at
http://bids.neuroimaging.io/
"""
__references__ = \
"""References
----------
[1] dcan-pipelines (for now, please cite [3] in use of this software)
[2] Glasser, MF. et al. The minimal preprocessing pipelines for the Human
Connectome Project. Neuroimage. 2013 Oct 15;80:105-24.
10.1016/j.neuroimage.2013.04.127
[3] Fair, D. et al. Correction of respiratory artifacts in MRI head motion
estimates. Biorxiv. 2018 June 7. doi: https://doi.org/10.1101/337360
[4] Dale, A.M., Fischl, B., Sereno, M.I., 1999. Cortical surface-based
analysis. I. Segmentation and surface reconstruction. Neuroimage 9, 179-194.
[5] M. Jenkinson, C.F. Beckmann, T.E. Behrens, M.W. Woolrich, S.M. Smith. FSL.
NeuroImage, 62:782-90, 2012
[6] Avants, BB et al. The Insight ToolKit image registration framework. Front
Neuroinform. 2014 Apr 28;8:44. doi: 10.3389/fninf.2014.00044. eCollection 2014.
"""
__version__ = "0.2.7"

import argparse
import os

from helpers import read_bids_dataset, validate_license
from pipelines import (ParameterSettings, PreliminaryMasking, PreFreeSurfer,
                       FreeSurfer, PostFreeSurfer, FMRIVolume, FMRISurface,
                       DCANBOLDProcessing, ExecutiveSummary, CustomClean)

# debug
# import debug


def _cli():
    """
    command line interface
    :return:
    """
    parser = generate_parser()
    args = parser.parse_args()

    return interface(args.bids_dir,
                     args.output_dir,
                     args.aseg,
                     args.subject_list,
                     args.session_list,
                     args.collect,
                     args.ncpus,
                     args.stage,
                     args.bandstop,
                     args.max_cortical_thickness,
                     args.check_outputs_only,
                     args.t1_brain_mask,
                     args.t2_brain_mask,
                     args.study_template,
                     args.t1_reg_method,
                     args.cleaning_json,
                     args.print,
                     args.ignore_expected_outputs,
                     args.multi_template_dir,
                     args.norm_method,
                     args.norm_gm_std_dev_scale,
                     args.norm_wm_std_dev_scale,
                     args.norm_csf_std_dev_scale,
                     args.make_white_from_norm_t1,
                     args.single_pass_pial,
                     args.registration_assist,
                     args.freesurfer_license)


def generate_parser(parser=None):
    """
    Generates the command line parser for this program.
    :param parser: optional subparser for wrapping this program as a submodule.
    :return: ArgumentParser for this script/module
    """
    if not parser:
        parser = argparse.ArgumentParser(
            prog='nhp-abcd-bids-pipeline',
            description=__doc__,
            formatter_class=argparse.RawDescriptionHelpFormatter,
            epilog=__references__,
            usage='%(prog)s bids_dir output_dir --freesurfer-license=<LICENSE>'
                  ' [OPTIONS]'

        )
    parser.add_argument(
        'bids_dir',
        help='path to the input bids dataset root directory.  Read more '
             'about bids format in the link in the description.  It is '
             'recommended to use the dcan bids gui or dcm2bids to convert '
             'from participant dicoms to bids.'
    )
    parser.add_argument(
        'output_dir',
        help='path to the output directory for all intermediate and output '
             'files from the pipeline, also path in which logs are stored.'
    )
    parser.add_argument(
        '--version', '-v', action='version', version='%(prog)s ' + __version__
    )
    parser.add_argument(
        '--participant-label', dest='subject_list', metavar='PARTICIPANT_LABEL', nargs='+',
        help='optional list of participant ids to run. Default is all ids '
             'found under the bids input directory.  A participant label '
             'does not include "sub-"'
    )
    parser.add_argument(
        '--session-id', dest='session_list', metavar='SESSION_ID', nargs='+',
        help='filter input dataset by session id. Default is all ids '
             'found under the subject input directory(s).  A session id '
             'does not include "ses-"'
    )
    parser.add_argument(
        '--all-sessions', dest='collect', action='store_true',
        help='collapses all sessions into one when running a subject.'
    )
    parser.add_argument(
        '--ncpus', type=int, default=1,
        help='number of cores to use for concurrent processing and '
             'algorithmic speedups.  Warning: causes ANTs and FreeSurfer to '
             'produce non-deterministic results.'
    )
    parser.add_argument(
        '--freesurfer-license', dest='freesurfer_license',
        metavar='LICENSE_FILE',
        help='If using docker or singularity, you will need to acquire and '
             'provide your own FreeSurfer license. The license can be '
             'acquired by filling out this form: '
             'https://surfer.nmr.mgh.harvard.edu/registration.html'
    )
    parser.add_argument(
        '--stage',
        help='begin from a given stage, continuing through.  Options: '
             'PreFreeSurfer, FreeSurfer, PostFreeSurfer, FMRIVolume, '
             'FMRISurface, DCANBOLDProcessing, ExecutiveSummary'
    )
    parser.add_argument(
        '--bandstop', type=float, nargs=2, metavar=('LOWER', 'UPPER'),
        help='parameters for motion regressor band-stop filter. It is '
             'recommended for the boundaries to match the inter-quartile '
             'range for participant group respiratory rate (bpm), or to match '
             'bids physio data directly [3].  These parameters are highly '
             'recommended for data acquired with a frequency of approx. 1 Hz '
             'or more (TR<=1.0). Default is no filter'
    )
    parser.add_argument(
        '--max-cortical-thickness', type=int, default=5, dest='max_cortical_thickness',
        help='maximum cortical thickness to allow in FreeSurfer. Default = 5 mm.'
    )
    parser.add_argument(
        '--norm-gm-std-dev-scale', type=float, default=1, dest='norm_gm_std_dev_scale',
        help='normalized GM standard deviation scale factor (relative to normalization template). '
        'Modifies the standard deviation of intensity values for GM voxels in the '
        'hypernormalized T1w image used by FreeSurfer. Default = 1.'
    )
    parser.add_argument(
        '--norm-wm-std-dev-scale', type=float, default=1, dest='norm_wm_std_dev_scale',
        help='normalized WM standard deviation scale factor (relative to normalization template). '
        'Modifies the standard deviation of intensity values for WM voxels in the '
        'hypernormalized T1w image used by FreeSurfer. Default = 1.'
    )
    parser.add_argument(
        '--norm-csf-std-dev-scale', type=float, default=1, dest='norm_csf_std_dev_scale',
        help='normalized CSF standard deviation scale factor (relative to normalization template). '
        'Modifies the standard deviation of intensity values for CSF voxels in the '
        'hypernormalized T1w image used by FreeSurfer. Has no effect if used with ADULT_GM_IP '
        'hypernormalization. Default = 1.'
    )           
    parser.add_argument(
        '--make-white-from-norm-t1', dest='make_white_from_norm_t1', action='store_true',
        help='use normalized T1w volume (if it exists) as input to FreeSurfer\'s ' 
        'mris_make_surfaces when making white surfaces. Default = False. '
    )     
    parser.add_argument(
        '--single-pass-pial', dest='single_pass_pial', action='store_true',
        help='create pial surfaces in FreeSurfer with a single pass of mris_make_surfaces ' 
        'using hypernormalized T1w brain (if hypernormalization was not omitted); '
        'omits second pass of mris_make_surfaces (in which the surfaces generated in '
        'the first pass would be used as priors, and a non-hypernormalized T1w brain is used). '
        'Default = False.'
    )
    parser.add_argument(
        '--registration-assist', nargs=2, metavar=('MOVING', 'REFERENCE'),
        help='provide two task/run names, a moving and a reference image to '
             'assist anatomical registration. Use case: ferumoxytol enhanced '
             'fmri do not register consistently to T1w images under typical '
             'FSL flirt metrics. Using a bold image as a reference can '
             'help with this issue. e.g. task-CErest01 task-rest01'
    )
    extras = parser.add_argument_group(
        'special pipeline options',
        description='options which pertain to an alternative pipeline or an '
                    'extra stage which is not\n inferred from the bids data.'
    )
    extras.add_argument(
        '--custom-clean', metavar='JSON', dest='cleaning_json',
        help='runs dcan cleaning script after the pipeline completes'
             'successfully to delete pipeline outputs based on '
             'the file structure specified in the custom-clean json.'
    )
    parser.add_argument(
        '--aseg', type=str, dest='aseg',
        default=None,
        metavar='PATH',
        help='specify  aseg file to be used by FreeSurfer. '
             'Specified file must be named \"aseg_acpc.nii.gz\" '
             'Replaces the default aseg_acpc_nii.gz generated '
             'in PreFreeSurfer in subject\'s T1w directory. '
             'Default: aseg generated by PreFreeSurfer. '
    )    
    parser.add_argument(
        '--t1-brain-mask', type=str, dest='t1_brain_mask',
        default=None,
        metavar='PATH',
        help='specify the path to the mask file. The file specified will be used '
             'in place of the default mask generation in PreliminaryMasking '
             'and PreFreeSurfer stages'
             'Default: mask generated by PreliminaryMasking and PreFreeSurfer. '
    )
    parser.add_argument(
        '--t2-brain-mask', type=str, dest='t2_brain_mask',
        default=None,
        metavar='PATH',
        help='specify the path to the mask file. The file specified will be used '
             'in place of the default mask generation in PreliminaryMasking '
             'and PreFreeSurfer stages'
             'Default: mask generated by PreliminaryMasking and PreFreeSurfer. '
    )
    parser.add_argument(
        '--study-template', nargs=2, metavar=('HEAD', 'BRAIN'),
        help='template head and brain images for masking nonlinear. '
             'Effective to account for population head shape differences in '
             'male/female and in separate age categories, or for differences '
             'in anatomical field of view. Default is to use the Yerkes19 '
             'Template.'
    )
    parser.add_argument(
        '--t1-reg-method', dest='t1_reg_method',
        default='FLIRT_FNIRT',
        choices=['FLIRT_FNIRT', 'ANTS', 'ANTS_NO_INTERMEDIATE'],
        help='specify the method used to register subject T1w to '
             'reference during PreFreeSurfer. '
             'FLIRT_FNIRT performs FLIRT and FNIRT registration to reference. '
             'ANTS performs intermediate registration to study template, '
             'then registers to reference, using antsRegistrationSyN for both. '
             'ANTS_NO_INTERMEDIATE registers directly to reference '
             'with antsRegistrationSyN. '
             'Default: FLIRT_FNIRT.'
    )        
    runopts = parser.add_argument_group(
        'runtime options',
        description='special changes to runtime behaviors. Debugging features.'
    )
    runopts.add_argument(
        '--check-outputs-only', action='store_true',
        help='checks for the existence of outputs for each stage then exit. '
             'Useful for debugging.'
    )
    runopts.add_argument(
        '--print-commands-only', action='store_true', dest='print',
        help='print run commands for each stage to shell then exit.'
    )
    runopts.add_argument(
        '--ignore-expected-outputs', action='store_true',
        help='continues pipeline even if some expected outputs are missing.'
    )
    parser.add_argument(
        '--multi-template-dir',
        help='directory for joint label fusion templates. It should contain '
             'only folders which each contain a "T1w_brain.nii.gz" and a '
             '"Segmentation.nii.gz". Each subdirectory may have any name and '
             'any number of additional files.'
    )
    parser.add_argument(
        '--hyper-normalization-method', dest='norm_method',
        default='ADULT_GM_IP',
        choices=['ADULT_GM_IP', 'ROI_IPS', 'NONE'],
        help='specify the intensity profiles to use for the hyper-'
             'normalization step in FreeSurfer: '
             'ADULT_GM_IP adjusts the entire base image such that the IP '
             'of GM in the target roughly matches the IP of GM of the '
             'reference (i.e., the adult freesurfer atlas). Then the WM '
             'is shifted in the target image to match the histogram of WM '
             'in the reference. '
             'ROI_IPS adjusts the intensity profile of each ROI (GM, WM, '
             'CSF) separately and reassembles the parts. '
             'NONE skips hyper-normalization step. This allows the user '
             'to run PreFreeSurfer, apply new, experimental hyper-'
             'normalization methods and then restart at FreeSurfer. '
             'Default: ADULT_GM_IP.'
    )

    return parser


def interface(bids_dir, output_dir, aseg=None, subject_list=None, session_list=None,
              collect=False, ncpus=1, start_stage=None, bandstop_params=None,
              max_cortical_thickness=5, check_only=False, t1_brain_mask=None, t2_brain_mask=None,
              study_template=None, t1_reg_method='FLIRT_FNIRT', cleaning_json=None, print_commands=False,
              ignore_expected_outputs=False, multi_template_dir=None, norm_method=None,
              norm_gm_std_dev_scale=1, norm_wm_std_dev_scale=1, norm_csf_std_dev_scale=1,
              make_white_from_norm_t1=False, single_pass_pial=False, registration_assist=None,
              freesurfer_license=None):
    """
    main application interface
    :param bids_dir: input bids dataset see "helpers.read_bids_dataset" for
    more information.
    :param output_dir: output folder
    :param subject_list: subject and session list filtering.  See
    "helpers.read_bids_dataset" for more information.
    :param session_list: subject and session list filtering.
    :param aseg: path to aseg file to be used in FreeSurfer.
    :param collect: treats each subject as having only one session.
    :param ncpus: number of cores for parallelized processing.
    :param start_stage: start from a given stage.
    :param bandstop_params: tuple of lower and upper bound for stop-band filter
    :param max_cortical_thickness: maximum cortical thickness allowed in FreeSurfer.
    :param check_only: check expected outputs for each stage then terminate
    :param t1_brain_mask: specify mask to use instead of letting PreFreeSurfer create it.
    :param t2_brain_mask: specify mask to use instead of letting PreFreeSurfer create it.
    :param sshead: study specific template head for brain masking
    :param ssbrain: study specific template brain for brain masking
    :param t1_reg_method: PreFreeSurfer T1w registration method
    :param multi_template_dir: directory of joint label fusion atlases
    :param norm_method: which method will be used for hyper-normalization step.
    :param norm_gm_std_dev_scale: scale factor for normalized GM standard deviation (relative to normalization template)
    :param norm_wm_std_dev_scale: scale factor for normalized WM standard deviation (relative to normalization template)
    :param norm_csf_std_dev_scale: scale factor for normalized CSF standard deviation (relative to normalization template)
    :param make_white_from_norm_t1: generate white surfaces in FreeSurfer from normalized T1w
    :param single_pass_pial: generate pial surfaces in FreeSurfer with a single pass of mris_make_surfaces instead of default two-pass method (using surfaces generated in first pass create priors)
    :return:
    """

    if not check_only or not print_commands:
        validate_license(freesurfer_license)

    # read from bids dataset
    assert os.path.isdir(bids_dir), bids_dir + ' is not a directory!'
    if not os.path.isdir(output_dir):
        os.makedirs(output_dir)
    session_generator = read_bids_dataset(
        bids_dir, subject_list=subject_list, session_list=session_list
    )

    # run each session in serial
    for session in session_generator:
        # setup session configuration
        out_dir = os.path.join(
            output_dir,
            'sub-%s' % session['subject'],
            'ses-%s' % session['session']
        )
        session_spec = ParameterSettings(session, out_dir)
        if aseg is not None:
            session_spec.set_aseg(aseg)
            session_spec.set_asegdir(os.path.dirname(aseg))
        if norm_method is None:
            # Use default: ADULT_GM_IP.
            session_spec.set_hypernormalization_method("ADULT_GM_IP")
        else:
            session_spec.set_hypernormalization_method(norm_method)
        if norm_gm_std_dev_scale is not 1:
            session_spec.set_norm_gm_std_dev_scale(norm_gm_std_dev_scale)
        if norm_wm_std_dev_scale is not 1:
            session_spec.set_norm_wm_std_dev_scale(norm_wm_std_dev_scale)
        if norm_csf_std_dev_scale is not 1:
            session_spec.set_norm_csf_std_dev_scale(norm_csf_std_dev_scale)
        if make_white_from_norm_t1 is not False:
            session_spec.set_make_white_from_norm_t1(make_white_from_norm_t1)
        if single_pass_pial is not False:
            session_spec.set_single_pass_pial(single_pass_pial)
        if t1_reg_method is None:
            # Use default: FLIRT_FNIRT
            session_spec.set_t1_reg_method("FLIRT_FNIRT")
        else:
            session_spec.set_t1_reg_method(t1_reg_method)
        if t1_brain_mask is not None:
            session_spec.set_t1_brain_mask(t1_brain_mask)
        if t2_brain_mask is not None:
            session_spec.set_t2_brain_mask(t2_brain_mask)
        if study_template is not None:
            session_spec.set_study_templates(*study_template)
        if multi_template_dir is not None:
            session_spec.set_templates_dir(multi_template_dir)
        if max_cortical_thickness is not 5:
            session_spec.set_max_cortical_thickness(max_cortical_thickness)

        # create pipelines
        mask = PreliminaryMasking(session_spec)
        pre = PreFreeSurfer(session_spec)
        free = FreeSurfer(session_spec)
        post = PostFreeSurfer(session_spec)
        vol = FMRIVolume(session_spec)
        surf = FMRISurface(session_spec)
        boldproc = DCANBOLDProcessing(session_spec)
        execsum = ExecutiveSummary(session_spec)

        # set user parameters
        if registration_assist:
            vol.set_registration_assist(*registration_assist)

        if bandstop_params is not None:
            boldproc.set_bandstop_filter(*bandstop_params)

        # determine pipeline order
        order = [mask, pre, free, post, vol, surf, boldproc, execsum]

        if cleaning_json:
            cclean = CustomClean(session_spec, cleaning_json)
            order.append(cclean)

        if start_stage:
            names = [x.__class__.__name__ for x in order]
            assert start_stage in names, \
                '"%s" is unknown, check class name and case for given stage' \
                % start_stage
            order = order[names.index(start_stage):]

        # special runtime options
        if check_only:
            for stage in order:
                print('checking outputs for %s' % stage.__class__.__name__)
                try:
                    stage.check_expected_outputs()
                except AssertionError:
                    pass
            return
        if print_commands:
            for stage in order:
                stage.deactivate_runtime_calls()
                stage.deactivate_check_expected_outputs()
                stage.deactivate_remove_expected_outputs()
        if ignore_expected_outputs:
            print('ignoring checks for expected outputs.')
            for stage in order:
                stage.activate_ignore_expected_outputs()

        # run pipelines
        for stage in order:
            print('nhp-abcd-bids-pipeline v%s' % __version__)
            print('running %s' % stage.__class__.__name__)
            print(stage)
            stage.run(ncpus)


if __name__ == '__main__':
    _cli()
