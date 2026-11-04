"""Demo application: a Flask web app running on a VM (IaaS) that talks to a
managed PostgreSQL database (PaaS: AWS RDS or GCP Cloud SQL).

Configuration is read from environment variables (see .env.example).
Never commit real credentials to Git.
"""
import os
import socket

import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)
HOSTNAME = socket.gethostname()


@app.after_request
def add_served_by_header(response):
    """Tell the client which VM answered (visible through the load balancer)."""
    response.headers["X-Served-By"] = HOSTNAME
    return response


def get_connection():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "appdb"),
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASS"],
        connect_timeout=5,
    )


@app.route("/")
def index():
    try:
        with get_connection() as conn, conn.cursor() as cur:
            cur.execute("SELECT version();")
            version = cur.fetchone()[0]
        return f"Connected to the database! PostgreSQL version: {version}"
    except KeyError as e:
        return f"Missing environment variable: {e}", 500
    except psycopg2.Error as e:
        return f"Database error: {e}", 500


@app.route("/health")
def health():
    """Lightweight check: the app is up (does not require the database)."""
    return jsonify(status="ok")


@app.route("/whoami")
def whoami():
    """Identify the VM that served the request (used to demo load balancing)."""
    return jsonify(hostname=HOSTNAME)


if __name__ == "__main__":
    # Port 8080 does not require root. Expose it via the Security Group /
    # firewall rule, or put Apache/Nginx in front as a reverse proxy on port 80.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
