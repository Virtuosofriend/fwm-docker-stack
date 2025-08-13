from flask import Flask, request, jsonify
import pygrib
import numpy as np
import os
import logging
from concurrent.futures import ProcessPoolExecutor
from joblib import Memory, Parallel, delayed
from apscheduler.schedulers.background import BackgroundScheduler
import atexit

os.environ['JOBLIB_TEMP_FOLDER'] = '/var/tmp/joblib'
os.makedirs(os.environ['JOBLIB_TEMP_FOLDER'], exist_ok=True)

app = Flask(__name__)
FORECASTS_DIR = "/forecasts"
CACHE_DIR = "/tmp/cache"
CORES_ALLOCATED = 2

# Set up joblib caching
memory = Memory(CACHE_DIR, verbose=0, bytes_limit=1e9, mmap_mode='r')

# Initialize the APScheduler
scheduler = BackgroundScheduler()

# Add a job to clear the cache every hour
scheduler.add_job(memory.clear, 'interval', hours=1)

# Start the scheduler
scheduler.start()

# Shut down the scheduler when the app exits
atexit.register(lambda: scheduler.shutdown())

@memory.cache
def read_grib_file(file_path):
    try:
        grbs = pygrib.open(file_path)
        grb = grbs[1]
        values, lats, lons = grb.data()

        # Correct scanning mode
        if grb.scanningMode == 64:
            lats = np.flipud(lats)
            values = np.flipud(values)

        # Normalize longitudes
        lons[lons < 0] += 360

        return {
            "shortName": grb.shortName,
            "forecast_time": int(grb.validDate.timestamp() * 1000),
            "step_range": grb.stepRange,
            "step_units": grb.stepUnits,
            "step": grb.step,
            "values": values,
            "lats": lats,
            "lons": lons,
            "file": os.path.basename(file_path)
        }

    except Exception as e:
        return {"error": str(e), "file": os.path.basename(file_path)}

@memory.cache
def get_grib_files():
    """ Recursively finds all GRIB files in the forecasts directory and caches the list. """
    grib_files = []
    for root, _, files in os.walk(FORECASTS_DIR):
        for file in files:
            if file.endswith(".grib2") or file.endswith(".grib"):
                grib_files.append(os.path.join(root, file))

    grib_files.sort(key=lambda x: os.path.basename(x))
    return grib_files

def process_grib(file_data, lat, lon):
    """ Extracts the nearest value for a list of lat/lon pairs from cached GRIB data. """
    try:
        if "error" in file_data:
            return [file_data]  # Return the error message if caching failed

        shortName = file_data["shortName"]
        forecast_time = file_data["forecast_time"]
        step_range = file_data["step_range"]
        step_units = file_data["step_units"]
        step = file_data["step"]
        values, lats, lons = file_data["values"], file_data["lats"], file_data["lons"]

        results = []
        def get_result(lat, lon):
            ft = forecast_time
            st = step
            # Handle step range for precipitation
            if shortName == "tp" and "-" in step_range:
                if step_units == 0:  # Step is in minutes
                    ft += int(st * 60 * 1000)  # Convert minutes to milliseconds
                elif step_units == 1:  # Step is in hours
                    ft += int(st * 60 * 60 * 1000)  # Convert hours to milliseconds
                else:
                    raise ValueError(f"Unsupported step_units: {step_units}")
            else:
                st = 60  # Default step (in minutes)

            # Find the nearest grid point
            distance = np.sqrt((lats - lat) ** 2 + (lons - lon) ** 2)
            nearest_idx = np.unravel_index(np.argmin(distance), lats.shape)
            nearest_value = values[nearest_idx]

            return {
                "lat": float(lats[nearest_idx]),
                "lon": float(lons[nearest_idx]),
                "value": float(nearest_value),
                "forecast_time": ft,
                "range": step_range,
                "step": st,
                "step_units": step_units,
                "shortName": shortName,
                "file": file_data["file"]
            }

        # latlons is a list of (lat, lon) tuples
        # This function will be called with latlons as argument
        # We'll handle that in the endpoint
        return get_result
    except Exception as e:
        return lambda lat, lon: {"error": str(e), "file": file_data["file"]}

@app.route("/")
def home():
    return "Hello from Flask container!"

@app.route('/get-grib-data')
def get_grib_data():
    """ Processes multiple lat/lon pairs using parallel processing and caching, avoiding nested parallelism. """
    latitudes = request.args.getlist('lat', type=float)
    longitudes = request.args.getlist('lon', type=float)

    if not latitudes or not longitudes or len(latitudes) != len(longitudes):
        return jsonify({"error": "Invalid or missing lat/lon parameters"}), 400

    try:
        grib_files = get_grib_files()
        if not grib_files:
            return jsonify({"error": "No GRIB files found in forecasts directory"}), 404

        # Read GRIB files in parallel and cache the results
        file_data_list = Parallel(n_jobs=CORES_ALLOCATED)(delayed(read_grib_file)(file) for file in grib_files)

        latlons = list(zip(latitudes, longitudes))

        # For each file, process all lat/lon pairs (no inner parallelism)
        results = []
        for file_data in file_data_list:
            process_fn = process_grib(file_data, 0, 0)
            for lat, lon in latlons:
                results.append(process_fn(lat, lon))

        return jsonify({"data": results})

    except Exception as e:
        logging.error(f"Error in /get-grib-data: {e}")
        return jsonify({"error": "Internal server error"}), 500

@app.route('/get-grib-data-with-bbox')
def get_grib_bbox_data():
    file_path = request.args.get('file')
    try:
        # Get BBOX coordinates from query params
        min_lat = float(request.args.get('min_lat'))
        max_lat = float(request.args.get('max_lat'))
        min_lon = float(request.args.get('min_lon'))
        max_lon = float(request.args.get('max_lon'))

        # Convert longitude to 0-360 range if necessary
        if min_lon < 0:
            min_lon += 360
        if max_lon < 0:
            max_lon += 360

        grbs = pygrib.open(file_path)
        grb = grbs[1]
        values, lats, lons = grb.data()

        # Adjust to ensure all longitudes in the file match the same range
        lons[lons < 0] += 360

        # Extract data within the BBOX
        matching_values = []
        for lat, lon, value in zip(lats.flatten(), lons.flatten(), values.flatten()):
            if min_lat <= lat <= max_lat and min_lon <= lon <= max_lon:
                matching_values.append({"lat": lat, "lon": lon, "value": value})

        if not matching_values:
            return jsonify({"error": "No data found in the specified bbox"}), 404

        return jsonify({"data": matching_values})

    except ValueError:
        return jsonify({"error": "Invalid input for latitude or longitude"}), 400
    except Exception as e:
        return jsonify({"error": str(e)}), 500

