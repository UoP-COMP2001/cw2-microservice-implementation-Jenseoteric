from flask import render_template

import config
from models import Plan
import uvicorn

#routes have to go on the flask app underneath, not on the connexion wrapper
flask_app = config.connex_app.app
app = config.connex_app


@flask_app.route("/")
def home():
    plans = Plan.query.all()
    return render_template("home.html", plans=plans)


if __name__ == "__main__":
    #the app object is passed straight in rather than as the string "app:app", which was the source of much frustration.
    #an import string makes uvicorn re-import this file, which registers the
    # route a second time and throws "view function mapping is overwriting an
    #existing endpoint". passing the object means no reload, which is fine
    uvicorn.run(app, host="0.0.0.0", port=8000)


#things i tried first that failed, kept to show how i got here
#app = config.connex_app.middleware
#this got /api/ui working but made / return 404. .middleware is an inner
#layer of the asgi stacj, so unmatched paths never fall through to flask

# app.run(f"{Path(__file__).stem}:app", host="0.0.0.0", port=8000, reload=True)
#connexion 3s run() doesnt take host and port like connexion 2 did, so this
#just exited silently. reload also spawned a second process that re-ran
#add_api and caused "/api already registered"

#i tried to take much help from the labs, but the coursework is a little older now
#meaning there were simply syntax and compatability issues across the baord that made me sink
#a lot of time into bugfixing/troubleshooting

# app.add_api(config.basedir / "swagger.yml")
#moved into config.py instead, because leaving it here meant it ran twice
#when uvicorn imported the module again
