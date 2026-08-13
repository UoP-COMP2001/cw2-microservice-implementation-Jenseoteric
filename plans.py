from models import Plan, Feature, PlanFeature, plans_schema
from config import db


def read_all():
    #compare plans no token needed to view
    plans = Plan.query.all()
    output = plans_schema.dump(plans)

    for entry in output:
        rows = (
            db.session.query(Feature.FeatureName)
            .join(PlanFeature, PlanFeature.FeatureID == Feature.FeatureID)
            .filter(PlanFeature.PlanID == entry["PlanID"])
            .all()
        )
        entry["Features"] = [r[0] for r in rows]

    return output
