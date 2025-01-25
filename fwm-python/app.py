from flask import Flask, request, jsonify
import pygrib
import numpy as np
import os

app = Flask(__name__)

@app.route("/")
def home():
    return "Hello from Flask container!"

@app.route('/get-grib-data')
def get_grib_data():
    file_path = request.args.get('file')
    lat = float(request.args.get('lat'))
    lon = float(request.args.get('lon'))

    try:
        grbs = pygrib.open(file_path)
        grb = grbs[1]
        shortName = grb.shortName
        forecast_time = int(grb.validDate.timestamp() * 1000)

        # Check for step range (accumulation period)
        step_range = grb.stepRange  # Usually like "0-3" (e.g., accumulated over 3 hours)
        step_units = "minutes" if grb.stepUnits == 0 else grb.stepUnits

        # Adjust forecast time for "tp" (total precipitation)
        if shortName == "tp" and "-" in step_range:
            start, end = map(int, step_range.split("-"))
            forecast_time += int(end * 60 * 1000) 

        values, lats, lons = grb.data()

        # Correct if the grid is scanning from top to bottom
        if grb.scanningMode == 64:
            lats = np.flipud(lats)
            values = np.flipud(values)

        # Normalize longitudes to the 0-360 range
        lons[lons < 0] += 360
        lon = lon if lon >= 0 else lon + 360

        # Find the nearest grid point
        distance = np.sqrt((lats - lat)**2 + (lons - lon)**2)
        nearest_idx = np.unravel_index(np.argmin(distance), lats.shape)
        nearest_value = values[nearest_idx]

        return jsonify({
            "lat": float(lats[nearest_idx]),
            "lon": float(lons[nearest_idx]),
            "value": float(nearest_value),
            "forecast_time": forecast_time,
            "range": step_range,
            "step": 60,
            "step_units": step_units,
            "shortName": shortName,
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

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

if __name__ == "__main__":
    port = int(os.getenv("PYTHON_PORT", 6000)) 
    app.run(host="0.0.0.0", port=port)
