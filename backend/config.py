import os
from models import db

class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "devsecret")
    API_KEY = os.environ.get("API_KEY", "patroclo")
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL",
        "postgresql://iot:p3guljWveqfEFZLYmI32piQxbzi6iaIq@dpg-d4avpa2li9vc73dljvng-a.oregon-postgres.render.com/iot_db_wcra"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
