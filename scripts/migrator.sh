#!/bin/bash

SUCCESS_CODE=0
FAIL_CODE=99
AUTHORIZATION_ERROR_CODE=701
WP_TOOLKIT_ERROR_CODE=702
BASE_DIR="/home/jelastic/migrator"
RUN_LOG="${BASE_DIR}/migrator.log"
BACKUP_DIR="${BASE_DIR}/backup"
DB_BACKUP="db_backup.sql"
WEBROOT_DIR="/var/www/webroot/ROOT"
WP_CONFIG="${WEBROOT_DIR}/wp-config.php"
WP_ENV="${BASE_DIR}/.wpenv"
WP_PROJECTS_LIST_JSON="projects.json"
WP_PROJECTS_LIST="projects.list"
WP_CLI="${BASE_DIR}/wp"

trap "execResponse '${FAIL_CODE}' 'Please check the ${RUN_LOG} log file for details.'; exit 0" TERM
export TOP_PID=$$

[[ -d ${BACKUP_DIR} ]] && mkdir -p ${BACKUP_DIR}
[[ ! -f ${WP_ENV} ]] && touch ${WP_ENV}

log(){
  local message=$1
  local timestamp
  timestamp=`date "+%Y-%m-%d %H:%M:%S"`
  echo -e "[${timestamp}]: ${message}" >> ${RUN_LOG}
}

installWP_CLI(){
  curl -s -o ${WP_CLI} https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar  && chmod +x ${WP_CLI};
  echo "apache_modules:" > ${BASE_DIR}/wp-cli.yml;
  echo "  - mod_rewrite" >> ${BASE_DIR}/wp-cli.yml;
  ${WP_CLI} --info 2>&1;
}

installRemoteWP_CLI(){
  local remote_wp_cli_dir="jelastic/wp-cli"
  local get_remote_wp_cli="${SSH} \"command -v wp > /dev/null && {  echo 'true'; } || { echo 'false'; }\""
  local result=$(execSshReturn "${get_remote_wp_cli}" "Validate default WP-CLI on remote host")
  log "Default WP-CLI installation does not found. Installing custom WP-CLI to ${remote_wp_cli_dir} directory";
  local create_remote_dir="${SSH} \"[[ ! -d ${remote_wp_cli_dir} ]] && { mkdir -p ${remote_wp_cli_dir};} || { echo 'false';} \""
  local install_wp_cli="${SSH} \"curl -s -o ${remote_wp_cli_dir}/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar  && chmod +x ${remote_wp_cli_dir}/wp; \""
  local install_wp_cli_find="${SSH} \"${remote_wp_cli_dir}/wp package install wp-cli/find-command \""
  execSshAction "${create_remote_dir}" "Creating directory ${remote_wp_cli_dir} for WP-CLI on remote host"
  execSshAction "${install_wp_cli}" "Installing custom WP-CLI to ${remote_wp_cli_dir} directory"
  execSshAction "${install_wp_cli_find}" "Installing wp-cli/find-command extension for WP-CLI"
  local wp_cli="${remote_wp_cli_dir}/wp"
  local validate_remote_wp_cli="${SSH} \"${wp_cli} --info 2>&1;\""
  execSshAction "${validate_remote_wp_cli}" "Validating WP-CLI om remote host"
  echo ${wp_cli}
}

execResponse(){
  local result=$1
  local message=$2
  local output_json="{\"result\": ${result}, \"out\": \"${message}\"}"
  echo $output_json
}

execAction(){
  local action="$1"
  local message="$2"
  stdout=$( { ${action}; } 2>&1 ) && { log "${message}...done";  } || {
    log "${message}...failed\n${stdout}\n";
    kill -s TERM $TOP_PID;
  }
}

execReturn(){
  local action="$1"
  local message="$2"
  stdout=$( { ${action}; } 2>&1 ) && { echo ${stdout}; log "${message}...done";  } || {
    log "${message}...failed\n${stdout}\n";
    kill -s TERM $TOP_PID;
  }
}

execSshAction(){
  local action="$1"
  local message="$2"
  action_to_base64=$(echo $action|base64 -w 0)
  stderr=$( { sh -c "$(echo ${action_to_base64}|base64 -d)"; } 2>&1 ) && { log "${message}...done"; } || {
    log "${message}...failed\n${stdout}\n";
    kill -s TERM $TOP_PID;
  }
}

execSshReturn(){
  local action="$1"
  local message="$2"
  local result=${FAIL_CODE}
  action_to_base64=$(echo $action|base64 -w 0)
  stdout=$( { sh -c "$(echo ${action_to_base64}|base64 -d)"; } 2>&1 ) && { echo ${stdout}; log "${message}...done"; } || {
    log "${message}...failed\n${stdout}\n";
    kill -s TERM $TOP_PID;
  }
}

getWPtoolkitVersion(){
  local command1="${SSH} \"wp-toolkit --list >/dev/null\""
  local command2="${SSH} \"plesk ext wp-toolkit --list >/dev/null\""
  local message="Checking WP Toolkit on remote host"
  action_to_base64=$(echo $command1|base64 -w 0)
  stdout=$( { sh -c "$(echo ${action_to_base64}|base64 -d)"; } 2>&1 ) && { log "${message}...done"; wp_toolkit="wp-toolkit"; }
  action_to_base64=$(echo $command2|base64 -w 0)
  stdout=$( { sh -c "$(echo ${action_to_base64}|base64 -d)"; } 2>&1 ) && { log "${message}...done"; wp_toolkit="plesk ext wp-toolkit"; }
  echo $wp_toolkit;
}

getRemoteProjectListWPT(){
  source ${WP_ENV}
#  local generateProjectlist="${SSH} \"${WPT} --list > ${WP_PROJECTS_LIST} \""
  local generateProjectlistJson="${SSH} \"${WPT} --list -format json > ${WP_PROJECTS_LIST_JSON} \""
#  local getProjectlist="sshpass -p ${SSH_PASSWORD} scp -P ${SSH_PORT} ${SSH_USER}@${SSH_HOST}:${WP_PROJECTS_LIST} ${BASE_DIR}/${WP_PROJECTS_LIST}"
  local getProjectlistJson="sshpass -p ${SSH_PASSWORD} scp -P ${SSH_PORT} ${SSH_USER}@${SSH_HOST}:${WP_PROJECTS_LIST_JSON} ${BASE_DIR}/${WP_PROJECTS_LIST_JSON}"
  local validateProjectlist="json_verify < ${BASE_DIR}/${WP_PROJECTS_LIST_JSON}"
#  execSshAction "${generateProjectlist}" "Generate projects list on remote host by wp-toolkit"
  execSshAction "${generateProjectlistJson}" "Generate projects list in JSON format on remote host by wp-toolkit"
#  execAction "${getProjectlist}" "Download projects list"
  execAction "${getProjectlistJson}" "Download projects list in JSON format"
#  execAction "${validateProjectlist}" "Validate JSON format forprojects list ${BASE_DIR}/${WP_PROJECTS_LIST_JSON}"
}


getRemoteProjectListWP_CLI(){
  _getRemoteSiteUrl() {
    local remote_path=$1
    local getRemoteSiteUrl="${SSH} \"${REMOTE_WP_CLI} option get siteurl --path=${remote_path} \""
    local remote_siteurl=$(execSshReturn "${getRemoteSiteUrl}" "Get remote WordPress siteurl for ${remote_path} installation")
    echo $remote_siteurl
  }
  local id=0
  local projects=$(jq -n '[]')
  local getRemoteWPinstallations="${SSH} \"${REMOTE_WP_CLI} find . --format=json \""
  local wp_installations=$(execSshReturn "${getRemoteWPinstallations}" "Get remote WordPress installations via WP-CLI find")
  for row in $(echo "${wp_installations}" | jq -r '.[] | @base64'); do
    _jq() {
     echo "${row}" | base64 --decode | jq -r "${1}"
    }
    fullPath=$(_jq '.version_path' | sed 's/wp-includes\/version.php//')
    version=$(_jq '.version')
    siteUrl=$(_getRemoteSiteUrl $fullPath)
    id=$((id+1))

    projects=$(echo $projects | jq \
      --argjson id "$id" \
      --arg siteUrl "$siteUrl" \
      --arg version "$version" \
      --arg fullPath "$fullPath" \
      '. += [{"id": $id, "siteUrl": $siteUrl, "version": $version, "fullPath": $fullPath}]')
  done
  echo $projects > ${BASE_DIR}/${WP_PROJECTS_LIST_JSON}
}

addVariable(){
  local var=$1
  local value=$2
  grep -q $var $WP_ENV || { echo "${var}=${value}" >> $WP_ENV; }
}

updateVariable(){
  local var=$1
  local value=$2
  grep -q $var $WP_ENV && { sed -i "s/${var}.*/${var}=${value}/" $WP_ENV; } || { echo "${var}=${value}" >> $WP_ENV; }
}

getArgFromJSON(){
  local key=$1
  local arg=$2
  local result=$(jq ".[] | select(.id == ${key}) | .${arg}" ${BASE_DIR}/${WP_PROJECTS_LIST_JSON} | tr -d '"')
  echo $result
}

createRemoteDbBackupWPCLI(){
  local project=$1;
  local db_backup="${REMOTE_DIR}/${DB_BACKUP}"
  local command="${SSH} \"${REMOTE_WP_CLI} db export $db_backup --path=${REMOTE_DIR}/\""
  local message="Creating database backup by WP CLI on remote host"
  execSshAction "$command" "$message"
}

createRemoteDbBackupWPT(){
  local project=$1;
  local command="${SSH} \"${WPT} --wp-cli -instance-id ${project}  -- db export ${DB_BACKUP}\""
  local message="Creating database backup by WP TOOLKIT on remote host"
  execSshAction "$command" "$message"
}

downloadProject(){
  local project=$1;
  rm -rf ${BACKUP_DIR}; mkdir -p ${BACKUP_DIR};
  rsync -e "sshpass -p ${SSH_PASSWORD} ssh -T -o StrictHostKeyChecking=no -p${SSH_PORT} -l ${SSH_USER}" \
    -Sa \
    ${SSH_HOST}:${REMOTE_DIR}/ /${BACKUP_DIR}/
}

syncContent(){
  local src=$1
  local dst=$2
  rm -rf $dst/{*,.*}; rsync -Sa --no-p --no-g --omit-dir-times --progress $src/ $dst/;
}

syncDB(){
  local backup=$1
  source ${WP_ENV}
  mysql -u${DB_USER} -p${DB_PASSWORD} -h${DB_HOST} ${DB_NAME} < $backup
}


getWPconfigVariable(){
  local var=$1
  local message="Getting $var from ${WP_CONFIG}"
  local command="${WP_CLI} config get ${var} --config-file=${WP_CONFIG} --quiet --path=${WEBROOT_DIR}"
  local result=$(execReturn "${command}" "${message}")
  echo $result
}

setWPconfigVariable(){
  local var=$1
  local value=$2
  local message="Updating $var in the ${WP_CONFIG}"
  local command="${WP_CLI} config set ${var} ${value} --config-file=${WP_CONFIG} --quiet --path=${WEBROOT_DIR}"
  execAction "${command}" "${message}"
}

getSiteUrl(){
  local message="Getting WordPress Site URL"
  local command="${WP_CLI} option get siteurl --path=${WEBROOT_DIR} --quiet --path=${WEBROOT_DIR}"
  local result=$(execReturn "${command}" "${message}")
  echo $result
}

updateSiteUrl(){
  local site_url=$1
  local message="Updating WordPress Site URL to ${site_url}"
  local command="${WP_CLI} option update siteurl ${site_url} --path=${WEBROOT_DIR} --quiet --path=${WEBROOT_DIR}"
  execAction "${command}" "${message}"
}

updateHomeUrl(){
  local home_url=$1
  local message="Updating WordPress Home to ${home_url}"
  local command="${WP_CLI} option update home ${home_url} --path=${WEBROOT_DIR} --quiet --path=${WEBROOT_DIR}"
  execAction "${command}" "${message}"
}

flushCache(){
  local message="Flushing caches"
  local command="${WP_CLI} cache flush --path=${WEBROOT_DIR} --quiet --path=${WEBROOT_DIR}"
  execAction "${command}" "${message}"
}


restoreWPconfig(){
  local message="Restoring ${WP_CONFIG}"
  local command="[ -f ${BASE_DIR}/wp-config.php ] && cat ${BASE_DIR}/wp-config.php > ${WP_CONFIG}"
  execAction "${command}" "${message}"
}

importProject(){
  for i in "$@"; do
    case $i in
      --instance-id=*)
      INSTANCE_ID=${i#*=}
      shift
      shift
      ;;
      *)
        ;;
    esac
  done

  source ${WP_ENV}
  SSH="timeout 300 sshpass -p ${SSH_PASSWORD} ssh -T -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_HOST} -p${SSH_PORT}"

  WPT=$(getWPtoolkitVersion)

  ### Restore original wp-config.php
  [ -f ${BASE_DIR}/wp-config.php ] && cat ${BASE_DIR}/wp-config.php > ${WP_CONFIG}

  ### Delete custom define wp-jelastic.php
  sed -i '/wp-jelastic.php/d' ${WP_CONFIG}

  createRemoteDbBackupWPT $INSTANCE_ID
  REMOTE_DIR=$(getArgFromJSON $INSTANCE_ID "fullPath")
  execAction "downloadProject $REMOTE_DIR" "Downloading $REMOTE_DIR from remote host to ${BACKUP_DIR}"
  addVariable DB_USER $(getWPconfigVariable DB_USER)
  addVariable DB_PASSWORD $(getWPconfigVariable DB_PASSWORD)
  addVariable DB_NAME $(getWPconfigVariable DB_NAME)
  addVariable DB_HOST $(getWPconfigVariable DB_HOST)
  addVariable SITE_URL $(getSiteUrl)
  execAction "syncContent ${BACKUP_DIR} ${WEBROOT_DIR}" "Sync content from ${BACKUP_DIR} to ${WEBROOT_DIR}"
  execAction "syncDB ${BACKUP_DIR}/${DB_BACKUP}" "Sync database from ${BACKUP_DIR}/${DB_BACKUP} "
  source ${WP_ENV}
  setWPconfigVariable DB_USER ${DB_USER}
  setWPconfigVariable DB_PASSWORD ${DB_PASSWORD}
  setWPconfigVariable DB_HOST ${DB_HOST}
  setWPconfigVariable DB_NAME ${DB_NAME}
  setWPconfigVariable WP_DEBUG "false"
  updateSiteUrl $SITE_URL
  updateHomeUrl $SITE_URL
  flushCache
  echo "{\"result\": 0}"
}

getProjectList(){
  for i in "$@"; do
    case $i in
      --format=*)
      FORMAT=${i#*=}
      shift
      shift
      ;;
      *)
        ;;
    esac
  done

  local project_list=$(cat ${BASE_DIR}/${WP_PROJECTS_LIST_JSON});
  if [[ "x${FORMAT}" == "xjson" ]]; then
    output="{\"result\": 0, \"projects\": ${project_list}}"
    echo $output
  else
    seperator=---------------------------------------------------------------------------------------------------
    rows="%-5s| %-50s| %-8s| %s\n"
    TableWidth=100

    printf "%-5s| %-50s| %-8s| %s\n" ID siteUrl version fullPath
    printf "%.${TableWidth}s\n" "$seperator"

    for row in $(echo "${project_list}" | jq -r '.[] | @base64'); do
      _jq() {
        echo "${row}" | base64 --decode | jq -r "${1}"
      }
      id=$(_jq '.id')
      fullPath=$(_jq '.fullPath')
      version=$(_jq '.version')
      siteUrl=$(_jq '.siteUrl')
      printf "$rows" "$id" "$siteUrl" "$version" "$fullPath"
    done
  fi
}

getProjectName(){
  for i in "$@"; do
    case $i in
      --instance-id=*)
      INSTANCE_ID=${i#*=}
      shift
      shift
      ;;
      *)
        ;;
    esac
  done

  projectName=$(getArgFromJSON $INSTANCE_ID "siteUrl")
  echo $projectName
}

checkSSHconnection(){
  local command="${SSH} \"exit 0\""
  local message="Checking SSH connection to remote host"
  action_to_base64=$(echo $command|base64 -w 0)
  stdout=$( { sh -c "$(echo ${action_to_base64}|base64 -d)"; } 2>&1 ) && { log "${message}...done"; } || {
    log "${message}...failed\n${stdout}\n";
    local output_json="{\"result\": ${AUTHORIZATION_ERROR_CODE}, \"out\": \"${message}...failed\"}"
    echo $output_json
    exit 0
  }
}

getRemoteProjects(){
  for i in "$@"; do
    case $i in
      --ssh-user=*)
      SSH_USER=${i#*=}
      shift
      shift
      ;;
      --ssh-password=*)
      SSH_PASSWORD=${i#*=}
      shift
      shift
      ;;
      --ssh-port=*)
      SSH_PORT=${i#*=}
      shift
      shift
      ;;
      --ssh-host=*)
      SSH_HOST=${i#*=}
      shift
      shift
      ;;
      --format=*)
      FORMAT=${i#*=}
      shift
      shift
      ;;
      *)
        ;;
    esac
  done

  updateVariable SSH_USER ${SSH_USER}
  updateVariable SSH_PASSWORD ${SSH_PASSWORD}
  updateVariable SSH_PORT ${SSH_PORT}
  updateVariable SSH_HOST ${SSH_HOST}
  source ${WP_ENV}
  SSH="timeout 300 sshpass -p ${SSH_PASSWORD} ssh -T -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_HOST} -p${SSH_PORT}"
  checkSSHconnection
  WPT=$(getWPtoolkitVersion)

  if [[ "$WPT" == *wp-toolkit* ]]; then
    getRemoteProjectListWPT
    updateVariable WPT ${WPT}
  else
    REMOTE_WP_CLI=$(installRemoteWP_CLI)
    updateVariable REMOTE_WP_CLI ${REMOTE_WP_CLI}
    getRemoteProjectListWP_CLI
  fi
  [[ "x${FORMAT}" == "xjson" ]] && { getProjectList --format=json; } || { getProjectList; }

}

### Backuping wp-config.php to /tmp/migrator/ dir
[ ! -f ${BASE_DIR}/wp-config.php \] && cp ${WP_CONFIG} ${BASE_DIR}

execAction "installWP_CLI" 'Install WP-CLI'

case ${1} in
    getRemoteProjects)
        getRemoteProjects "$@"
        ;;

    getProjectList)
      getProjectList "$@"
      ;;

    getProjectName)
      getProjectName "$@"
      ;;

    importProject)
      importProject "$@"
      ;;
esac
