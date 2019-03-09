#!/bin/bash

set -o pipefail
set -o errexit
set -o errtrace
# set -o xtrace

BACKUP_DIR=${BACKUP_DIR:-"/backup"}
BOTO_CONFIG_PATH=${BOTO_CONFIG_PATH:-"/root/.boto"}
MONGODB_HOST=${MONGODB_HOST:-"localhost"}
MONGODB_PORT=${MONGODB_PORT:-"27017"}
BACKUP_PREFIX=${BACKUP_PREFIX:-"backup"}

backup() {
  mkdir -p ${BACKUP_DIR}
  date=$(date "+%Y-%m-%dT%H:%M:%SZ")
  archive_name="${BACKUP_PREFIX}-${date}.gz"

  cmd_auth_part=""
  if [[ -n ${MONGODB_USERNAME} ]] && [[ -n ${MONGODB_PASSWORD} ]]
  then
    cmd_auth_part="--username=\"${MONGODB_USERNAME}\" --password=\"${MONGODB_PASSWORD}\""
  fi

  cmd_db_part=""
  if [[ -n ${DATABASE_NAME} ]]
  then
    cmd_db_part="--db=\"${DATABASE_NAME}\""
  fi

  if [[ -n ${MONGODB_REPLICASET} ]]
  then
    MONGODB_HOST=${MONGODB_REPLICASET}/${MONGODB_HOST}
  fi

  cmd="mongodump --host=\"${MONGODB_HOST}\" --port=\"${MONGODB_PORT}\" ${cmd_auth_part} ${cmd_db_part} ${EXTRA_OPTS} --gzip --archive=${BACKUP_DIR}/${archive_name}"
  echo "starting to backup MongoDB host=${MONGODB_HOST} port=${MONGODB_PORT} using ${cmd}"
  eval "$cmd"
}

upload_to_gcs() {
  if [[ ! "$GCS_BUCKET" =~ gs://* ]]; then
    GCS_BUCKET="gs://${GCS_BUCKET}"
  fi

  if [[ -n ${GCS_KEY_FILE_PATH} ]]
  then
cat <<EOF > ${BOTO_CONFIG_PATH}
[Credentials]
gs_service_key_file = ${GCS_KEY_FILE_PATH}
[Boto]
https_validate_certificates = True
[GoogleCompute]
[GSUtil]
content_language = en
default_api_version = 2
[OAuth2]
EOF
  fi
  echo "uploading backup archive to GCS bucket=${GCS_BUCKET}"
  gsutil cp ${BACKUP_DIR}/${archive_name} ${GCS_BUCKET}
}

send_slack_message() {
  local color=${1}
  local title=${2}
  local message=${3}

  echo 'Sending to '${SLACK_CHANNEL}'...'
  curl --silent --data-urlencode \
    "$(printf 'payload={"channel": "%s", "username": "%s", "link_names": "true", "icon_emoji": "%s", "attachments": [{"author_name": "mongodb-gcs-backup", "title": "%s", "text": "%s", "color": "%s"}]}' \
        "${SLACK_CHANNEL}" \
        "${SLACK_USERNAME}" \
        "${SLACK_ICON}" \
        "${title}" \
        "${message}" \
        "${color}" \
    )" \
    ${SLACK_WEBHOOK_URL} || true
  echo
}

err() {
  err_msg="Something went wrong on line $(caller)"
  echo ${err_msg} >&2
  if [[ ${SLACK_ALERTS} == "true" ]]
  then
    send_slack_message "danger" "Error while performing mongodb backup" "${err_msg}"
  fi
}

cleanup() {
  rm -f ${BACKUP_DIR}/${archive_name}
}

trap err ERR
backup
upload_to_gcs
cleanup
echo "backup done!"
