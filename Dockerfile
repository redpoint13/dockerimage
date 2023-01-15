FROM nvidia/cuda:8.0-cudnn5-devel

#################################################################################################################
#           Global
#################################################################################################################
# apt-get to skip any interactive post-install configuration steps with DEBIAN_FRONTEND=noninteractive and apt-get install -y
# add base bashrc file
COPY bashrc /root/.bashrc

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ARG DEBIAN_FRONTEND=noninteractive


#################################################################################################################
#           Global Path Setting
#################################################################################################################

ENV CUDA_HOME /usr/local/cuda
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH}:${CUDA_HOME}/lib64
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH}:/usr/local/lib

ENV OPENCL_LIBRARIES /usr/local/cuda/lib64
ENV OPENCL_INCLUDE_DIR /usr/local/cuda/include

#################################################################################################################
#           TINI
#################################################################################################################

# Install tini
# ENV TINI_VERSION v0.19.0
# ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
# RUN chmod +x /tini

#################################################################################################################
#           SYSTEM
#################################################################################################################
# update: downloads the package lists from the repositories and "updates" them to get information on the newest versions of packages and their
# dependencies. It will do this for all repositories and PPAs.

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    bzip2 \
    wget \
    ca-certificates \
    libglib2.0-0 \
    libxext6 \
    libsm6 \
    libxrender1 \
    git \
    nano \
    mercurial \
    subversion \
    cmake \
    libssl-dev \
    libboost-dev \
    libboost-system-dev \
    libboost-filesystem-dev \
    gcc \
    g++

# Add OpenCL ICD files for LightGBM
RUN mkdir -p /etc/OpenCL/vendors && \
    echo "libnvidia-opencl.so.1" > /etc/OpenCL/vendors/nvidia.icd

#################################################################################################################
#           CONDA
#################################################################################################################

ARG CONDA_DIR=/opt/conda
# add to path
ENV PATH $CONDA_DIR/bin:$PATH

WORKDIR /app
COPY . /app

ARG CONDA_VERSION=py39_22.11.1-1
ARG CONDA_MD5=e685005710679914a909bfb9c52183b3ccc56ad7bb84acc861d596fcbe5d28bb
# get conda versions & md5 hashes from https://repo.anaconda.com/miniconda/
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-x86_64.sh -O miniconda.sh && \
    echo "${CONDA_MD5}  miniconda.sh" > miniconda.md5 && \
    if ! sha256sum --status -c miniconda.md5; then exit 1; fi && \
    mkdir -p /opt && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh miniconda.md5 && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> /root/.bashrc && \
    echo "conda activate base" >> /root/.bashrc && \
    find /opt/conda/ -follow -type f -name '*.a' -delete && \
    find /opt/conda/ -follow -type f -name '*.js.map' -delete

#################################################################################################################
#           mamba install
#################################################################################################################

ENV MAMBA_ROOT_PREFIX=/opt/conda/bin/

RUN conda update -n base -c defaults conda -y \
    && conda install -n base -c conda-forge mamba -y \
    # assure thatt .bashrc exists
    # && mv /app/bashrc /root/.bashrc \
    # fix tty error message
    && sed -i ~/.profile -e 's/mesg n || true/tty -s \&\& mesg n/g' \
    && conda init bash

# Override default shell and use bash https://kevalnagda.github.io/conda-docker-tutorial
SHELL ["conda", "run", "-n", "base", "/bin/bash", "-c"]

#################################################################################################################
#           install / update base environment
#################################################################################################################
RUN conda config --set always_yes yes && \
    ${MAMBA_ROOT_PREFIX}/mamba install -qy -n base -c conda-forge \
    black ipykernel ipython jupyter jupyter_contrib_nbextensions \
    jupyter_nbextensions_configurator jupyterlab jupytext matplotlib nb_conda_kernels \
    notebook scikit-learn tensorboard

#################################################################################################################
#           create ml-env
#################################################################################################################
ENV CONDA_DEFAULT_ENV=ml-env
ARG CONDA_DEFAULT_ENV=ml-env

RUN /opt/conda/bin/mamba env create -f environment.yml \
    # Make RUN commands use the new environment:
    && echo -e '#! /bin/bash\n\n/opt/conda/bin/conda activate "${CONDA_DEFAULT_ENV:-base}"' > ~/.bashrc
    # && conda remove -n ml-env cudf -y \
    # && mamba install -n ml-env -c rapidsai cudf

#################################################################################################################
#           LightGBM
#################################################################################################################

RUN cd /usr/local/src && mkdir lightgbm && cd lightgbm && \
    git clone --recursive --branch stable --depth 1 https://github.com/microsoft/LightGBM && \
    cd LightGBM && mkdir build && cd build && \
    cmake -DUSE_GPU=1 -DOpenCL_LIBRARY=/usr/local/cuda/lib64/libOpenCL.so -DOpenCL_INCLUDE_DIR=/usr/local/cuda/include/ .. && \
    make OPENCL_HEADERS=/usr/local/cuda-8.0/targets/x86_64-linux/include LIBOPENCL=/usr/local/cuda-8.0/targets/x86_64-linux/lib

ENV PATH /usr/local/src/lightgbm/LightGBM:${PATH}

RUN /bin/bash -c "pip uninstall lightgbm"  # remove old installation that have no GPU support

# RUN /bin/bash -c "/opt/conda/bin/mamba activate ml-env && cd /usr/local/src/lightgbm/LightGBM/python-package && python setup.py install --precompile --cuda && /opt/conda/bin/mamba deactivate"
RUN /bin/bash -c "cd /usr/local/src/lightgbm/LightGBM/python-package && python setup.py install --precompile --cuda"

#################################################################################################################
#           System CleanUp
#################################################################################################################
# apt-get autoremove: used to remove packages that were automatically installed to satisfy dependencies for some package and that are no more needed.
# apt-get clean: removes the aptitude cache in /var/cache/apt/archives. You'd be amazed how much is in there! the only drawback is that the packages
# have to be downloaded again if you reinstall them.

RUN apt-get autoremove -y && apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    /opt/conda/bin/conda clean -afy

#################################################################################################################
#           JUPYTER
#################################################################################################################

# password: keras
# password key: --NotebookApp.password='sha1:98b767162d34:8da1bc3c75a0f29145769edc977375a373407824'

# Add a notebook profile.
RUN mkdir -p -m 700 ~/.jupyter/ && \
    echo "--ServerApp.ip=0.0.0.0 --ServerApp.port=8888 --no-browser --notebook-dir="/app/" --ServerApp.token='abcdefg1234567890' --ServerApp.password='abcdefg1234567890'"  >> ~/.jupyter/jupyter_notebook_config.py

# RUN python -m ipykernel install --user --name ml-env --display-name ml-env

# IPython/Jupyter listens ports:
EXPOSE 8888
EXPOSE 8787
EXPOSE 8686
# MLFlow listening port:
EXPOSE 5000


# Make RUN commands use the new environment:
SHELL ["/opt/conda/bin/mamba", "run", "-n", "ml-env", "/bin/bash", "-c"]

# Activate Conda environment and check if it is working properly
RUN echo "Making sure pycaret is installed correctly..."
RUN python -c "import pycaret" && \
    python -c "import lightgbm"

WORKDIR /app
COPY *.sh /app
# Python program to run in the container
# COPY app.py .
# ENTRYPOINT [ "/bin/bash", "start-jupyter.sh" ]
# CMD /bin/bash -c "source activate base && jupyter notebook --allow-root --no-browser --NotebookApp.password='sha1:98b767162d34:8da1bc3c75a0f29145769edc977375a373407824' && source deactivate"
# CMD ["/bin/bash", "/root/.bashrc"]
ENTRYPOINT ["/bin/bash"]