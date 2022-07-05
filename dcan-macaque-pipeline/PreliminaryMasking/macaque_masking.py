#!/usr/bin/env python3

import argparse
import os
import subprocess


def _cli():

    parser = generate_parser()

    args = parser.parse_args()

    return interface(args.path, args.t1, args.t2, args.t1brainmask,
                     args.t2brainmask, args.func, args.fmapmag,
                     args.sshead, args.ssbrain, args.verbose)


def generate_parser(parser=None):
    if not parser:
        parser = argparse.ArgumentParser(
            description="""preparatory masking pipeline for macaques.  
            Creates masks which supplement HCP processes which otherwise have 
            trouble with different macaque heads and field of views"""
        )
    parser.add_argument(
        '--path', type=str,
        help='path to study folder for subject'
    )
    parser.add_argument(
        '--t1', nargs='+',
        help='space delimited input t1w image paths'
    )
    parser.add_argument(
        '--t2', nargs='+',
        help='space delimited input t2w image paths'
    )
    parser.add_argument(
        '--func', nargs='+',
        help='space delimited input functional data'
    )
    parser.add_argument(
        '--fmapmag',
        help='diffusion field map path if it is used.'
    )
    parser.add_argument(
        '--sshead',
        help='study atlas head for ants masking, should generally match age '
             'and gender for best results'
    )
    parser.add_argument(
        '--ssbrain',
        help='study atlas brain for ants masking, should generally match age '
             'and gender for best results'
    )
    parser.add_argument(
        '--t1brainmask',
        help='optional user-specified subject T1w mask, to be used instead '
             'of the default ANTs-based masking performed by this script '
    )
    parser.add_argument(
        '--t2brainmask',
        help='optional user-specified subject T2w mask, to be used instead '
             'of the default ANTs-based masking performed by this script '
    )
    parser.add_argument(
        '--verbose', action='store_true',
        help='print commands prior to execution'
    )

    return parser


def interface(path, t1w_images, t2w_images, t1_brain_mask, t2_brain_mask,
              functional_images, dfm_image, study_atlas_head,
              study_atlas_brain, verbose):
    cmdlist = []

    wd = os.path.join(path, 'masks')
    # jlf_council = os.walk(multi_atlas_dir)

    # define intermediates and outputs for formatting
    kwargs = {
        'FSLDIR': os.environ['FSLDIR'],
        'ANTSPATH': os.environ['ANTSPATH'],
        't1w': os.path.join(wd, 'T1w_average.nii.gz'),
        't2w': os.path.join(wd, 'T2w_average.nii.gz'),
        'user_t1w_mask': t1_brain_mask,
        'user_t2w_mask': t2_brain_mask,
        'atlas_head': study_atlas_head,
        'atlas_brain': study_atlas_brain,
        't1w2atl': os.path.join(wd, 't1w2atl.mat'),
        'atl2t1w': os.path.join(wd, 'atl2t1w.mat'),
        't1w_in_atl': os.path.join(wd, 'T1w_average_rot2atl.nii.gz'),
        'atlas_mask': os.path.join(wd, 'study_atlas_mask.nii.gz'),
        'warp_out': os.path.join(wd, 'atl2T1'),
        'warp_files': ' '.join((
            os.path.join(wd, 'atl2T1Warp.nii.gz'),
            os.path.join(wd, 'atl2T1Affine.txt')
        )),
        'warp_mask': os.path.join(wd, 'warped_mask.nii.gz'),
        'brain_mask': os.path.join(wd, 'brain_mask.nii.gz'),
        't1w_brain': os.path.join(wd, 'T1w_brain.nii.gz'),
        't1w2t2w': os.path.join(wd, 't1w2t2w.mat'),
        't2w_brain': os.path.join(wd, 'T2w_brain.nii.gz'),
        't2w_brain_mask': os.path.join(wd, 'T2w_brain_mask.nii.gz'),
        'dfm_image': dfm_image,
        'dfm_image_mask': os.path.join(wd, 'dfm_mask.nii.gz'),
        'dfm_image_brain': os.path.join(wd, 'dfm_brain.nii.gz'),
        'n4_bias_field': os.path.join(wd, 'N4BiasField.nii.gz')
    }

    if not os.path.exists(wd):
        os.makedirs(wd)

    # average images
    for txw_images, avg in ((t1w_images, kwargs['t1w']), (t2w_images, kwargs[
            't2w'])):
        if len(txw_images) > 1:
            avg_cmd = '{}/better_flirt_average {} {} {}'.format(
                os.environ['HCPPIPEDIR_Global'], len(txw_images),
                ' '.join(txw_images), avg
            )
        else:
            avg_cmd = 'cp {} {}'.format(txw_images[0], avg)
        cmdlist.append(avg_cmd)

    # @TODO insert workaround for bad OHSU t2w protocol.
    # @TODO initial N4BiasCorrection is necessary?

    if t1_brain_mask and t1_brain_mask.upper() != 'NONE':
        # if a user-specified mask exists, skip ants mask generation
        # and apply the specified mask instead
        copy_t1w_mask = 'cp {user_t1w_mask} {brain_mask}'.format(
            **kwargs)
        user_mask_t1w = 'fslmaths {t1w} -mas {brain_mask} {t1w_brain}'.format(
            **kwargs)
        cmdlist += [copy_t1w_mask, user_mask_t1w]
    else:
        # mask images using ants
        bias_field_correct_t1w = '{ANTSPATH}/N4BiasFieldCorrection -d 3 -i {t1w} -o [{t1w},{n4_bias_field}]'.format(
            **kwargs)

        rigid_align = '{FSLDIR}/bin/flirt -v -dof 6 -in {t1w} -ref {atlas_head} ' \
                      '-out {t1w_in_atl} -omat {t1w2atl} -interp spline ' \
                      '-searchrx -30 30 -searchry -30 30 -searchrz -30 ' \
                      '30'.format(**kwargs)
        create_mask = '{FSLDIR}/bin/fslmaths {atlas_brain} -bin {' \
                      'atlas_mask}'.format(**kwargs)
        ants_warp = '{ANTSPATH}/ANTS 3 -m  CC[{t1w_in_atl},{atlas_head},1,5] ' \
                    '-t SyN[0.25] -r Gauss[3,0] -o {warp_out} -i 60x50x20 ' \
                    '--use-Histogram-Matching --number-of-affine-iterations ' \
                    '10000x10000x10000x10000x10000 --MI-option ' \
                    '32x16000'.format(**kwargs)
        apply_ants_warp = '{ANTSPATH}/antsApplyTransforms -d 3 -i {atlas_mask} ' \
                          '-t {warp_files} -r {t1w_in_atl} -o ' \
                          '{warp_mask}'.format(**kwargs)
        inverse_mat = '{FSLDIR}/bin/convert_xfm -omat {atl2t1w} -inverse {' \
                      't1w2atl}'.format(**kwargs)
        rigid_align_mask = '{FSLDIR}/bin/flirt -interp nearestneighbour -in {' \
                           'warp_mask} -ref {t1w} -o {brain_mask} -applyxfm ' \
                           '-init {atl2t1w}'.format(**kwargs)
        mask_t1w = 'fslmaths {t1w} -mas {brain_mask} {t1w_brain}'.format(**kwargs)
        cmdlist += [bias_field_correct_t1w, rigid_align, create_mask, ants_warp, apply_ants_warp,
                    inverse_mat, rigid_align_mask, mask_t1w]
    if t2_brain_mask and t2_brain_mask.upper() != 'NONE':
        # if a user-specified mask exists, skip ants mask generation
        # and apply the specified mask instead
        copy_t2w_mask = 'cp {user_t2w_mask} {t2w_brain_mask}'.format(
            **kwargs)
        user_mask_t2w = 'fslmaths {t2w} -mas {t2w_brain_mask} {t2w_brain}'.format(
            **kwargs)
        cmdlist += [copy_t2w_mask, user_mask_t2w]
    else:
        bias_field_correct_t2w = '{ANTSPATH}/N4BiasFieldCorrection -d 3 -i {t2w} -o [{t2w},{n4_bias_field}]'.format(
            **kwargs)
        t1w2t2w_rigid = 'flirt -dof 6 -cost mutualinfo -in {t1w} -ref {t2w} ' \
                        '-omat {t1w2t2w}'.format(**kwargs)
        t1w2t2w_mask = 'flirt -in {brain_mask} -interp nearestneighbour -ref {' \
                       't2w} -o {t2w_brain_mask} -applyxfm -init {' \
                       't1w2t2w}'.format(**kwargs)
        mask_t2w = 'fslmaths {t2w} -mas {t2w_brain_mask} ' \
                   '{t2w_brain}'.format(**kwargs)
        cmdlist += [bias_field_correct_t2w, t1w2t2w_rigid,
                    t1w2t2w_mask, mask_t2w]

    # create fieldmap mask and bet mask if applicable
    if dfm_image and dfm_image.upper() != 'NONE':
        rigid_dfm = 'flirt -dof 6 -in {t2w} -ref {dfm_image} -omat {' \
                    't2w2dfm}'.format(**kwargs)
        align_mask = 'flirt -interp nearestneighbour -in {t2w_brain_mask} ' \
                     '-ref {dfm_image} -applyxfm -init {t2w2dfm} -o ' \
                     '{dfm_brain_mask}'.format(**kwargs)
        apply_mask = 'fslmaths {dfm_image} -mas {dfm_brain_mask} {' \
                     'dfm_brain}'.format(**kwargs)
        cmdlist += [rigid_dfm, align_mask, apply_mask]
        for func in functional_images:
            # apply bet and create brain mask for resting state data
            func_bet = os.path.join(wd, os.path.basename(func))[:-7] + \
                '_bet.nii.gz'
            func_mask = func_bet[:-7] + '_mask.nii.gz'
            bet = '{FSLDIR}/bin/bet {func} {func_bet} -m -f 0.25 -g ' \
                  '0.3'.format(**kwargs, func=func, func_bet=func_bet,
                               func_mask=func_mask)
            cmdlist += [bet]

    # copy brains into prefreesurfer directory
    prefreedir = os.path.join(wd, '..', 'T1w')
    prefreet2dir = os.path.join(wd, '..', 'T2w')
    if not os.path.exists(prefreedir):
        os.makedirs(prefreedir)
    if not os.path.exists(prefreet2dir):
        os.makedirs(prefreet2dir)
    copy_t1w_brain = 'cp {t1w_brain} '.format(**kwargs) + os.path.join(
        prefreedir, os.path.basename(kwargs['t1w_brain'])
    )
    copy_t2w_brain = 'cp {t2w_brain} '.format(**kwargs) + os.path.join(
        prefreet2dir, os.path.basename(kwargs['t2w_brain'])
    )
    cmdlist += [copy_t1w_brain, copy_t2w_brain]

    for cmd in cmdlist:
        if verbose:
            print(cmd)
        status = subprocess.call(cmd.split(), env=os.environ, cwd=wd)
        if status:
            print('command finished with exit code %s, cmd=%s' % (status, cmd))


if __name__ == '__main__':
    _cli()
