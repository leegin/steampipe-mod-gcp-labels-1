variable "prohibited_labels" {
  type        = list(string)
  description = "A list of prohibited labels to check for."
}

locals {
  prohibited_sql = <<EOT
    with analysis as (
      select
        self_link,
        array_agg(k) as prohibited_labels
      from
        __TABLE_NAME__,
        jsonb_object_keys(labels) as k,
        unnest($1::text[]) as prohibited_key
      where
        k = prohibited_key
      group by
        self_link
    )
    select
      r.self_link as resource,
      case
        when a.prohibited_labels <> array[]::text[] then 'alarm'
        else 'ok'
      end as status,
      case
        when a.prohibited_labels <> array[]::text[] then r.title || ' has prohibited labels: ' || array_to_string(a.prohibited_labels, ', ') || '.'
        else r.title || ' has no prohibited labels.'
      end as reason,
      __DIMENSIONS__
    from
      __TABLE_NAME__ as r
    full outer join
      analysis as a on a.self_link = r.self_link
  EOT
}

locals {
  prohibited_sql_project  = replace(local.prohibited_sql, "__DIMENSIONS__", "r.project")
  prohibited_sql_location = replace(local.prohibited_sql, "__DIMENSIONS__", "r.location, r.project")
}

benchmark "prohibited" {
  title    = "Prohibited"
  description = "Prohibited labels may contain sensitive, confidential, or otherwise unwanted data and should be removed."
  children = [
    control.compute_instance_prohibited,
    control.storage_bucket_prohibited,
  ]
}

control "compute_instance_prohibited" {
  title       = "Compute instances should not have prohibited labels"
  description = "Check if Compute instances have any prohibited labels."
  sql         = replace(local.prohibited_sql_location, "__TABLE_NAME__", "gcp_compute_instance")
  param "prohibited_labels" {
    default = var.prohibited_labels
  }
}

control "storage_bucket_prohibited" {
  title       = "Storage buckets should not have prohibited labels"
  description = "Check if Storage buckets have any prohibited labels."
  sql         = replace(local.prohibited_sql_location, "__TABLE_NAME__", "gcp_storage_bucket")
  param "prohibited_labels" {
    default = var.prohibited_labels
  }
}
