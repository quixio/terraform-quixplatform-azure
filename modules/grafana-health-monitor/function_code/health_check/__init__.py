import azure.functions as func
import logging
import os
import requests
from opencensus.ext.azure import metrics_exporter
from opencensus.stats import aggregation, measure, stats, view

# Setup custom metrics
grafana_availability_measure = measure.MeasureInt(
    "GrafanaAvailability",
    "Grafana health check result (1=healthy, 0=unhealthy)",
    "1"
)

grafana_response_time_measure = measure.MeasureFloat(
    "GrafanaResponseTime",
    "Grafana health check response time in milliseconds",
    "ms"
)

availability_view = view.View(
    "GrafanaAvailability",
    "Grafana availability metric",
    [],
    grafana_availability_measure,
    aggregation.LastValueAggregation()
)

response_time_view = view.View(
    "GrafanaResponseTime",
    "Grafana response time metric",
    [],
    grafana_response_time_measure,
    aggregation.LastValueAggregation()
)

# Register views
stats.stats.view_manager.register_view(availability_view)
stats.stats.view_manager.register_view(response_time_view)

# Setup Azure Monitor exporter
def get_exporter():
    connection_string = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if connection_string:
        return metrics_exporter.new_metrics_exporter(connection_string=connection_string)
    return None

exporter = get_exporter()
if exporter:
    stats.stats.view_manager.register_exporter(exporter)

mmap = stats.stats.stats_recorder.new_measurement_map()


def main(timer: func.TimerRequest) -> None:
    """
    Timer-triggered function that checks Grafana health and emits metrics.
    """
    grafana_url = os.environ.get("GRAFANA_HEALTH_URL")
    timeout = int(os.environ.get("HEALTH_CHECK_TIMEOUT_SECONDS", "10"))

    if not grafana_url:
        logging.error("GRAFANA_HEALTH_URL environment variable is not set")
        record_metrics(0, -1)
        return

    logging.info(f"Checking Grafana health at: {grafana_url}")

    try:
        response = requests.get(grafana_url, timeout=timeout)
        response_time_ms = response.elapsed.total_seconds() * 1000
        is_healthy = 1 if response.status_code == 200 else 0

        if is_healthy:
            logging.info(f"Grafana is healthy. Response time: {response_time_ms:.2f}ms")
        else:
            logging.warning(
                f"Grafana returned non-200 status: {response.status_code}. "
                f"Response time: {response_time_ms:.2f}ms"
            )

        record_metrics(is_healthy, response_time_ms)

    except requests.exceptions.Timeout:
        logging.error(f"Grafana health check timed out after {timeout}s")
        record_metrics(0, timeout * 1000)

    except requests.exceptions.ConnectionError as e:
        logging.error(f"Failed to connect to Grafana: {e}")
        record_metrics(0, -1)

    except Exception as e:
        logging.error(f"Unexpected error during health check: {e}")
        record_metrics(0, -1)


def record_metrics(is_healthy: int, response_time_ms: float) -> None:
    """Record metrics to Application Insights."""
    mmap.measure_int_put(grafana_availability_measure, is_healthy)
    if response_time_ms >= 0:
        mmap.measure_float_put(grafana_response_time_measure, response_time_ms)
    mmap.record()
