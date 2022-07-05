#!/bin/bash
# This script is basically just a wrapper, but created such that it could be modified later without impacting other scripts.
options=`getopt -o t:d:r:g:l:o:n:h -l target:,working-dir:,refdir:,ncores:,ref:,lab:,pexec:,output:,help -n 'run_JLF.sh' -- "$@"`
eval set -- "$options"
function display_help() {
    echo "Usage: `basename $0` "
    echo "	Required:"
    echo "	-t|--target <target brain>        subject brain"
    echo "	-d|--working-dir <directory>      working directory for intermediate outputs"
    echo "	-g|--ref <template brain>         1 per template brain, in order"
    echo "	-l|--labels <template seg>        1 per template segmentation, in order"
    echo "	-o|--output <output name>         output aseg"
    echo "	Optional:"
    echo "	-r|--refdir                       optional directory such that templates may be"
    echo "	                                  relative paths to here.  Must come before first -g/-l"
    echo "	-n|--ncores <cpus>                 number of cores for parallel execution"
    exit $1
}

echo "`basename $0` $options"
debug=0
# extract options and their arguments into variables.
while true ; do
	case "$1" in
		-t|--target)
			target="$2"
			shift 2
			;;
		-d|--working-dir)
			WD="$2"
			shift 2
			;;
		-r|--refdir)
			if ((${#references[@]})); then
				echo "Reference directory must be declared before references"
				exit 1
			fi
			refdir="$2"
			shift 2
			;;
		-g|--ref)
			references+=("${refdir}${refdir:+/}$2")
			shift 2
			;;
		-l|--lab)
			labels+=("${refdir}${refdir:+/}$2")
			shift 2
			;;
		-n|--ncores)
			if (($2 - 1)); then
				pexec="-c 2 -j $2"
			fi
			shift 2
			;;
		-o|--output)
			output="$2"
			shift 2
			;;
        -h|--help)
            display_help;;
        --) shift ; break ;;
        *) echo "Unexpected error parsing args!" ; display_help 1 ;;
    esac
done


if [ ! $(command -v ${ANTSPATH}${ANTSPATH:+/}antsJointLabelFusion.sh) ]; then
	echo "could not find ants scripts necessary for running joint label fusion in paths..."
	echo ${ANTSPATH}${ANTSPATH:+/}antsJointLabelFusion.sh
	exit 1
fi

if [ ! -z $ANTSPATH ]; then
	export ANTSPATH=${ANTSPATH%/}${ANTSPATH:+/} # ANTs script requires a trailing slash on this variable...
fi

if [ -z "$WD" ]; then
	WD="$PWD"
elif [ ! -e "$WD" ]; then
	mkdir -p "$WD"
fi

if [ ${#references[@]} -ne ${#labels[@]} ]; then
	echo "Reference/Label quantity mismatch in `basename $0`!  Cannot run segmentation"
	exit 1
fi
cd "$WD"


${FSLDIR}/bin/fslmaths $target -bin brainmask.nii.gz

# construct call to joint label fusion
cmd="${ANTSPATH}${ANTSPATH:+/}antsJointLabelFusion.sh -d 3 -o ants_multiatlas_ -t $target -x brainmask.nii.gz -y b ${pexec:-"-c 0"}"
for (( i=0; i<${#references[@]}; i++ )); do
	cmd=${cmd}" -g ${references[$i]} -l ${labels[$i]}"
done

# call process
echo $cmd | tee cmd.txt
$cmd

${FSLDIR}/bin/imcp "$WD"/ants_multiatlas_Labels $output
