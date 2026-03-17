###############################################################################
# CloudTrail Sentinel — Locals (dynamic filter pattern builder)
###############################################################################

locals {
  catalog = jsondecode(file("${path.module}/event_catalog.json"))

  # Get all category keys per service (excluding metadata keys)
  _category_keys = { for svc, data in local.catalog : svc => [
    for k in keys(data) : k if !contains(["event_source", "arn_field"], k)
  ] }

  # Resolve tracked_services into flat event list with optional ARN scoping
  catalog_events = flatten([
    for ts in var.tracked_services : [
      for cat in(contains(ts.categories, "all") ? local._category_keys[ts.service] : ts.categories) : {
        event_source  = local.catalog[ts.service].event_source
        event_names   = local.catalog[ts.service][cat]
        arn_field     = lookup(local.catalog[ts.service], "arn_field", "")
        resource_arns = ts.resource_arns
      }
    ]
  ])

  # Merge catalog events + custom events (custom events have no ARN scoping)
  all_events = concat(
    local.catalog_events,
    [for ce in var.custom_events : {
      event_source  = ce.event_source
      event_names   = ce.event_names
      arn_field     = ""
      resource_arns = []
    }]
  )

  # Build CloudWatch metric filter clauses
  # When resource_arns is provided and arn_field exists, scope to those ARNs
  filter_clauses = flatten([
    for ev in local.all_events : [
      for name in ev.event_names : (
        length(ev.resource_arns) > 0 && ev.arn_field != ""
        ? join(" || ", [
          for arn in ev.resource_arns :
          "(($.eventSource = \"${ev.event_source}\") && ($.eventName = \"${name}\") && ($.${ev.arn_field} = \"${arn}\"))"
        ])
        : "(($.eventSource = \"${ev.event_source}\") && ($.eventName = \"${name}\"))"
      )
    ]
  ])

  # CloudWatch metric filter patterns have a 1024-char limit.
  # If the combined pattern fits, use one filter. Otherwise, one filter per clause.
  _combined_pattern = length(local.filter_clauses) > 0 ? "{ ${join(" || ", local.filter_clauses)} }" : ""

  filter_patterns = (
    length(local._combined_pattern) <= 1024
    ? { "0" = local._combined_pattern }
    : { for i, clause in local.filter_clauses : tostring(i) => "{ ${clause} }" }
  )

  # Notification channel flags
  enable_slack = var.notification_channels.slack_webhook_url != ""
}
