#!/bin/bash

nohup up jupyter-lab --allow-root --ServerApp.ip=0.0.0.0 --ServerApp.port=8888 --no-browser --notebook-dir="/app/" --ServerApp.token='abcdefg1234567890' --ServerApp.password='abcdefg1234567890' > /dev/null 2>&1 &
# CMD ["jupyter-lab", "--allow-root", "--notebook-dir=/mnt/ssd0", "--ip=*", "--port=8888", "--no-browser", "&"]

echo "JupyterLab server started."