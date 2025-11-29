from flask import Blueprint, request, jsonify, current_app, send_file
from models import db, DeviceState, ObjectEvent, Shift
from utils import require_api_key
from datetime import datetime, timedelta
from io import BytesIO
import pandas as pd
from fpdf import FPDF

api = Blueprint('api', __name__)

def _apply_shift_filters(query):
    """Aplica filtros comunes (start_date, end_date, q) a una query SQLAlchemy de Shift."""
    q = request.args.get('q')
    start = request.args.get('start_date')
    end = request.args.get('end_date')

    if start:
        try:
            start_dt = datetime.fromisoformat(start)
            query = query.filter(Shift.start_at >= start_dt)
        except Exception:
            pass

    if end:
        try:
            # hacer inclusive la fecha final si solo es YYYY-MM-DD
            if len(end) == 10:
                end_dt = datetime.fromisoformat(end) + timedelta(days=1)
            else:
                end_dt = datetime.fromisoformat(end)
            query = query.filter(Shift.start_at < end_dt)
        except Exception:
            pass

    if q:
        # ilike para búsqueda case-insensitive
        query = query.filter(Shift.name.ilike(f"%{q}%"))

    return query

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

    # -------------------------------------------
    # 🛑 VALIDACIÓN: no motor sin turno activo
    # -------------------------------------------
    shift = Shift.query.filter_by(end_at=None).order_by(Shift.start_at.desc()).first()

    if motor_on is True and not shift:
        return jsonify({
            "error": "No se puede activar el motor sin turno activo",
            "motor_on": False
        }), 400

    # Obtener último estado
    last = DeviceState.query.order_by(DeviceState.timestamp.desc()).first()

    new_state = DeviceState(
        motor_on = motor_on if motor_on is not None else (last.motor_on if last else False),
        turn_led_on = turn_led_on if turn_led_on is not None else (last.turn_led_on if last else False),
        box_full = box_full if box_full is not None else (last.box_full if last else False)
    )

    db.session.add(new_state)
    db.session.commit()

    return jsonify({"message": "Device state updated"}), 200


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
    # cerrar cualquier shift abierto
    open_shifts = Shift.query.filter_by(end_at=None).all()
    for s in open_shifts:
        s.end_at = datetime.utcnow()
    new_shift = Shift(name=name)
    db.session.add(new_shift)
    db.session.commit()
    # Opcional: encender turn LED
    ds = DeviceState(motor_on=False, turn_led_on=True, box_full=False)
    db.session.add(ds)
    db.session.commit()
    return jsonify({"message":"shift started","shift": new_shift.as_dict()}), 200

@api.route('/shift/end', methods=['POST'])
@require_api_key
def shift_end():
    shift = Shift.query.filter_by(end_at=None).order_by(Shift.start_at.desc()).first()
    if not shift:
        return jsonify({"message": "No active shift"}), 404

    # cerrar el turno
    shift.end_at = datetime.utcnow()
    db.session.add(shift)

    # APAGAR motor y LED automáticamente
    ds = DeviceState(
        motor_on=False,
        turn_led_on=False,
        box_full=False
    )
    db.session.add(ds)

    db.session.commit()

    return jsonify({
        "message":"shift ended",
        "shift": shift.as_dict()
    }), 200


@api.route('/shift/history', methods=['GET'])
@require_api_key
def shift_history():
    query = Shift.query
    query = _apply_shift_filters(query)
    shifts = query.order_by(Shift.start_at.desc()).limit(1000).all()
    return jsonify([s.as_dict() for s in shifts]), 200

# -------------------------
# STATS para gráficos
# -------------------------
@api.route('/shift/stats', methods=['GET'])
@require_api_key
def shift_stats():
    query = Shift.query
    query = _apply_shift_filters(query)
    shifts = query.order_by(Shift.start_at.desc()).limit(100).all()

    labels = []
    totals = []
    for s in reversed(shifts):  # orden ascendente para el chart
        start_label = s.start_at.strftime("%Y-%m-%d %H:%M")
        labels.append(f"{s.name} ({start_label})")
        totals.append(s.counts_total or 0)

    return jsonify({"labels": labels, "totals": totals}), 200

# ---------------------------------------------------
# EXPORTAR HISTORIAL A EXCEL (acepta filtros)
# ---------------------------------------------------
@api.route('/shift/export/excel', methods=['GET'])
@require_api_key
def export_excel():
    query = Shift.query
    query = _apply_shift_filters(query)
    shifts = query.order_by(Shift.start_at.desc()).all()

    rows = []
    for s in shifts:
        rows.append({
            "ID": s.id,
            "Nombre": s.name,
            "Inicio": s.start_at.isoformat(),
            "Fin": s.end_at.isoformat() if s.end_at else "",
            "Total": s.counts_total,
            "Pequeños": s.counts_small,
            "Medianos": s.counts_medium,
            "Grandes": s.counts_large
        })
    
    df = pd.DataFrame(rows)
    output = BytesIO()
    df.to_excel(output, index=False, engine='openpyxl')
    output.seek(0)

    return send_file(output, as_attachment=True,
                     download_name="historial_turnos.xlsx",
                     mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")


# ---------------------------------------------------
# EXPORTAR HISTORIAL A PDF (acepta filtros)
# ---------------------------------------------------
@api.route('/shift/export/pdf', methods=['GET'])
@require_api_key
def export_pdf():
    query = Shift.query
    query = _apply_shift_filters(query)
    shifts = query.order_by(Shift.start_at.desc()).all()

    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Arial", size=12)

    pdf.cell(0, 10, txt="Historial de Turnos", ln=True, align='C')
    pdf.ln(4)

    for s in shifts:
        pdf.cell(0, 8, txt=f"ID: {s.id}  |  {s.name}", ln=True)
        inicio_str = s.start_at.strftime("%Y-%m-%d %H:%M:%S")
        fin_str = s.end_at.strftime("%Y-%m-%d %H:%M:%S") if s.end_at else "En curso"
        pdf.cell(0, 8, txt=f"Inicio: {inicio_str}  -  Fin: {fin_str}", ln=True)
        pdf.cell(0, 8, txt=f"Total: {s.counts_total}  Peq:{s.counts_small}  Med:{s.counts_medium}  Gra:{s.counts_large}", ln=True)
        pdf.ln(4)

    pdf_output = pdf.output(dest='S')
    if isinstance(pdf_output, str):
        pdf_bytes = pdf_output.encode('latin-1')
    else:
        pdf_bytes = pdf_output
    
    output = BytesIO(pdf_bytes)
    output.seek(0)

    return send_file(output, as_attachment=True,
                     download_name="historial_turnos.pdf",
                     mimetype="application/pdf")