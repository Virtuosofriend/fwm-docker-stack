FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3-pip \
    python3-dev \
    gcc \
    gfortran \
    libeccodes0 \
    libeccodes-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir flask pygrib scipy joblib gunicorn apscheduler

ARG PYTHON_PORT
ENV PYTHON_PORT=${PYTHON_PORT}

# Set the working directory
WORKDIR /app

# Copy the app files
COPY . /app

EXPOSE 6000

# Run the application with Gunicorn
CMD ["gunicorn", "--config", "gunicorn.conf.py", "--preload", "app:app"]
