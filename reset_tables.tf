variable "gcp_project_id" {
  type = string
}

resource "google_bigquery_job" "load_tables" {
  for_each = toset([
    "pool_estimates",
    "accepted_with_deposit",
    "denied_estimates",
    "scheduled_installations",
    "completed_pools",
    "paid_and_closed"
  ])

  project  = var.gcp_project_id
  job_id   = "load_${each.value}_${formatdate("YYYYMMDDHHmmss", timestamp())}"
  location = "US"

  load {
    source_uris = [
      "gs://${var.gcp_project_id}-bucket/${each.value}.csv"
    ]

    destination_table {
      project_id = var.gcp_project_id
      dataset_id = "pool_data"
      table_id   = each.value
    }

    autodetect         = true
    source_format      = "CSV"
    skip_leading_rows  = 1
    write_disposition  = "WRITE_TRUNCATE"
    create_disposition = "CREATE_IF_NEEDED"
  }
}
