#!/usr/bin/env -l

# fix jupyter server to run properly
# mamba remove --force notebook -y
# mamba remove --force jupyter_nbextensions_configurator -y
# mamba remove --force jupyter_contrib_nbextensions -y
# mamba install jupyter notebook -y

mamba install -c anaconda cudatoolkit -y
mamba install -c conda-forge jupytext -y
mamba install -c conda-forge jupyterlab jupyter_nbextensions_configurator jupyter_contrib_nbextensions -y
pip install jupyter-tensorboard
# Create Conda environment from the YAML file
/opt/conda/bin/mamba env create -f environment.yml

# activate target environment
ENV CONDA_TARGET_ENV=ml-env
/opt/conda/bin/mamba init bash && echo '/opt/conda/bin/mamba activate "${CONDA_TARGET_ENV:-base}"' >>  ~/.bashrc

# Name the enviornment to add to pick list in jupyter
python -m ipykernel install --user --name ml-env --display-name ml-env

echo "before calling source: $PATH"
conda activate ml-env
echo "after calling source: $PATH"

# install the specified version of pycaret
pip install -U --pre pycaret[full]==3.0.0rc4

# Activate Conda environment and check if it is working properly
echo "Making sure pycaret is installed correctly..."
python -c "import pycaret"

cd /app/projects/lc
python setup.py develop

# Activate Conda environment and check if it is working properly
echo "Making sure lendingclub is installed correctly..."
python -c "import lendingclub"