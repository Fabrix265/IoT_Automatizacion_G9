# backend/models.py
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()

class Shift(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120))
    started_at = db.Column(db.DateTime, default=datetime.utcnow)
    ended_at = db.Column(db.DateTime, nullable=True)
    active = db.Column(db.Boolean, default=False)

class ObjectEvent(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    size_cat = db.Column(db.String(20))  # "small","medium","large"
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    shift_id = db.Column(db.Integer, db.ForeignKey('shift.id'), nullable=True)
    length_est = db.Column(db.Float, nullable=True)  # opcional: distancia en metros o cm

class DeviceState(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    motor_on = db.Column(db.Boolean, default=False)
    turn_led_on = db.Column(db.Boolean, default=False)
    box_full = db.Column(db.Boolean, default=False)
    last_update = db.Column(db.DateTime, default=datetime.utcnow)
