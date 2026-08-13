from flask import abort
from sqlalchemy import func

from auth import admin_required
from config import db
from models import Payment, Plan, Subscription


@admin_required
def revenue():
    #the admin backlog asks for a revenue dashboard. same grouping as the
    #vw_RevenueByPlan view in the sql, done here so it comes back as json.
    #failed and refunded rows are left out, only money that stayed in counts
    rows = (
        db.session.query(
            Plan.PlanName,
            Plan.BillingCycle,
            func.count(Payment.PaymentID),
            func.sum(Payment.Amount),
        )
        .join(Subscription, Subscription.SubscriptionID == Payment.SubscriptionID)
        .join(Plan, Plan.PlanID == Subscription.PlanID)
        .filter(Payment.PaymentStatus == "Completed")
        .group_by(Plan.PlanName, Plan.BillingCycle)
        .all()
    )

    return [
        {
            "PlanName": r[0],
            "BillingCycle": r[1],
            "PaymentsTaken": r[2],
            "TotalRevenue": float(r[3]),
        }
        for r in rows
    ]


@admin_required
def refund(payment_id):
    #the other admin story, sorting out a billing problem
    payment = db.session.get(Payment, payment_id)
    if payment is None:
        abort(404, f"No payment with id {payment_id}")

    if payment.PaymentStatus != "Completed":
        abort(409, "Nothing was taken, so there is nothing to refund")

    payment.PaymentStatus = "Refunded"
    db.session.commit()
    #the row stays and gets marked, it doesnt get deleted, so the history still
    #shows the money went out and came back

    return {"PaymentID": payment.PaymentID, "PaymentStatus": payment.PaymentStatus}