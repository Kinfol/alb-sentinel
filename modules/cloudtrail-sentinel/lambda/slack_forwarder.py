import json
import os
import urllib.request


def handler(event, context):
    webhook_url = os.environ["SLACK_WEBHOOK_URL"]

    for record in event["Records"]:
        message = record["Sns"]["Message"]
        subject = record["Sns"].get("Subject", "CloudTrail Sentinel Alert")

        payload = json.dumps({
            "text": f":rotating_light: *{subject}*\n{message}"
        })

        req = urllib.request.Request(
            webhook_url,
            data=payload.encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(req)

    return {"statusCode": 200}
