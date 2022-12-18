# For more information, please refer to https://aka.ms/vscode-docker-python
# FROM ubuntu:22.04
# FROM nvcr.io/nvidia/rapidsai/rapidsai:22.10-cuda11.5-runtime-ubuntu20.04-py3.8
# FROM nvcr.io/nvidia/rapidsai/rapidsai:cuda11.4-base-ubuntu20.04-py3.8
# FROM nvcr.io/nvidia/tensorflow:22.11-tf2-py3
FROM nvcr.io/nvidia/rapidsai/rapidsai-core:22.10-cuda11.5-runtime-ubuntu20.04-py3.8


# Keeps Python from generating .pyc files in the container
ENV PYTHONDONTWRITEBYTECODE=1
# Turns off buffering for easier container logging
ENV PYTHONUNBUFFERED=1

ARG DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND noninteractive

# Jupyter listens ports:
EXPOSE 8888
EXPOSE 8787
EXPOSE 8686

# MLFlow listening port:
EXPOSE 5000

# Creates a non-root user with an explicit UID and adds permission to access the /app folder
# https://code.visualstudio.com/remote/advancedcontainers/add-nonroot-user
# https://code.visualstudio.com/remote/advancedcontainers/overview
# ARG USERNAME=appuser
# ARG USER_UID=1000
# ARG USER_GID=$USER_UID

# # Create the user
# RUN groupadd --gid $USER_GID $USERNAME \
#     && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
#     #
#     # [Optional] Add sudo support. Omit if you don't need to install software after connecting.
#     && apt-get update \
#     && apt-get install -y sudo \
#     && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
#     && chmod 0440 /etc/sudoers.d/$USERNAME

# ********************************************************
# * Anything else you want to do like clean up goes here *
# ********************************************************
# [Optional] Set the default user. Omit if you want to keep the default as root.
# USER $USERNAME

# RUN apt-get update && apt-get install -qy ubuntu-drivers-common && apt-get update && apt-get install -qy software-properties-common -qy && apt-get update && add-apt-repository ppa:graphics-drivers/ppa && apt-get update

# install basic apps, one per line for better caching
RUN apt-get update && apt-get install -qy apt-utils
RUN apt-get update && apt-get install -qy locales && \
    apt-get update && apt-get install -qy build-essential && \
    apt-get update && apt-get install -qy --no-install-recommends libboost-system-dev libboost-filesystem-dev libboost-all-dev && \
    apt-get update && apt-get install -qy --no-install-recommends cmake libboost-dev && \
    # apt-get update && apt-get install -qy libtinfo6 && \
    # apt-get update && apt-get install -qy libtinfo-dev && \
    apt-get update && apt-get install -qy wget && \
    apt-get update && apt-get install -qy curl && \
    apt-get update && apt-get install -qy nano && \
    apt-get update && apt-get install -qy unzip && \
    apt-get update && apt-get install -qy git && \
    apt-get update && apt-get install -qy python3-pip && \
    apt-get update && apt-get install -qy opencl-headers ocl-icd-opencl-dev && \
    # apt-get update && apt-get install -qy docker nvidia-container-toolkit && \
    apt-get autoclean -y && apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Leave these args here to better use the Docker build cache: conda in rapids base image
# ARG CONDA_VERSION=py38_4.12.0
# ARG CONDA_MD5=3190da6626f86eee8abf1b2fd7a5af492994eb2667357ee4243975cdbb175d7a
# RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-x86_64.sh -O miniconda.sh && \
#     echo "${CONDA_MD5}  miniconda.sh" > miniconda.md5 && \
#     if ! sha256sum --status -c miniconda.md5; then exit 1; fi && \
#     mkdir -p /opt && \
#     sh miniconda.sh -b -p /opt/conda && \
#     rm miniconda.sh miniconda.md5 && \
#     ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
#     echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
#     echo "conda activate base" >> ~/.bashrc && \
#     find /opt/conda/ -follow -type f -name '*.a' -delete && \
#     find /opt/conda/ -follow -type f -name '*.js.map' -delete && \
#     /opt/conda/bin/conda clean -afy

# name your environment and choose python 3.x version

RUN /opt/conda/bin/conda update -qy -n base conda
RUN /opt/conda/bin/conda update -qy -n base -c conda-forge mamba
RUN /opt/conda/bin/mamba update --all -y

# RUN /opt/conda/bin/mamba install -y -n base -c anaconda cudatoolkit
RUN /opt/conda/bin/mamba install -y -n base -c conda-forge jupyterlab nb_conda_kernels tensorboard jupytext jupyter_nbextensions_configurator jupyter_contrib_nbextensions

WORKDIR /app
COPY . /app

# Create Conda environment from the YAML file
RUN /opt/conda/bin/mamba env create -f environment.yml

# Make RUN commands use the new environment:
ENV CONDA_DEFAULT_ENV=ml-env
ARG conda_env=ml-env
RUN /opt/conda/bin/mamba init bash && echo '/opt/conda/bin/mamba activate "${CONDA_DEFAULT_ENV:-base}"' >>  ~/.bashrc
SHELL ["/bin/bash", "--login", "-c"]

# create Python 3.x environment and link it to jupyter
# RUN "${CONDA_DIR}/envs/${conda_env}/bin/python" -m ipykernel install --user --name="${conda_env}" && \
#     fix-permissions "${CONDA_DIR}" && \
#     fix-permissions "/home/${NB_USER}"
RUN python -m ipykernel install --user --name ml-env --display-name ml-env


# prepend conda environment to path
ENV PATH "${CONDA_DIR}/envs/${conda_env}/bin:${PATH}"

# make the env default
ENV CONDA_DEFAULT_ENV ${conda_env}

# install lightgbm gpu version
RUN mkdir -p /tmp/workspace && \
    chown $(whoami):$(whoami) /tmp/workspace 
WORKDIR /tmp/workspace/
# RUN /bin/bash -c "mamba activate ml-env"
ENV CL_TARGET_OPENCL_VERSION 220
RUN /bin/bash -c "git clone --recursive https://github.com/microsoft/LightGBM && \
    cd LightGBM && mkdir build && cd build && \
    # cmake -DUSE_GPU=1 .. && \
    # if you have installed NVIDIA CUDA to a customized location, you should specify paths to OpenCL headers and library like the following:
    cmake -DUSE_GPU=1 -DOpenCL_LIBRARY=/usr/local/cuda/lib64/libOpenCL.so.1 -DOpenCL_INCLUDE_DIR=/usr/local/cuda/include/ .. && \
    make -j$(nproc) && \
    cd .. && \
    cd python-package && \
    /opt/conda/envs/ml-env/bin/python setup.py install --precompile --cuda"


RUN /opt/conda/bin/mamba clean --all -f -y

WORKDIR /app

RUN rm -rf /tmp/workspace/*

COPY . /app


# Override default shell and use bash
# SHELL ["/opt/conda/bin/conda", "run", "-n", "ml-env", "/bin/bash", "-c"]

# Activate Conda environment and check if it is working properly
# RUN echo "Making sure pycaret is installed correctly..."
# RUN python -c "import pycaret"

# Python program to run in the container
COPY app.py .
CMD ["/bin/bash"]