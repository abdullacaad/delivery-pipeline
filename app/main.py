"""Small Flask service used to demonstrate the delivery pipeline."""
import os

from flask import Flask, jsonify, request

app = Flask(__name__)


def _version() -> str:
    return os.getenv("APP_VERSION", "dev")


@app.get("/")
def index():
    return jsonify(service="delivery-demo", version=_version())


@app.get("/health")
def health():
    # SIMULATE_UNHEALTHY exists only so the pipeline's rollback can be demonstrated.
    if os.getenv("SIMULATE_UNHEALTHY") == "1":
        return jsonify(status="unhealthy", version=_version()), 503
    return jsonify(status="ok", version=_version())


@app.get("/version")
def version():
    return jsonify(version=_version())


@app.get("/api/greet")
def greet():
    name = request.args.get("name", "world").strip() or "world"
    return jsonify(message=f"Hello, {name}!")


@app.get("/api/add")
def add():
    try:
        a = float(request.args["a"])
        b = float(request.args["b"])
    except (KeyError, ValueError):
        return jsonify(error="query params 'a' and 'b' must be numbers"), 400
    return jsonify(result=a + b)
