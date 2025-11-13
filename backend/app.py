# backend/app.py
import os
from flask import Flask, request, jsonify
from flask_cors import CORS
from models import db, Shift, ObjectEvent, DeviceState
from config import Config
from datetime import datetime
from sqlalchemy import desc

app = Flask(__name__)
app.config.from_object(Config)
CORS(app)
db.init_app(app)

API_KEY = app.config.get("API_KEY")

def require_api_key(fn):
    def wrapper(*args, **kwargs):
        key = request.headers.get("x-api-key") or request.args.get("api_key")
        if not key or key != API_KEY:
            return jsonify({"error":"Unauthorized"}), 401
        return fn(*args, **kwargs)
    wrapper.__name__ = fn.__name__
    return wrapper

@app.before_request
def setup_db_once():
    if not hasattr(app, 'has_created_db'):
        with app.app_context():
            db.create_all()
            if not DeviceState.query.first():
                ds = DeviceState(motor_on=False, turn_led_on=False, box_full=False)
                db.session.add(ds)
                db.session.commit()
        app.has_created_db = True


# START SHIFT
@app.route("/api/shift/start", methods=["POST"])
@require_api_key
def start_shift():
    name = request.json.get("name") if request.json else None
    # close others
    active = Shift.query.filter_by(active=True).all()
    for s in active:
        s.active = False
        s.ended_at = datetime.utcnow()
    s = Shift(name=name or f"Turno {datetime.utcnow().isoformat()}", started_at=datetime.utcnow(), active=True)
    db.session.add(s)
    # set led on
    ds = DeviceState.query.first()
    ds.turn_led_on = True
    db.session.commit()
    return jsonify({"message":"shift_started","shift_id":s.id})

# END SHIFT
@app.route("/api/shift/end", methods=["POST"])
@require_api_key
def end_shift():
    sid = request.json.get("shift_id") if request.json else None
    s = Shift.query.get(sid) if sid else Shift.query.filter_by(active=True).first()
    if not s:
        return jsonify({"error":"no_active_shift"}), 400
    s.active = False
    s.ended_at = datetime.utcnow()
    ds = DeviceState.query.first()
    ds.turn_led_on = False
    db.session.commit()
    # buzzer event could be logged (frontend triggers buzzer via device state change or ESP32 polls a 'buzz' flag)
    return jsonify({"message":"shift_ended","shift_id":s.id})

# GET active shift
@app.route("/api/shift/active", methods=["GET"])
def get_active_shift():
    s = Shift.query.filter_by(active=True).first()
    if not s:
        return jsonify({"active": False})
    return jsonify({"active": True, "shift": {"id": s.id, "name": s.name, "started_at": s.started_at.isoformat()}})

# HISTORY
@app.route("/api/shift/history", methods=["GET"])
def shift_history():
    rows = Shift.query.order_by(desc(Shift.started_at)).limit(200).all()
    out = []
    for s in rows:
        counts = {"small":0,"medium":0,"large":0, "total":0}
        for e in s.objectevent_set if hasattr(s,'objectevent_set') else s.events:
            counts[e.size_cat] = counts.get(e.size_cat,0)+1
            counts["total"] += 1
        out.append({
            "id": s.id,
            "name": s.name,
            "started_at": s.started_at.isoformat(),
            "ended_at": s.ended_at.isoformat() if s.ended_at else None,
            "counts": counts
        })
    return jsonify(out)

# OBJECT EVENT POST (from ESP32)
@app.route("/api/object_event", methods=["POST"])
@require_api_key
def object_event():
    content = request.json or {}
    size_cat = content.get("size_cat")
    length_est = float(content.get("length_est", 0.0))
    s = Shift.query.filter_by(active=True).first()
    shift_id = s.id if s else None
    ev = ObjectEvent(size_cat=size_cat, length_est=length_est, shift_id=shift_id)
    db.session.add(ev)
    db.session.commit()
    return jsonify({"message":"stored","shift_id": shift_id})

# DEVICE STATE GET (ESP32 polls)
@app.route("/api/device_state", methods=["GET"])
def get_device_state():
    ds = DeviceState.query.first()
    return jsonify({
        "motor_on": ds.motor_on,
        "turn_led_on": ds.turn_led_on,
        "box_full": ds.box_full,
        "last_update": ds.last_update.isoformat() if ds.last_update else None
    })

# DEVICE STATE POST (from frontend/app to change motor)
@app.route("/api/device_state", methods=["POST"])
@require_api_key
def set_device_state():
    content = request.json or {}
    ds = DeviceState.query.first()
    if "motor_on" in content:
        ds.motor_on = bool(content["motor_on"])
    if "turn_led_on" in content:
        ds.turn_led_on = bool(content["turn_led_on"])
    if "box_full" in content:
        ds.box_full = bool(content["box_full"])
    ds.last_update = datetime.utcnow()
    db.session.commit()
    return jsonify({"message":"updated", "motor_on": ds.motor_on})

# CURRENT COUNTS for active shift
@app.route("/api/counts/current", methods=["GET"])
def current_counts():
    s = Shift.query.filter_by(active=True).first()
    if not s:
        return jsonify({"active": False, "counts": {"small":0,"medium":0,"large":0,"total":0}})
    counts = {"small":0,"medium":0,"large":0,"total":0}
    events = ObjectEvent.query.filter_by(shift_id=s.id).all()
    for e in events:
        counts[e.size_cat] = counts.get(e.size_cat,0)+1
        counts["total"] += 1
    return jsonify({"active": True, "shift_id": s.id, "counts": counts})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT",5000)), debug=True)
