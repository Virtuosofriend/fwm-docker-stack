import multiprocessing

# CPU-bound GRIB reading → 2 workers for 2 cores
workers = 2  

# Bind to all interfaces
bind = "0.0.0.0:6000"

# Give heavy GRIB processing plenty of time
timeout = 300  # 5 minutes before killing a stuck worker

# Don't kill the worker while still sending data
graceful_timeout = 60  

# Preload the app so that workers share as much memory as possible
preload_app = True  

# Avoid excess forking delays on startup
worker_class = "sync"

# Limit requests per worker to prevent slow memory leaks from growing too big
# A bit of jitter prevents all workers from recycling at the same time
max_requests = 200
max_requests_jitter = 20

# Logging
accesslog = "-"
errorlog = "-"
loglevel = "info"

# Extra safety: disable request buffering if large uploads might be sent
limit_request_line = 0
limit_request_field_size = 0
