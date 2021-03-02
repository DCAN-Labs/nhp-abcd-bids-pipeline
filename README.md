# nhp-abcd-bids-pipeline
The repository contains the BIDs app for non-human primates (i.e., macaques),
used to run the dcan-macaque-pipeline.

This software takes a BIDS folder as input and determines parameters for the
DCAN Labs' modified HCP pipeline, calling upon the proper code to run the
subject(s).

## Using Docker
Before running, you will need to load the image onto your Docker service by
running the following command:
```{bash}
docker pull dcanlabs/nhp-abcd-bids-pipeline
```
If you receive a "no space left on device" error during this pull process, you
may need to clean up any old/dangling images and containers from the docker
registry, and possibly increase the amount of space allocated to Docker.

## Using Singularity
You can either pull the image from the Docker repository, or build it from the
repository for the image to be saved in the working directory.
```{bash}
singularity pull docker://dcanlabs/nhp-abcd-bids-pipeline

singularity build nhp-abcd-bids-pipeline.img docker://dcanlabs/nhp-abcd-bids-pipeline
```
These are essentially the same, but in the latter case you have control over the
name of the file.

## Usage:
Using the image will require BIDS formatted input data. Consult
http://bids.neuroimaging.io/ for more information and for tools which assist
with converting data into BIDS format. Our favorite is Dcm2Bids.

These are the minimal command invocations. Options are detailed in Options,
below.

To call using Docker:
```{bash}
docker run --rm \
    -v /path/to/bids_dataset:/bids_input:ro \
    -v /path/to/outputs:/output \
    -v /path/to/freesurfer/license:/license \
    dcanlabs/nhp-abcd-bids-pipeline /bids_input /output
    --freesurfer-license=/license [OPTIONS]
```
Notice that the FreeSurfer license is now mounted directly into the FreeSurfer
folder.

To call using Singularity:
```{bash}
env -i singularity run \
    -B /path/to/bids_dataset:/bids_input \
    -B /path/to/outputs:/output \
    -B /path/to/freesurfer/license.txt:/opt/freesurfer/license.txt \
    ./nhp-abcd-bids-pipeline.img /bids_input /output
--freesurfer-license=/opt/freesurfer/license.txt [OPTIONS]
```
Notice that the license is now mounted directly into the freesurfer folder, and
the call to singularity is prefaced by "env -i"

## Options
```{python}
usage: nhp-abcd-bids-pipeline [-h] [--version]
                              [--participant-label PARTICIPANT_LABEL [PARTICIPANT_LABEL ...]]
                              [--session-id SESSION_ID [SESSION_ID ...]]
                              [--all-sessions] [--ncpus NCPUS] [--stage STAGE]
                              [--bandstop LOWER UPPER]
                              [--max-cortical-thickness MAX_CORTICAL_THICKNESS]
                              [--registration-assist MOVING REFERENCE]
                              [--custom-clean JSON]
                              [--t1-brain-mask T1_BRAIN_MASK]
                              [--t2-brain-mask T2_BRAIN_MASK]
                              [--study-template HEAD BRAIN]
                              [--check-outputs-only] [--print-commands-only]
                              [--ignore-expected-outputs]
                              [--multi-template-dir MULTI_TEMPLATE_DIR]
                              [--hyper-normalization-method {ADULT_GM_IP,ROI_IPS,NONE}]
                              bids_dir output_dir

The Developmental Cognition and Neuroimaging (DCAN) lab Macaque fMRI
Pipeline [1].  This BIDS application initiates a functional MRI processing
pipeline built upon the Human Connectome Project's minimal processing
pipelines [2].  The application requires only a dataset conformed to the BIDS
specification, and little-to-no additional configuration on the part of the
user. BIDS format and applications are explained in detail at
http://bids.neuroimaging.io/

positional arguments:
  bids_dir              path to the input bids dataset root directory. Read
                        more about bids format in the link in the description.
                        It is recommended to use the dcan bids gui or dcm2bids
                        to convert from participant dicoms to bids.
  output_dir            path to the output directory for all intermediate and
                        output files from the pipeline, also path in which
                        logs are stored.

optional arguments:
  -h, --help            show this help message and exit
  --version, -v         show program's version number and exit
  --participant-label PARTICIPANT_LABEL [PARTICIPANT_LABEL ...]
                        optional list of participant ids to run. Default is
                        all ids found under the bids input directory. A
                        participant label does not include "sub-"
  --session-id SESSION_ID [SESSION_ID ...]
                        filter input dataset by session id. Default is all ids
                        found under the subject input directory(s). A session
                        id does not include "ses-"
  --all-sessions        collapses all sessions into one when running a
                        subject.
  --ncpus NCPUS         number of cores to use for concurrent processing and
                        algorithmic speedups. Warning: causes ANTs and
                        FreeSurfer to produce non-deterministic results.
  --stage STAGE         begin from a given stage, continuing through. Options:
                        PreFreeSurfer, FreeSurfer, PostFreeSurfer, FMRIVolume,
                        FMRISurface, DCANBOLDProcessing, ExecutiveSummary
  --bandstop LOWER UPPER
                        parameters for motion regressor band-stop filter. It
                        is recommended for the boundaries to match the inter-
                        quartile range for participant group respiratory rate
                        (bpm), or to match bids physio data directly [3].
                        These parameters are highly recommended for data
                        acquired with a frequency of approx. 1 Hz or more
                        (TR<=1.0). Default is no filter
  --max-cortical-thickness MAX_CORTICAL_THICKNESS
                        maximum cortical thickness to allow in FreeSurfer.
                        Default = 5 mm.
  --registration-assist MOVING REFERENCE
                        provide two task/run names, a moving and a reference
                        image to assist anatomical registration. Use case:
                        ferumoxytol enhanced fmri do not register consistently
                        to T1w images under typical FSL flirt metrics. Using a
                        bold image as a reference can help with this issue.
                        e.g. task-CErest01 task-rest01
  --t1-brain-mask T1_BRAIN_MASK
                        specify the path to the mask file. The file specified
                        will replace T1w_acpc_brain_mask.nii.gz. Default: mask 
                        generated by PreFreeSurfer.
  --t2-brain-mask T2_BRAIN_MASK
                        specify the path to the mask file. The file specified
                        will replace T2w_acpc_brain_mask.nii.gz. Default: mask 
                        generated by PreFreeSurfer.
  --study-template HEAD BRAIN
                        template head and brain images for masking nonlinear.
                        Effective to account for population head shape
                        differences in male/female and in separate age
                        categories, or for differences in anatomical field of
                        view. Default is to use the Yerkes19 Template.
  --multi-template-dir MULTI_TEMPLATE_DIR
                        directory for joint label fusion templates. It should
                        contain only folders which each contain a
                        "T1w_brain.nii.gz" and a "Segmentation.nii.gz". Each
                        subdirectory may have any name and any number of
                        additional files.
  --hyper-normalization-method {ADULT_GM_IP,ROI_IPS,NONE}
                        specify the intensity profiles to use for the hyper-
                        normalization step in FreeSurfer: ADULT_GM_IP adjusts
                        the entire base image such that the IP of GM in the
                        target roughly matches the IP of GM of the reference
                        (i.e., the adult freesurfer atlas). Then the WM is
                        shifted in the target image to match the histogram of
                        WM in the reference. ROI_IPS adjusts the intensity
                        profile of each ROI (GM, WM, CSF) separately and
                        reassembles the parts. NONE skips hyper-normalization
                        step. This allows the user to run PreFreeSurfer, apply
                        new, experimental hyper-normalization methods and then
                        restart at FreeSurfer. Default: ADULT_GM_IP.

special pipeline options:
  options which pertain to an alternative pipeline or an extra stage which is not
   inferred from the bids data.

  --custom-clean JSON   runs dcan cleaning script after the pipeline
                        completessuccessfully to delete pipeline outputs based
                        on the file structure specified in the custom-clean
                        json.

runtime options:
  special changes to runtime behaviors. Debugging features.

  --check-outputs-only  checks for the existence of outputs for each stage
                        then exit. Useful for debugging.
  --print-commands-only
                        print run commands for each stage to shell then exit.
  --ignore-expected-outputs
                        continues pipeline even if some expected outputs are
                        missing.

References
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
```

## Building the Docker Image
This repository contains the Dockerfile (and other files) needed to create the
docker image that will contain the BIDs app and the pipeline scripts. In order
to build the image, you will need to have already built the internal-tools
docker image.

Whenever you push changes to the dcanlabs/nhp-abcd-bids-pipeline repository on
GitHub, the pipeline build on DockerHub will be triggered automatically.

If you have made changes to dcanlabs/internal-tools and you want the
changes to be incorporated into this pipeline, you need to do that explicitly.

Tag the internal-tools release and let it build. Then, go to:
https://hub.docker.com/repository/docker/dcanlabs/external-software/nhp-abcd-bids-pipeline.
Click on the "Builds" tab, then on "Trigger" for the build.

