from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()

class DeviceState(db.Model):
    __tablename__ = "device_state"
    id = db.Column(db.Integer, primary_key=True)
    motor_on = db.Column(db.Boolean, default=False)
    turn_led_on = db.Column(db.Boolean, default=False)
    box_full = db.Column(db.Boolean, default=False)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)

class Shift(db.Model):
    __tablename__ = "shift"
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(200))
    start_at = db.Column(db.DateTime, default=datetime.utcnow)
    end_at = db.Column(db.DateTime, nullable=True)
    counts_total = db.Column(db.Integer, default=0)
    counts_small = db.Column(db.Integer, default=0)
    counts_medium = db.Column(db.Integer, default=0)
    counts_large = db.Column(db.Integer, default=0)

    def as_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "start_at": self.start_at.isoformat(),
            "end_at": self.end_at.isoformat() if self.end_at else None,
            "counts": {
                "total": self.counts_total,
                "small": self.counts_small,
                "medium": self.counts_medium,
                "large": self.counts_large
            }
        }

class ObjectEvent(db.Model):
    __tablename__ = "object_event"
    id = db.Column(db.Integer, primary_key=True)
    size_cat = db.Column(db.String(20))  # small/medium/large
    length_est = db.Column(db.Float)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    shift_id = db.Column(db.Integer, db.ForeignKey('shift.id'), nullable=True)
    shift = db.relationship('Shift', backref=db.backref('events', lazy=True))
