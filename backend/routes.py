from flask import Blueprint, request, jsonify, current_app
from models import db, DeviceState, ObjectEvent, Shift
from utils import require_api_key
from datetime import datetime

api = Blueprint('api', __name__)

# -------------------------
# Device state endpoints
# -------------------------
@api.route('/device_state', methods=['POST'])
@require_api_key
def post_device_state():
    data = request.get_json() or {}
    # Map payload keys used by ESP32 / frontend
    motor_on = data.get('motor_on') if 'motor_on' in data else data.get('motor', None)
    turn_led_on = data.get('turn_led_on') if 'turn_led_on' in data else data.get('turnLed', None)
    box_full = data.get('box_full') if 'box_full' in data else data.get('boxFull', None)

    # Si no vienen valores explícitos, no los sobreescribimos (opcional)
    last = DeviceState.query.order_by(DeviceState.timestamp.desc()).first()
    new_state = DeviceState(
        motor_on = motor_on if motor_on is not None else (last.motor_on if last else False),
        turn_led_on = turn_led_on if turn_led_on is not None else (last.turn_led_on if last else False),
        box_full = box_full if box_full is not None else (last.box_full if last else False)
    )
    db.session.add(new_state)
    db.session.commit()
    return jsonify({"message":"Device state updated"}), 200

@api.route('/device_state', methods=['GET'])
@require_api_key
def get_device_state():
    last = DeviceState.query.order_by(DeviceState.timestamp.desc()).first()
    if not last:
        return jsonify({"message":"No data yet"}), 404
    return jsonify({
        "motor_on": bool(last.motor_on),
        "turn_led_on": bool(last.turn_led_on),
        "box_full": bool(last.box_full),
        "timestamp": last.timestamp.isoformat()
    }), 200

# -------------------------
# Object events (ESP32 posts)
# -------------------------
@api.route('/object_event', methods=['POST'])
@require_api_key
def object_event():
    data = request.get_json() or {}
    size_cat = data.get('size_cat') or data.get('size') or 'unknown'
    length_est = float(data.get('length_est', 0.0))

    # Asignar al turno activo (el shift con end_at == None y más reciente)
    shift = Shift.query.filter_by(end_at=None).order_by(Shift.start_at.desc()).first()
    evt = ObjectEvent(size_cat=size_cat, length_est=length_est, shift=shift)
    db.session.add(evt)

    # actualizar contadores si hay shift activo
    if shift:
        shift.counts_total = (shift.counts_total or 0) + 1
        if size_cat == 'small':
            shift.counts_small = (shift.counts_small or 0) + 1
        elif size_cat == 'medium':
            shift.counts_medium = (shift.counts_medium or 0) + 1
        elif size_cat == 'large':
            shift.counts_large = (shift.counts_large or 0) + 1

    db.session.commit()
    return jsonify({"message":"event recorded", "shift_id": shift.id if shift else None}), 200

# -------------------------
# Counts endpoints
# -------------------------
@api.route('/counts/current', methods=['GET'])
@require_api_key
def counts_current():
    shift = Shift.query.filter_by(end_at=None).order_by(Shift.start_at.desc()).first()
    if not shift:
        # devolver ceros si no hay turno
        return jsonify({"counts":{"total":0,"small":0,"medium":0,"large":0}}), 200
    return jsonify({"counts": {
        "total": shift.counts_total or 0,
        "small": shift.counts_small or 0,
        "medium": shift.counts_medium or 0,
        "large": shift.counts_large or 0
    }}), 200

# -------------------------
# Shift endpoints
# -------------------------
@api.route('/shift/start', methods=['POST'])
@require_api_key
def shift_start():
    data = request.get_json() or {}
    name = data.get('name') or f"Turno {datetime.utcnow().isoformat()}"
    # cerrar cualquier shift abierto? -> por ahora permitimos uno a la vez: cerrar prev abiertos
    open_shifts = Shift.query.filter_by(end_at=None).all()
    for s in open_shifts:
        s.end_at = datetime.utcnow()
    new_shift = Shift(name=name)
    db.session.add(new_shift)
    db.session.commit()
    # Opcional: encender turn LED por crear device state
    ds = DeviceState(motor_on=False, turn_led_on=True, box_full=False)
    db.session.add(ds)
    db.session.commit()
    return jsonify({"message":"shift started","shift": new_shift.as_dict()}), 200

@api.route('/shift/end', methods=['POST'])
@require_api_key
def shift_end():
    # finalizar el shift activo más reciente
    shift = Shift.query.filter_by(end_at=None).order_by(Shift.start_at.desc()).first()
    if not shift:
        return jsonify({"message":"No active shift"}), 404
    shift.end_at = datetime.utcnow()
    db.session.add(shift)
    # apagar turn LED globalmente
    ds = DeviceState(motor_on=False, turn_led_on=False, box_full=False)
    db.session.add(ds)
    db.session.commit()
    # hacer sonar buzzer: el ESP32 leerá box_full o poll y detectará cambio; puedes notificar por otro endpoint si quieres.
    return jsonify({"message":"shift ended", "shift": shift.as_dict()}), 200

@api.route('/shift/history', methods=['GET'])
@require_api_key
def shift_history():
    shifts = Shift.query.order_by(Shift.start_at.desc()).limit(100).all()
    return jsonify([s.as_dict() for s in shifts]), 200
