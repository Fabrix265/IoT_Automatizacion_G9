from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()

class DeviceState(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    motor = db.Column(db.Boolean, default=False)
    turnLed = db.Column(db.Boolean, default=False)
    boxFull = db.Column(db.Boolean, default=False)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
