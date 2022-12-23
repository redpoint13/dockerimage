# FROM nvidia/cuda:8.0-cudnn5-devel
FROM nvidia/cuda:11.3.0-cudnn8-devel-ubuntu20.04

#################################################################################################################
#           Global
#################################################################################################################
# apt-get to skip any interactive post-install configuration steps with DEBIAN_FRONTEND=noninteractive and apt-get install -y

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ARG DEBIAN_FRONTEND=noninteractive

#################################################################################################################
#           Global Path Setting
#################################################################################################################

ENV CUDA_HOME /usr/local/cuda
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH}:${CUDA_HOME}/lib64
# ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH}:/usr/local/lib

ENV OPENCL_LIBRARIES /usr/local/cuda/lib64
ENV OPENCL_INCLUDE_DIR /usr/local/cuda/include

#################################################################################################################
#           TINI
#################################################################################################################

# Install tini
ENV TINI_VERSION v0.14.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

#################################################################################################################
#           SYSTEM
#################################################################################################################
# update: downloads the package lists from the repositories and "updates" them to get information on the newest versions of packages and their
# dependencies. It will do this for all repositories and PPAs.

RUN apt-get update && \
apt-get install -y --no-install-recommends \
build-essential \
curl \
wget \
bzip2 \
ca-certificates \
libglib2.0-0 \
libxext6 \
libsm6 \
libxrender1 \
git \
vim \
nano \
mercurial \
subversion \
cmake \
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

# ARG CONDA_DIR=/opt/conda
# # add to path
# ENV PATH $CONDA_DIR/bin:$PATH

# # Install miniforge
# RUN echo "export PATH=$CONDA_DIR/bin:"'$PATH' > /etc/profile.d/conda.sh && \
#     curl -sL https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -o ~/miniforge.sh && \
#     /bin/bash ~/miniforge.sh -b -p $CONDA_DIR && \
#     rm ~/miniforge.sh

# RUN conda config --set always_yes yes --set changeps1 no && \
#     conda create -y -q -n py3 numpy scipy scikit-learn jupyter jupyterlab notebook ipython pandas matplotlib

# prepend conda environment to path
ENV CONDA_DIR="/opt/conda/bin"
ENV PATH "${CONDA_DIR}/envs/${conda_env}/bin:${PATH}"
# RUN echo "export PATH=$CONDA_DIR/bin:"'$PATH' > /etc/profile.d/conda.sh

# Leave these args here to better use the Docker build cache: conda in rapids base image
ARG CONDA_VERSION=py38_4.12.0
ARG CONDA_MD5=3190da6626f86eee8abf1b2fd7a5af492994eb2667357ee4243975cdbb175d7a
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-x86_64.sh -O miniconda.sh && \
    echo "${CONDA_MD5}  miniconda.sh" > miniconda.md5 && \
    if ! sha256sum --status -c miniconda.md5; then exit 1; fi && \
    mkdir -p /opt && \
    sh miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh miniconda.md5 && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "/opt/conda/bin/conda activate base" >> ~/.bashrc && \
    find /opt/conda/ -follow -type f -name '*.a' -delete && \
    find /opt/conda/ -follow -type f -name '*.js.map' -delete
    # /opt/conda/bin/conda clean -afy

# #############################################################################################################
# ML-ENV Setup
# #############################################################################################################
RUN /opt/conda/bin/conda update -qy -n base conda && \
    /opt/conda/bin/conda install -qy -n base -c conda-forge mamba && \
    /opt/conda/bin/mamba update --all -y && \
    /opt/conda/bin/mamba init bash

RUN /opt/conda/bin/mamba install -y -n base -c conda-forge jupyterlab nb_conda_kernels ipykernel tensorboard jupytext jupyter_nbextensions_configurator jupyter_contrib_nbextensions

WORKDIR /app
COPY . /app

# Create Conda environment from the YAML file
RUN /opt/conda/bin/mamba env create -f environment.yml

# Make RUN commands use the new environment:
ENV CONDA_DEFAULT_ENV=ml-env
ARG conda_env=ml-env
RUN /opt/conda/bin/mamba init bash && echo '/opt/conda/bin/mamba activate "${CONDA_DEFAULT_ENV:-base}"' >>  ~/.bashrc

RUN /opt/conda/envs/ml-env/bin/python -m ipykernel install --user --name ml-env --display-name ml-env

#################################################################################################################
#           LightGBM
#################################################################################################################

RUN cd /usr/local/src && mkdir lightgbm && cd lightgbm && \
    git clone --recursive --branch stable --depth 1 https://github.com/microsoft/LightGBM && \
    cd LightGBM && mkdir build && cd build && \
    cmake -DUSE_GPU=1 -DOpenCL_LIBRARY=/usr/local/cuda/lib64/libOpenCL.so -DOpenCL_INCLUDE_DIR=/usr/local/cuda/include/ .. && \
    make OPENCL_HEADERS=/usr/local/cuda-11.3/targets/x86_64-linux/include/ LIBOPENCL=/usr/local/cuda-11.3/targets/x86_64-linux/lib/

ENV PATH /usr/local/src/lightgbm/LightGBM:${PATH}

RUN /bin/bash -c "conda activate ml-env && \
                  cd /usr/local/src/lightgbm/LightGBM/python-package && \
                  python setup.py install --precompile && \ 
                  conda deactivate"

#################################################################################################################
#           System CleanUp
#################################################################################################################
# apt-get autoremove: used to remove packages that were automatically installed to satisfy dependencies for some package and that are no more needed.
# apt-get clean: removes the aptitude cache in /var/cache/apt/archives. You'd be amazed how much is in there! the only drawback is that the packages
# have to be downloaded again if you reinstall them.

RUN apt-get autoremove -y && apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    /opt/conda/bin/mamba clean --all -f -y

#################################################################################################################
#           JUPYTER
#################################################################################################################

# password: keras
# password key: --NotebookApp.password='sha1:98b767162d34:8da1bc3c75a0f29145769edc977375a373407824'

# Add a notebook profile.
RUN mkdir -p -m 700 ~/.jupyter/ && \
    echo "c.ServerApp.ip = '*'" >> ~/.jupyter/jupyter_notebook_config.py

# IPython
# Jupyter listens ports:
EXPOSE 8888
EXPOSE 8787
EXPOSE 8686
# MLFlow listening port:
EXPOSE 5000

VOLUME /app
WORKDIR /app
COPY . /app

# Override default shell and use bash
# SHELL ["/opt/conda/bin/conda", "run", "-n", "ml-env", "/bin/bash", "-c"]

# Activate Conda environment and check if it is working properly
# RUN echo "Making sure pycaret is installed correctly..."
# RUN python -c "import pycaret"

# Python program to run in the container
COPY app.py .
ENTRYPOINT [ "/tini", "--" ]
CMD /bin/bash -c "conda activate basee && jupyter-lab --allow-root --no-browser && conda deactivate"
