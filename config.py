import os
import pathlib

import connexion
from dotenv import load_dotenv
from flask_marshmallow import Marshmallow
from flask_sqlalchemy import SQLAlchemy

load_dotenv()   # reads .env.
                #in docker the variables come in with the --env-file instead so this just finds nothing and moves on

basedir = pathlib.Path(__file__).parent.resolve()

#add_api lives here rather than in app.py, which isnt how it used to be as leaving it in app.py meant it ran a
#second time when uvicorn re-imported the module, which gave "/api already registered"
connex_app = connexion.FlaskApp(__name__, specification_dir=basedir)
connex_app.add_api("swagger.yml")
app = connex_app.app

#credentials come out of the environment not out of the source
DB_SERVER   = os.getenv("DB_SERVER", "dist-6-505.uopnet.plymouth.ac.uk")
DB_NAME     = os.getenv("DB_NAME")
DB_USER     = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")

app.config["SQLALCHEMY_DATABASE_URI"] = (
    "mssql+pyodbc:///?odbc_connect="
    "DRIVER={ODBC Driver 17 for SQL Server};"
    f"SERVER={DB_SERVER};"
    f"DATABASE={DB_NAME};"
    f"UID={DB_USER};"
    f"PWD={DB_PASSWORD};"
    "TrustServerCertificate=yes;"
    "Encrypt=yes;"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

#used to sign the JWTs 
app.config["JWT_SECRET"] = os.getenv("JWT_SECRET", "change-me-in-production")

#the external credential checker service
AUTH_API_URL = "https://web.socem.plymouth.ac.uk/COMP2001/auth/api/users"

db = SQLAlchemy(app)
ma = Marshmallow(app)
