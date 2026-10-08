import os
import socket

from flask import Flask, jsonify, render_template

app = Flask(__name__)

APP_VERSION = os.getenv("APP_VERSION", "dev")
APP_ENV = os.getenv("APP_ENV", "local")

@app.route("/")
def index():
    return render_template(
        "index.html",
        version=APP_VERSION,
        environment=APP_ENV,
        hostname=socket.gethostname(),
    )

@app.route("/health")
def health():
    return jsonify(status="ok"), 200

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="127.0.0.1", port=port, debug=APP_ENV == "local")