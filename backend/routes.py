from flask import Blueprint, request, jsonify, current_app
from models import db, DeviceState

api = Blueprint('api', __name__)

@api.route('/update', methods=['POST'])
def update_state():
    data = request.get_json()
    key = request.headers.get("x-api-key")

    if key != current_app.config["API_KEY"]:
        return jsonify({"error": "Unauthorized"}), 401

    new_state = DeviceState(
        motor=data.get('motor', False),
        turnLed=data.get('turnLed', False),
        boxFull=data.get('boxFull', False)
    )
    db.session.add(new_state)
    db.session.commit()
    return jsonify({"message": "Estado actualizado"}), 200

@api.route('/latest', methods=['GET'])
def latest_state():
    last = DeviceState.query.order_by(DeviceState.timestamp.desc()).first()
    if last:
        return jsonify({
            "motor": last.motor,
            "turnLed": last.turnLed,
            "boxFull": last.boxFull,
            "timestamp": last.timestamp
        })
    return jsonify({"message": "No hay datos aún"})
