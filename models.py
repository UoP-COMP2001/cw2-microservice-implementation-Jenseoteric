from config import db, ma

# every model sets the schema explicitly. without __table_args__ sqlalchemy
# defaults to dbo and the tables land in the wrong place, which the module
# leader specifically warned about


class User(db.Model):
    __tablename__ = "User"
    __table_args__ = {"schema": "RCW2", "implicit_returning": False} # cancelling subscriptions and adding them was broken before adding implicitreturning

    UserID = db.Column(db.Integer, primary_key=True)
    Username = db.Column(db.Unicode(50), nullable=False, unique=True)
    Email = db.Column(db.Unicode(255), nullable=False, unique=True)
    PasswordHash = db.Column(db.String(255), nullable=False)
    Role = db.Column(db.Unicode(20), nullable=False, default="User")

    subscriptions = db.relationship("Subscription", back_populates="user")


class Plan(db.Model):
    __tablename__ = "Plan"
    __table_args__ = {"schema": "RCW2"}

    PlanID = db.Column(db.Integer, primary_key=True)
    PlanName = db.Column(db.Unicode(50), nullable=False, unique=True)
    Price = db.Column(db.Numeric(6, 2), nullable=False)
    BillingCycle = db.Column(db.Unicode(10), nullable=False)
    Description = db.Column(db.Unicode(255))

    subscriptions = db.relationship("Subscription", back_populates="plan")


class Feature(db.Model):
    __tablename__ = "Feature"
    __table_args__ = {"schema": "RCW2"}

    FeatureID = db.Column(db.Integer, primary_key=True)
    FeatureName = db.Column(db.Unicode(100), nullable=False, unique=True)


class PlanFeature(db.Model):
    __tablename__ = "PlanFeature"
    __table_args__ = {"schema": "RCW2"}

    #linked entity
    PlanID = db.Column(db.Integer, db.ForeignKey("RCW2.Plan.PlanID"), primary_key=True)
    FeatureID = db.Column(db.Integer, db.ForeignKey("RCW2.Feature.FeatureID"), primary_key=True)


class Subscription(db.Model):
    __tablename__ = "Subscription"
    __table_args__ = {"schema": "RCW2", "implicit_returning": False}

    SubscriptionID = db.Column(db.Integer, primary_key=True)
    UserID = db.Column(db.Integer, db.ForeignKey("RCW2.User.UserID"), nullable=False)
    PlanID = db.Column(db.Integer, db.ForeignKey("RCW2.Plan.PlanID"), nullable=False)
    StartDate = db.Column(db.Date, nullable=False)
    TrialEndDate = db.Column(db.Date)   # added in cw2, cw1 didnt have trials
    EndDate = db.Column(db.Date)
    SubscriptionStatus = db.Column(db.Unicode(10), nullable=False, default="Active")
    AutoRenew = db.Column(db.Boolean, nullable=False, default=True)

    user = db.relationship("User", back_populates="subscriptions")
    plan = db.relationship("Plan", back_populates="subscriptions")
    payments = db.relationship("Payment", back_populates="subscription")


class Payment(db.Model):
    __tablename__ = "Payment"
    __table_args__ = {"schema": "RCW2"}

    PaymentID = db.Column(db.Integer, primary_key=True)
    SubscriptionID = db.Column(db.Integer, db.ForeignKey("RCW2.Subscription.SubscriptionID"), nullable=False)
    PaymentDate = db.Column(db.DateTime)
    Amount = db.Column(db.Numeric(6, 2), nullable=False)
    PaymentMethod = db.Column(db.Unicode(20), nullable=False)
    PaymentStatus = db.Column(db.Unicode(10), nullable=False, default="Completed")

    subscription = db.relationship("Subscription", back_populates="payments")


class UserLog(db.Model):
    __tablename__ = "UserLog"
    __table_args__ = {"schema": "RCW2"}

    LogID = db.Column(db.Integer, primary_key=True)
    UserID = db.Column(db.Integer, db.ForeignKey("RCW2.User.UserID"))
    Username = db.Column(db.Unicode(50), nullable=False)
    Email = db.Column(db.Unicode(255), nullable=False)
    Role = db.Column(db.Unicode(20), nullable=False)
    DateLogged = db.Column(db.DateTime)


class SubscriptionLog(db.Model):
    __tablename__ = "SubscriptionLog"
    __table_args__ = {"schema": "RCW2"}

    LogID = db.Column(db.Integer, primary_key=True)
    SubscriptionID = db.Column(db.Integer, db.ForeignKey("RCW2.Subscription.SubscriptionID"))
    Username = db.Column(db.Unicode(50), nullable=False)
    PlanName = db.Column(db.Unicode(50), nullable=False)
    Price = db.Column(db.Numeric(6, 2), nullable=False)
    DateLogged = db.Column(db.DateTime)


#marshmallow schemas handle turning these objects into JSON and back


class UserSchema(ma.SQLAlchemyAutoSchema):
    class Meta:
        model = User
        load_instance = True
        sqla_session = db.session
        exclude = ("PasswordHash",)   # a hash should never leave the api


class PlanSchema(ma.SQLAlchemyAutoSchema):
    class Meta:
        model = Plan
        load_instance = True
        sqla_session = db.session


class SubscriptionSchema(ma.SQLAlchemyAutoSchema):
    class Meta:
        model = Subscription
        load_instance = False   # false so incoming JSON stays a plain dict and
                                # can be validated before anything is created
        sqla_session = db.session
        include_fk = True


class PaymentSchema(ma.SQLAlchemyAutoSchema):
    class Meta:
        model = Payment
        load_instance = False
        sqla_session = db.session
        include_fk = True


user_schema = UserSchema()
users_schema = UserSchema(many=True)
plan_schema = PlanSchema()
plans_schema = PlanSchema(many=True)
subscription_schema = SubscriptionSchema()
subscriptions_schema = SubscriptionSchema(many=True)
payment_schema = PaymentSchema()
payments_schema = PaymentSchema(many=True)
