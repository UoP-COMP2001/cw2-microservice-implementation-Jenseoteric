from datetime import date, timedelta

from flask import abort, make_response

from auth import current_user, login_required
from config import db
from models import Plan, Subscription, subscription_schema, subscriptions_schema


def _may_touch(user, subscription):
    #admins get everything, everyone else only their own rows
    return user.Role == "Administrator" or subscription.UserID == user.UserID


@login_required
def read_all():
    user = current_user()
    if user.Role == "Administrator":
        results = Subscription.query.all()
    else:
        results = Subscription.query.filter(Subscription.UserID == user.UserID).all()
    return subscriptions_schema.dump(results)


@login_required
def read_one(subscription_id):
    subscription = db.session.get(Subscription, subscription_id)
    if subscription is None:
        abort(404, f"No subscription with id {subscription_id}")

    if not _may_touch(current_user(), subscription):
        abort(403, "You can only view your own subscriptions")

    return subscription_schema.dump(subscription)


@login_required
def create(body):
    user = current_user()
    plan = db.session.get(Plan, body.get("PlanID"))
    if plan is None:
        abort(404, "That plan does not exist")

    #an admin can set someone else up, a normal user only themselves
    target_user_id = body.get("UserID", user.UserID)
    if target_user_id != user.UserID and user.Role != "Administrator":
        abort(403, "You can only subscribe yourself")

    existing = Subscription.query.filter(
        Subscription.UserID == target_user_id,
        Subscription.SubscriptionStatus == "Active",
    ).one_or_none()
    if existing is not None:
        abort(409, "This user already has an active subscription")

    start = date.today()
    #seven days free, off the compare plans page. free plan gets none since
    #there is nothing to charge for
    trial_end = None if plan.Price == 0 else start + timedelta(days=7)

    subscription = Subscription(
        UserID=target_user_id,
        PlanID=plan.PlanID,
        StartDate=start,
        TrialEndDate=trial_end,
        SubscriptionStatus="Active",
        AutoRenew=body.get("AutoRenew", True),
    )
    db.session.add(subscription)
    db.session.commit()
    #the trigger writes the log row, not this

    return subscription_schema.dump(subscription), 201


@login_required
def update(subscription_id, body):
    subscription = db.session.get(Subscription, subscription_id)
    if subscription is None:
        abort(404, f"No subscription with id {subscription_id}")

    if not _may_touch(current_user(), subscription):
        abort(403, "You can only change your own subscriptions")

    for field in ("PlanID", "SubscriptionStatus", "EndDate", "AutoRenew"):
        if field in body:
            setattr(subscription, field, body[field])

    #setting Cancelled here doesnt do anything to EndDate, they are separate
    #columns. so a cancelled row can still have a future end date on it, which
    #isnt right but sorting it out properly means deciding whether cancelling
    #ends it now or at the end of the billing period

    db.session.commit()
    return subscription_schema.dump(subscription), 200


@login_required
def delete(subscription_id):
    subscription = db.session.get(Subscription, subscription_id)
    if subscription is None:
        abort(404, f"No subscription with id {subscription_id}")

    if not _may_touch(current_user(), subscription):
        abort(403, "You can only delete your own subscriptions")

    db.session.delete(subscription)
    db.session.commit()

    return make_response(f"Subscription {subscription_id} deleted", 200)


#what this looked like before:

# def read_all():
#     return subscriptions_schema.dump(Subscription.query.all())
#every user could see every subscription. i had the role column sat there doing
#nothing until i went back and used it

# if body["UserID"]:
#threw a KeyError when the field wasnt sent at all, .get() with a default was
#the fix