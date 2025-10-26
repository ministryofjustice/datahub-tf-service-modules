# Replay Pipeline Step Function
module "replay_pipeline" {
  source = "../../step_function"

  enable_step_function = var.setup_replay_pipeline
  step_function_name   = var.replay_pipeline

  step_function_execution_role_arn = var.step_function_execution_role_arn

  definition = jsonencode(
    {
      "Comment" : "Replay Pipeline Step Function",
      "StartAt" : "Deactivate Archive Trigger",
      "States" : {
        "Deactivate Archive Trigger" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_trigger_activation_job,
            "Arguments" : {
              "--dwh.glue.trigger.name" : var.archive_job_trigger_name,
              "--dwh.glue.trigger.activate" : "false"
            }
          },
          "Next" : "Stop Archive Job"
        },
        "Stop Archive Job" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_stop_glue_instance_job,
            "Arguments" : {
              "--dwh.stop.glue.instance.job.name" : var.glue_archive_job
            }
          },
          "Next" : "Stop DMS Replication Task"
        },
        "Stop DMS Replication Task" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.stop_dms_task_job,
            "Arguments" : {
              "--dwh.dms.replication.task.id" : var.replication_task_id
            }
          },
          "Next" : "Check All Pending Files Have Been Processed"
        },
        "Check All Pending Files Have Been Processed" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_unprocessed_raw_files_check_job,
            "Arguments" : {
              "--dwh.orchestration.wait.interval.seconds" : tostring(var.processed_files_check_wait_interval_seconds),
              "--dwh.orchestration.max.attempts" : tostring(var.processed_files_check_max_attempts)
            }
          },
          "Next" : "Stop Glue Streaming Job"
        },
        "Stop Glue Streaming Job" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_stop_glue_instance_job,
            "Arguments" : {
              "--dwh.stop.glue.instance.job.name" : var.glue_reporting_hub_cdc_jobname
            }
          },
          "Next" : "Prepare Temp Reload Bucket Data"
        },
        "Prepare Temp Reload Bucket Data" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_s3_data_deletion_job,
            "Arguments" : {
              "--dwh.file.deletion.buckets" : var.s3_temp_reload_bucket_id,
              "--dwh.config.key" : var.domain
            }
          },
          "Next" : "Copy Curated Data to Temp-Reload Bucket"
        },
        "Copy Curated Data to Temp-Reload Bucket" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_s3_file_transfer_job,
            "Arguments" : {
              "--dwh.file.transfer.source.bucket" : var.s3_curated_bucket_id,
              "--dwh.file.transfer.destination.bucket" : var.s3_temp_reload_bucket_id,
              "--dwh.file.transfer.delete.copied.files" : "false",
              "--dwh.datastorage.retry.maxAttempts" : tostring(var.glue_s3_max_attempts),
              "--dwh.datastorage.retry.minWaitMillis" : tostring(var.glue_s3_retry_min_wait_millis),
              "--dwh.datastorage.retry.maxWaitMillis" : tostring(var.glue_s3_retry_max_wait_millis),
              "--dwh.config.s3.bucket" : var.s3_glue_bucket_id,
              "--dwh.config.key" : var.domain
            }
          },
          "Next" : "Switch Hive Tables for Prisons to Temp-Reload Bucket"
        },
        "Switch Hive Tables for Prisons to Temp-Reload Bucket" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_switch_prisons_hive_data_location_job,
            "Arguments" : {
              "--dwh.prisons.data.switch.target.s3.path" : "s3://${var.s3_temp_reload_bucket_id}",
              "--dwh.config.key" : var.domain
            }
          },
          "Next" : "Empty Structured and Curated Data"
        },
        "Empty Structured and Curated Data" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_s3_data_deletion_job,
            "Arguments" : {
              "--dwh.file.deletion.buckets" : "${var.s3_structured_bucket_id},${var.s3_curated_bucket_id}",
              "--dwh.config.key" : var.domain
            }
          },
          "Next" : "Archive Remaining Raw Files"
        },
        "Archive Remaining Raw Files" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_s3_file_transfer_job,
            "Arguments" : {
              "--dwh.file.transfer.source.bucket" : var.s3_raw_bucket_id,
              "--dwh.file.transfer.destination.bucket" : var.s3_raw_archive_bucket_id,
              "--dwh.file.transfer.delete.copied.files" : "true",
              "--dwh.datastorage.retry.maxAttempts" : tostring(var.glue_s3_max_attempts),
              "--dwh.datastorage.retry.minWaitMillis" : tostring(var.glue_s3_retry_min_wait_millis),
              "--dwh.datastorage.retry.maxWaitMillis" : tostring(var.glue_s3_retry_max_wait_millis),
              "--dwh.config.s3.bucket" : var.s3_glue_bucket_id,
              "--dwh.config.key" : var.domain
            }
          },
          "Next" : "Copy Archived Data to Raw Bucket"
        },
        "Copy Archived Data to Raw Bucket" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_s3_file_transfer_job,
            "Arguments" : {
              "--dwh.file.transfer.source.bucket" : var.s3_raw_archive_bucket_id,
              "--dwh.file.transfer.destination.bucket" : var.s3_raw_bucket_id,
              "--dwh.file.transfer.retention.period.amount" : "0",
              "--dwh.file.transfer.delete.copied.files" : "false",
              "--dwh.datastorage.retry.maxAttempts" : tostring(var.glue_s3_max_attempts),
              "--dwh.datastorage.retry.minWaitMillis" : tostring(var.glue_s3_retry_min_wait_millis),
              "--dwh.datastorage.retry.maxWaitMillis" : tostring(var.glue_s3_retry_max_wait_millis),
              "--dwh.config.s3.bucket" : var.s3_glue_bucket_id,
              "--dwh.config.key" : var.domain
            }
          },
          "Next" : "Start Glue Batch Job"
        },
        "Start Glue Batch Job" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_reporting_hub_batch_jobname,
            "Arguments" : {
              "--dwh.batch.load.fileglobpattern" : "{part-*.snappy.parquet,LOAD*parquet}",
              "--dwh.config.s3.bucket" : var.s3_glue_bucket_id,
              "--dwh.config.key" : var.domain
            }
          },
          "Next" : "Run Compaction Job on Structured Zone"
        },
        "Run Compaction Job on Structured Zone" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_maintenance_compaction_job,
            "Arguments" : {
              "--dwh.maintenance.root.path" : var.s3_structured_path,
              "--dwh.config.s3.bucket" : var.s3_glue_bucket_id,
              "--dwh.config.key" : var.domain
            },
            "NumberOfWorkers" : var.compaction_structured_num_workers,
            "WorkerType" : var.compaction_structured_worker_type
          },
          "Next" : "Run Vacuum Job on Structured Zone"
        },
        "Run Vacuum Job on Structured Zone" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_maintenance_retention_job,
            "Arguments" : {
              "--dwh.maintenance.root.path" : var.s3_structured_path,
              "--dwh.config.s3.bucket" : var.s3_glue_bucket_id,
              "--dwh.config.key" : var.domain
            },
            "NumberOfWorkers" : var.retention_structured_num_workers,
            "WorkerType" : var.retention_structured_worker_type
          },
          "Next" : "Run Compaction Job on Curated Zone"
        },
        "Run Compaction Job on Curated Zone" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_maintenance_compaction_job,
            "Arguments" : {
              "--dwh.maintenance.root.path" : var.s3_curated_path,
              "--dwh.config.s3.bucket" : var.s3_glue_bucket_id,
              "--dwh.config.key" : var.domain
            },
            "NumberOfWorkers" : var.compaction_curated_num_workers,
            "WorkerType" : var.compaction_curated_worker_type
          },
          "Next" : "Run Vacuum Job on Curated Zone"
        },
        "Run Vacuum Job on Curated Zone" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_maintenance_retention_job,
            "Arguments" : {
              "--dwh.maintenance.root.path" : var.s3_curated_path,
              "--dwh.config.s3.bucket" : var.s3_glue_bucket_id,
              "--dwh.config.key" : var.domain
            },
            "NumberOfWorkers" : var.retention_curated_num_workers,
            "WorkerType" : var.retention_curated_worker_type
          },
          "Next" : "Start Glue Streaming Job"
        },
        "Start Glue Streaming Job" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun",
          "Parameters" : {
            "JobName" : var.glue_reporting_hub_cdc_jobname,
            "Arguments" : {
              "--dwh.clean.cdc.checkpoint" : "true",
              "--dwh.config.s3.bucket" : var.s3_glue_bucket_id,
              "--dwh.config.key" : var.domain
            }
          },
          "Next" : "Check All Files Have Been Replayed"
        },
        "Check All Files Have Been Replayed" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_unprocessed_raw_files_check_job,
            "Arguments" : {
              "--dwh.orchestration.wait.interval.seconds" : tostring(var.processed_files_check_wait_interval_seconds),
              "--dwh.orchestration.max.attempts" : tostring(var.processed_files_check_max_attempts),
              "--dwh.allowed.s3.file.regex" : "\\d+-\\d+.parquet"
            }
          },
          "Next" : "Empty Raw Data"
        },
        "Empty Raw Data" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_s3_data_deletion_job,
            "Arguments" : {
              "--dwh.file.deletion.buckets" : var.s3_raw_bucket_id,
              "--dwh.config.key" : var.domain
            }
          },
          "Next" : "Resume DMS Replication Task"
        },
        "Resume DMS Replication Task" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::aws-sdk:databasemigration:startReplicationTask",
          "Parameters" : {
            "ReplicationTaskArn" : var.dms_replication_task_arn,
            "StartReplicationTaskType" : "resume-processing"
          },
          "Next" : "Switch Hive Tables for Prisons to Curated"
        },
        "Switch Hive Tables for Prisons to Curated" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_switch_prisons_hive_data_location_job,
            "Arguments" : {
              "--dwh.prisons.data.switch.target.s3.path" : "s3://${var.s3_curated_bucket_id}",
              "--dwh.config.key" : var.domain
            }
          },
          "Next" : "Reactivate Archive Trigger"
        },
        "Reactivate Archive Trigger" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_trigger_activation_job,
            "Arguments" : {
              "--dwh.glue.trigger.name" : var.archive_job_trigger_name,
              "--dwh.glue.trigger.activate" : "true"
            }
          },
          "Next" : "Empty Temp Reload Bucket Data"
        },
        "Empty Temp Reload Bucket Data" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun.sync",
          "Parameters" : {
            "JobName" : var.glue_s3_data_deletion_job,
            "Arguments" : {
              "--dwh.file.deletion.buckets" : var.s3_temp_reload_bucket_id,
              "--dwh.config.key" : var.domain
            }
          },
          "End" : true
        }
      }
    }
  )

  tags = var.tags

}