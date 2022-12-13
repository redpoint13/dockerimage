# For more information, please refer to https://aka.ms/vscode-docker-python
# FROM ubuntu:22.04
# FROM nvcr.io/nvidia/rapidsai/rapidsai:22.10-cuda11.5-runtime-ubuntu20.04-py3.8
# FROM nvcr.io/nvidia/rapidsai/rapidsai:cuda11.4-base-ubuntu20.04-py3.8
FROM nvcr.io/nvidia/tensorflow:22.11-tf2-py3


# Keeps Python from generating .pyc files in the container
ENV PYTHONDONTWRITEBYTECODE=1

# Turns off buffering for easier container logging
ENV PYTHONUNBUFFERED=1

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

# install basic apps, one per line for better caching
RUN apt-get update && apt-get install -qy apt-utils
RUN apt-get update && apt-get install -qy locales && \
    apt-get update && apt-get install -qy build-essential && \
    apt-get update && apt-get install -qy --no-install-recommends libboost-system-dev libboost-filesystem-dev && \
    apt-get update && apt-get install -qy libtinfo6 && \
    apt-get update && apt-get install -qy libtinfo-dev && \
    apt-get update && apt-get install -qy wget && \
    apt-get update && apt-get install -qy curl && \
    apt-get update && apt-get install -qy nano && \
    apt-get update && apt-get install -qy unzip && \
    apt-get update && apt-get install -qy git && \
    # apt-get update && apt-get install -qy docker nvidia-container-toolkit && \
    rm -rf /var/lib/apt/lists/*

# Leave these args here to better use the Docker build cache
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
    echo "conda activate base" >> ~/.bashrc && \
    find /opt/conda/ -follow -type f -name '*.a' -delete && \
    find /opt/conda/ -follow -type f -name '*.js.map' -delete && \
    /opt/conda/bin/conda clean -afy


RUN /opt/conda/bin/conda update -y -n base conda
RUN /opt/conda/bin/conda install -y -n base -c conda-forge mamba
RUN /opt/conda/bin/mamba update --all -y

# RUN /opt/conda/bin/mamba install -y -n base -c anaconda cudatoolkit
RUN /opt/conda/bin/mamba install -y -n base -c conda-forge jupyterlab nb_conda_kernels tensorboard jupytext jupyter_nbextensions_configurator jupyter_contrib_nbextensions

WORKDIR /app
COPY . /app

# Create Conda environment from the YAML file
RUN /opt/conda/bin/mamba env create -f environment.yml
ENV CONDA_DEFAULT_ENV=ml-env
RUN /opt/conda/bin/mamba init bash && echo '/opt/conda/bin/mamba activate "${CONDA_DEFAULT_ENV:-base}"' >>  ~/.bashrc

RUN python -m ipykernel install --user --name ml-env --display-name ml-env

# Override default shell and use bash
# SHELL ["/opt/conda/bin/conda", "run", "-n", "ml-env", "/bin/bash", "-c"]

# Activate Conda environment and check if it is working properly
# RUN echo "Making sure pycaret is installed correctly..."
# RUN python -c "import pycaret"

# Python program to run in the container
COPY app.py .
CMD ["/bin/bash"]