FROM continuumio/miniconda3:24.7.1-0

# Create environment with pinned versions
RUN conda create -n myenv -c conda-forge -y \
    python=3.11 \
    pygrib=2.1.6 \
    scipy=1.15.1 \
    eccodes \
    joblib=1.4.2 \
    flask=3.1.0 \
    gunicorn=23.0.0 \
    apscheduler=3.11.0 \
    sqlite \
    && conda clean -afy

# Activate environment
ENV PATH=/opt/conda/envs/myenv/bin:$PATH
ENV PROJ_LIB=/opt/conda/envs/myenv/share/proj
ENV PYTHONUNBUFFERED=1
ENV JOBLIB_TEMP_FOLDER=/var/tmp/joblib

# Create joblib temp folder
RUN mkdir -p /var/tmp/joblib && chmod 777 /var/tmp/joblib

# Set working directory
WORKDIR /app

# Copy the app files
COPY . /app

EXPOSE 6000

CMD ["gunicorn", "--config", "gunicorn.conf.py", "--preload", "app:app"]
