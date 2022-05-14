FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive

# install dependencies
RUN apt-get update && apt-get install -y build-essential gpg wget m4 libglu1-mesa libncursesw5-dev libgdbm-dev \
    gfortran python python-pip python3 python3-dev python3-distutils python3-pip libz-dev libreadline-dev libbz2-dev \
    libopenblas-dev liblapack-dev libhdf5-dev libfftw3-dev git graphviz patchelf libssl-dev libsqlite3-dev uuid-dev \
    git-lfs curl bc dc libgl1-mesa-dev unzip libgomp1 libxmu6 libxt6 tcsh libffi-dev lzma-dev liblzma-dev tk-dev \
    libdb-dev && \
    # install cmake
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null && \
    echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ bionic main' | tee /etc/apt/sources.list.d/kitware.list >/dev/null && \
    apt-get update && rm /usr/share/keyrings/kitware-archive-keyring.gpg && apt-get install -y kitware-archive-keyring cmake && \
    # install python3.10
    cd /opt && curl -O https://www.python.org/ftp/python/3.10.4/Python-3.10.4.tgz && tar xvf Python-3.10.4.tgz && \
    rm Python-3.10.4.tgz && cd Python-3.10.4 && ./configure --enable-optimizations && make altinstall && \
    cd .. && rm -rf Python-3.10.4 

# set directory to /opt
WORKDIR /opt

# install ants
RUN mkdir -p /opt/ANTs && cd /opt/ANTs && \
    curl -O https://raw.githubusercontent.com/cookpa/antsInstallExample/master/installANTs.sh && \
    chmod +x /opt/ANTs/installANTs.sh && /opt/ANTs/installANTs.sh && rm installANTs.sh && \
    rm -rf /opt/ANTs/ANTs && rm -rf /opt/ANTs/build && rm -rf /opt/ANTs/install/lib && \
    mv /opt/ANTs/install/bin /opt/ANTs/bin && rm -rf /opt/ANTs/install
ENV ANTSPATH=/opt/ANTs/bin PATH=${PATH}:/opt/ANTs/bin

# install fsl
RUN curl -O https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py && \
    python2 fslinstaller.py -d /opt/fsl && rm fslinstaller.py
ENV FSLDIR=/opt/fsl PATH=${PATH}:/opt/fsl/bin

# install afni
RUN mkdir -p /opt/afni && cd /opt/afni && \
    curl -O https://afni.nimh.nih.gov/pub/dist/tgz/linux_ubuntu_16_64.tgz && \
    tar xvf linux_ubuntu_16_64.tgz && rm linux_ubuntu_16_64.tgz
ENV PATH=${PATH}:/opt/afni/linux_ubuntu_16_64

# install connectome workbench
RUN curl -O https://www.humanconnectome.org/storage/app/media/workbench/workbench-linux64-v1.5.0.zip && \
    unzip workbench-linux64-v1.5.0.zip && rm workbench-linux64-v1.5.0.zip
ENV PATH=${PATH}:/opt/workbench/bin_linux64

# install convert3d
RUN mkdir /opt/c3d && \
    curl -sSL --retry 5 https://sourceforge.net/projects/c3d/files/c3d/1.0.0/c3d-1.0.0-Linux-x86_64.tar.gz/download \
    | tar -xzC /opt/c3d --strip-components=1
ENV C3DPATH=/opt/c3d/bin PATH=/opt/c3d/bin:$PATH

#--------------------------
# Install FreeSurfer v5.3.0-HCP
#--------------------------
RUN curl -sSL --retry 5 https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/5.3.0-HCP/freesurfer-Linux-centos6_x86_64-stable-pub-v5.3.0-HCP.tar.gz \
    | tar xz -C /opt \
    --exclude='freesurfer/average/mult-comp-cor' \
    --exclude='freesurfer/lib/cuda' \
    --exclude='freesurfer/lib/qt' \
    --exclude='freesurfer/subjects/V1_average' \
    --exclude='freesurfer/subjects/bert' \
    --exclude='freesurfer/subjects/cvs_avg35' \
    --exclude='freesurfer/subjects/cvs_avg35_inMNI152' \
    --exclude='freesurfer/subjects/fsaverage3' \
    --exclude='freesurfer/subjects/fsaverage4' \
    --exclude='freesurfer/subjects/fsaverage5' \
    --exclude='freesurfer/subjects/fsaverage6' \
    --exclude='freesurfer/subjects/fsaverage_sym' \
    --exclude='freesurfer/trctrain' && \
    # patch mris_make_surfaces to use a non-specific version of netcdf
    patchelf --replace-needed libnetcdf.so.6 libnetcdf.so /opt/freesurfer/bin/mris_make_surfaces
# FreeSurfer uses matlab and tries to write the startup.m to the HOME dir.
# Therefore, HOME needs to be a writable dir.
ENV FREESURFER_HOME=/opt/freesurfer HOME=/opt SUBJECTS_DIR=/opt/freesurfer/subjects

# ---------------------
# Install MATLAB Compiler Runtime
#---------------------
RUN mkdir /opt/mcr /opt/mcr_download && cd /opt/mcr_download && \
    wget https://ssd.mathworks.com/supportfiles/downloads/R2017a/deployment_files/R2017a/installers/glnxa64/MCR_R2017a_glnxa64_installer.zip \
    && unzip MCR_R2017a_glnxa64_installer.zip \
    && ./install -agreeToLicense yes -mode silent -destinationFolder /opt/mcr \
    && rm -rf /opt/mcr_download

#---------------------
# Install MSM Binaries
#---------------------
RUN mkdir /opt/msm && \
    curl -ksSL --retry 5 https://www.doc.ic.ac.uk/~ecr05/MSM_HOCR_v2/MSM_HOCR_v2-download.tgz | tar zx -C /opt && \
    mv /opt/homes/ecr05/MSM_HOCR_v2/* /opt/msm/ && \
    rm -rf /opt/homes /opt/msm/MacOSX /opt/msm/Centos
ENV MSMBINDIR=/opt/msm/Ubuntu

#----------------------------
# Make perl version 5.20.3
#----------------------------
RUN curl -sSL --retry 5 http://www.cpan.org/src/5.0/perl-5.20.3.tar.gz | tar zx -C /opt && \
    cd /opt/perl-5.20.3 && ./Configure -des -Dprefix=/usr/local && make && make install && \
    rm -f /usr/bin/perl && ln -s /usr/local/bin/perl /usr/bin/perl && \
    cd / && rm -rf /opt/perl-5.20.3/

#------------------
# Make libnetcdf
#------------------
RUN curl -sSL --retry 5 https://github.com/Unidata/netcdf-c/archive/v4.6.1.tar.gz | tar zx -C /opt && \
    cd /opt/netcdf-c-4.6.1/ && \
    LDFLAGS=-L/usr/local/lib && CPPFLAGS=-I/usr/local/include && ./configure --disable-netcdf-4 --disable-dap --enable-shared --prefix=/usr/local && \
    make && make install && cd /usr/local/lib && \
    rm -rf /opt/netcdf-c-4.6.1/ && ldconfig

#------------------------------------------
# Set Connectome Workbench Binary Directory
#------------------------------------------
RUN ln -s /opt/workbench/bin_linux64/wb_command /opt/workbench/wb_command && \
    mkdir -p /root/.config/brainvis.wustl.edu /.config/brainvis.wustl.edu /opt/workbench/brainvis.wustl.edu && \
    printf "[General]\nloggingLevel=INFO\nvolumeAxesCrosshairs=false\nvolumeAxesLabels=false\n" > /opt/workbench/brainvis.wustl.edu/Caret7.conf && \
    printf "[General]\nloggingLevel=INFO\nvolumeAxesCrosshairs=false\nvolumeAxesLabels=false\n" > /root/.config/brainvis.wustl.edu/Caret7.conf && \
    printf "[General]\nloggingLevel=INFO\nvolumeAxesCrosshairs=false\nvolumeAxesLabels=false\n" > /.config/brainvis.wustl.edu/Caret7.conf && \
    chmod -R 775 /root/.config /.config
ENV WORKBENCHDIR=/opt/workbench \
    CARET7DIR=/opt/workbench/bin_linux64 \
    CARET7CONFDIR=/opt/workbench/brainvis.wustl.edu

# DCAN tools
RUN mkdir /opt/dcan-tools && cd /opt/dcan-tools && \
    pip2 install pyyaml numpy pillow && \
    # dcan executive summary
    git clone -b v2.2.10 --single-branch --depth 1 https://github.com/DCAN-Labs/ExecutiveSummary.git executivesummary && \
    gunzip /opt/dcan-tools/executivesummary/templates/parasagittal_Tx_169_template.scene.gz && \
    # dcan custom clean
    git clone -b v0.0.0 --single-branch --depth 1 https://github.com/DCAN-Labs/CustomClean.git customclean && \
    # dcan file mapper
    git clone -b v1.3.0 --single-branch --depth 1 https://github.com/DCAN-Labs/file-mapper.git filemapper && \
    printf "{\n  \"VERSION\": \"development\"\n}\n" > /opt/dcan-tools/version.json
# dcan bold processing
COPY ["dcan_bold_processing", "/opt/dcan-tools/dcan_bold_proc"]

#----------------------------------------------------------
# Install common dependencies and insert pipeline code
#----------------------------------------------------------
COPY ["app", "/app"]
RUN python3 -m pip install pyyaml numpy pillow pandas && python3 -m pip install -r "/app/requirements.txt"
COPY ["dcan-macaque-pipeline", "/opt/pipeline"]

# unless otherwise specified...
ENV OMP_NUM_THREADS=1 SCRATCHDIR=/tmp/scratch ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1 TMPDIR=/tmp

# make app directories
RUN mkdir /bids_input /output /atlases

# setup ENTRYPOINT
COPY ["./entrypoint.sh", "/entrypoint.sh"]
COPY ["./SetupEnv.sh", "/SetupEnv.sh"]
ENTRYPOINT ["/entrypoint.sh"]
WORKDIR /
CMD ["--help"]

RUN python3 -m pip install jupyter
