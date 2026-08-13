from datetime import datetime, timedelta, timezone
from functools import wraps

import bcrypt
import jwt
import requests
from flask import request, abort

from config import AUTH_API_URL, app, db
from models import User

TOKEN_HOURS = 3


def verify_with_authenticator(username, email, password):
    #Asks the university Authenticator API whether these credentials are valid
    try:
        response = requests.post(
            AUTH_API_URL,
            json={"username": username, "email": email, "password": password},
            timeout=10,
        )
    except requests.RequestException:
        return False   # if the authenticator cant be reached i treat it as a
                       # failed login rather than letting anyone through

    if response.status_code != 200:
        return False

    body = response.json()
    return isinstance(body, list) and "True" in [str(v) for v in body]


def hash_password(plain):
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt()).decode()


def check_password(plain, hashed):
    return bcrypt.checkpw(plain.encode(), hashed.encode())


def issue_token(user):
    payload = {
        "sub": str(user.UserID),
        "username": user.Username,
        "role": user.Role,
        "exp": datetime.now(timezone.utc) + timedelta(hours=TOKEN_HOURS),
    }
    return jwt.encode(payload, app.config["JWT_SECRET"], algorithm="HS256")


def current_user():
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    try:
        payload = jwt.decode(header[7:], app.config["JWT_SECRET"], algorithms=["HS256"])
    except jwt.PyJWTError:
        return None   # covers expired, tampered and malformed tokens alike
    return db.session.get(User, int(payload["sub"]))


def decode_token(token):
    try:
        payload = jwt.decode(token, app.config["JWT_SECRET"], algorithms=["HS256"])
    except jwt.PyJWTError:
        return None
    return {"sub": payload["sub"], "role": payload["role"]}

#old
# def current_user(token):
#     header = request.headers.get("Authorization", "")
#     ...
#   one function doing both jobs. connexion calls the security function with the
#   token as an argument, so this threw "missing 1 required positional argument".
#   giving it the token parameter then broke login_required, which calls it with
#   none. they are two different questions asked in two different layers, so they
#   ended up as two functions

# def decode_token(token):
#     except jwt.PyJWTError:
#         abort(401, "Invalid or expired token")
#   flask's abort needs a request context too, so this swapped one 500 for
#   another. returning None is the right way to reject a token here


def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        user = current_user()
        if user is None:
            abort(401, "A valid token is required")
        return f(*args, **kwargs)
    return wrapper


def admin_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        user = current_user()
        if user is None:
            abort(401, "A valid token is required")
        if user.Role != "Administrator":
            abort(403, "Administrator role required")
        return f(*args, **kwargs)
    return wrapper


# endpoint handlers


def register(body):
    #Makes a local account, but only for someone the Authenticator knows about.
    #The Authenticator has no way to create an identity, only to check one, so
    #this deliberately cant sign up anyone new. 
    
    
    username = body.get("username")
    email = body.get("email")
    password = body.get("password")

    if not verify_with_authenticator(username, email, password):
        abort(401, "The Authenticator API did not verify these credentials")

    if User.query.filter(User.Email == email).one_or_none() is not None:
        abort(409, "An account already exists for this email")

    user = User(
        Username=username,
        Email=email,
        PasswordHash=hash_password(password),   # hashed, never stored plainly
        Role="User",
    )
    db.session.add(user)
    db.session.commit()
    # the database trigger writes the UserLog row, i dont do it here

    return {"UserID": user.UserID, "Username": user.Username, "Role": user.Role}, 201


def login(body):
    #checks externally, then hands back a token this service will accept
    username = body.get("username")
    email = body.get("email")
    password = body.get("password")

    if not verify_with_authenticator(username, email, password):
        abort(401, "Invalid credentials")

    user = User.query.filter(User.Email == email).one_or_none()
    if user is None:
        abort(404, "Verified, but no account exists here yet. Register first.")

    return {"token": issue_token(user), "expires_in_hours": TOKEN_HOURS}
