import os
import socket

import psycopg
from flask import Flask, jsonify, render_template

app = Flask(__name__)

APP_VERSION = os.getenv("APP_VERSION", "dev")
APP_ENV = os.getenv("APP_ENV", "local")
DATABASE_URL = os.getenv("DATABASE_URL", "")


def get_connection():
    return psycopg.connect(DATABASE_URL, connect_timeout=3)


def record_visit(hostname):
    with get_connection() as conn:
        conn.execute("INSERT INTO visits (hostname) VALUES (%s)", (hostname,))
        return conn.execute("SELECT count(*) FROM visits").fetchone()[0]


@app.route("/")
def index():
    hostname = socket.gethostname()
    try:
        visits = record_visit(hostname)
    except psycopg.Error:
        app.logger.exception("Could not record visit")
        visits = None

    return render_template(
        "index.html",
        version=APP_VERSION,
        environment=APP_ENV,
        hostname=hostname,
        visits=visits,
    )


@app.route("/health")
def health():
    return jsonify(status="ok"), 200


@app.route("/ready")
def ready():
    try:
        with get_connection() as conn:
            conn.execute("SELECT 1")
    except psycopg.Error:
        return jsonify(status="unavailable", database="down"), 503
    return jsonify(status="ok", database="up"), 200


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="127.0.0.1", port=port, debug=APP_ENV == "local")
