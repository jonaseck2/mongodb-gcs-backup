# mongodb-gcs-backup

This project aims to provide a simple way to perform a MongoDB server/db backup using `mongo-tools` and to upload it to Google Cloud Storage. It was greatly inspired from [`takemetour/docker-mongodb-gcs-backup`](https://github.com/takemetour/docker-mongodb-gcs-backup).

We provide a kubernetes support thanks to the helm chart located in the `chart` folder of this repository.

## Docker Image

You can pull the public image from Docker Hub:

    docker pull jonaseck/mongodb-gcs-backup:latest

### Configuration

The following table lists the configurable parameters you can set up.

Environment Variable | Required | Default | Description
---------------------|----------|---------|-------------
`BACKUP_DIR`         | No  | `/tmp` | The path where the `mongodump` result will be temporarily stored.
`BACKUP_PREFIX`      | No  | `backup` | Prefix of the backup file name.
`BOTO_CONFIG_PATH`   | No  | `/root/.boto` | The path where `gsutil` will search for the boto configuration file.
`GCS_BUCKET`         | Yes |  | The bucket you want to upload the backup archive to.
`GCS_KEY_FILE_PATH`  | Yes |  | The location where the GCS serviceaccount key file will be mounted.
`MONGODB_HOST`       | No  | `localhost` | The MongoDB server host.
`MONGODB_PORT`       | No  | `27017` | The MongoDB port.
`DATABASE_NAME`      | No  |  | The database to backup. By default, a backup of all the databases will be performed.
`MONGODB_USERNAME`   | No  |  | The MongoDB user if any.
`MONGODB_PASSWORD`   | No  |  | The MongoDB password if any.
`MONGODB_REPLICASET` | No  |  | The MongoDB replicaset if any. Adds `--oplog` to `EXTRA_OPTS` unless set.
`EXTRA_OPTS`         | No  |  | Additional backup flags.
`SLACK_ALERTS`       | No  |  | `true` if you want to send Slack alerts in case of failure.
`SLACK_WEBHOOK_URL`  | No  |  | The Incoming WebHook URL to use to send the alerts.
`SLACK_CHANNEL`      | No  |  | The channel to send Slack messages to.
`SLACK_USERNAME`     | No  |  | The user to send Slack messages as.
`SLACK_ICON`         | No  |  | The Slack icon to associate to the user/message.

You can set all of these variables within your `values.yaml` file under the `env` dict key.

### Usage

#### Run Locally

You can run the script locally:

```
cd /path/to/mongodb-gcs-backup
chmod +x backup.sh
GCS_BUCKET=<gs://bucket_name> \
./backup.sh
```

Please note that you can set any environment variable described in the previous section! As an example, to enable the Slack alerts on failure:

```
SLACK_ALERTS=true \
SLACK_WEBHOOK_URL=<webhook_url> \
SLACK_CHANNEL=<slack_channel> \
SLACK_USERNAME=<slack_username> \
SLACK_ICON=<slack_icon> \
GCS_BUCKET=<gs://bucket_name> \
./backup.sh
```

#### Run within Kubernetes

##### Installing the Chart

To install the chart with the release name my-release within you Kubernetes cluster:

```
helm install --name my-release chart/mongodb-gcs-backup
```

The command deploys the chart on the Kubernetes cluster in the default namespace. The configuration section lists the parameters that can be configured during installation.

##### Uninstalling the Chart

To uninstall/delete the my-release deployment:

    helm delete my-release --purge

The command removes all the Kubernetes components associated with the chart and deletes the release.

### Authenticate with GCS

#### Using the gcloud CLI

If you are running the script locally, the easiest solution is to sign in to the google account associated with your Google Cloud Storage data:

    gcloud init --console-only

More information on how to setup gsutil locally [here](https://cloud.google.com/storage/docs/gsutil_install).

#### Using a Service Account Within Kubernetes

You can create a [service account](https://cloud.google.com/iam/docs/creating-managing-service-accounts) by executing the example below. The service account is granted access to the specific bucket only and a lifecycle to delete backups after 28 days is added.

To use the resulting JSON key file within Kubernetes you can create a secret from it by running the following command:

```
GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null)
BUCKET=gs://example-bucket
NAME=mongodb-gcs-backup
KEYNAME=credentials.json
SERVICE_ACCOUNT=${NAME}@${GCLOUD_PROJECT}.iam.gserviceaccount.com
gcloud iam service-accounts create ${NAME} --display-name "${NAME}" 2>/dev/null
gcloud iam service-accounts keys create ${KEYNAME} --iam-account=${SERVICE_ACCOUNT}
kubectl create secret generic ${NAME} --from-file ${KEYNAME}
rm -f ${KEYNAME}

gsutil mb -b off -c regional -l ${REGION} ${BUCKET}
gsutil defacl ch -u ${SERVICE_ACCOUNT}:O ${BUCKET}

cat << EOF > lifecycle.json
{
    "rule": [{
        "action": {
            "type": "Delete"
        },
        "condition": {
            "age": 28
        }
    }]
}
EOF
gsutil lifecycle set lifecycle.json ${BUCKET}
rm -f lifecycle.json
```

Then you will need to specify this secret name via the `--set secretName=<your_secret_name>` argument to the `helm install` command or by specifying it directly in your `values.yaml` file (by default, the secret name is set to `mongodb-gcs-backup`). The key file will be mounted by default under `/secrets/gcp/credentials.json` and the `GCS_KEY_FILE_PATH` variable should point to it.
