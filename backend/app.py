from flask import Flask, jsonify
from flask_cors import CORS
from config import Config
from models import db
from routes import api
import os

def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)
    CORS(app)
    db.init_app(app)

    with app.app_context():
        # crea tablas si no existen
        db.create_all()

    # registrar blueprint con prefijo /api
    app.register_blueprint(api, url_prefix='/api')

    @app.route('/')
    def home():
        return {"message": "IoT Backend funcionando correctamente 🚀"}

    return app

app = create_app()

if __name__ == '__main__':
    debug = os.environ.get("FLASK_DEBUG", "1") == "1"
    app.run(host='0.0.0.0', port=int(os.environ.get("PORT", 5000)), debug=debug)
