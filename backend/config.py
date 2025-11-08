# backend/config.py
import os
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent

class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "devsecret")
    API_KEY = os.environ.get("API_KEY", "change_this_api_key")  # ============ CAMBIAR ============
    SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URL", f"sqlite:///{BASE_DIR/'conveyor.db'}")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
