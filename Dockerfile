FROM dcanumn/internal-tools:v1.0.12

ARG DEBIAN_FRONTEND=noninteractive

#----------------------------------------------------------
# Install common dependencies
#----------------------------------------------------------
RUN apt-get update && apt-get install -yq --no-install-recommends \
        apt-utils \
        graphviz \
        python-pip \
        python3 \
        python3-dev \
        wget

RUN pip install pyyaml numpy pillow pandas
RUN apt-get update && apt-get install -yq --no-install-recommends python3-pip
RUN pip3 install setuptools wheel

COPY ["app", "/app"]
RUN python3 -m pip install -r "/app/requirements.txt"

# insert pipeline code
RUN git clone -b 'v0.1.1' --single-branch --depth 1 https://github.com/DCAN-Labs/dcan-macaque-pipeline.git /opt/pipeline

# unless otherwise specified...
ENV OMP_NUM_THREADS=1
ENV SCRATCHDIR=/tmp/scratch
ENV ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
ENV TMPDIR=/tmp

# make app directories
RUN mkdir /bids_input /output /atlases

# setup ENTRYPOINT
COPY ["./entrypoint.sh", "/entrypoint.sh"]
COPY ["./SetupEnv.sh", "/SetupEnv.sh"]
ENTRYPOINT ["/entrypoint.sh"]
WORKDIR /
CMD ["--help"]


