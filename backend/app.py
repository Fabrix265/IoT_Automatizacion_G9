from flask import Flask
from flask_cors import CORS
from config import Config
from routes import api
from models import db

app = Flask(__name__)
app.config.from_object(Config)
CORS(app)

db.init_app(app)

with app.app_context():
    db.create_all()

app.register_blueprint(api)

@app.route('/')
def home():
    return {"message": "IoT Backend funcionando correctamente 🚀"}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
