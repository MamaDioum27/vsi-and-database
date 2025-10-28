from flask import Flask
import psycopg2

app = Flask(__name__)

DB_HOST = "mydb.abcdef123.eu-west-1.rds.amazonaws.com"
DB_NAME = "appdb"
DB_USER = "admin"
DB_PASS = "YOUR_PASSWORD"

@app.route("/")
def index():
    try:
        conn = psycopg2.connect(
            host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASS
        )
        cur = conn.cursor()
        cur.execute("SELECT version();")
        version = cur.fetchone()
        cur.close()
        conn.close()
        return f"Connected to RDS! PostgreSQL version: {version[0]}"
    except Exception as e:
        return f"Error: {str(e)}"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
