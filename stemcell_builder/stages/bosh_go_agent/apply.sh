#!/usr/bin/env bash

set -e
base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash
source $base_dir/lib/prelude_bosh.bash

mkdir -p $chroot/etc/sv
cp -a $assets_dir/runit/agent $chroot/etc/sv/agent
cp -a $assets_dir/runit/monit $chroot/etc/sv/monit
mkdir -p $chroot/var/vcap/monit/svlog

# Set up agent and monit with runit
run_in_bosh_chroot $chroot "
chmod +x /etc/sv/agent/run /etc/sv/agent/log/run
rm -f /etc/service/agent
ln -s /etc/sv/agent /etc/service/agent

chmod +x /etc/sv/monit/run /etc/sv/monit/log/run
rm -f /etc/service/monit
ln -s /etc/sv/monit /etc/service/monit
"

# Alerts for monit config
cp -a $assets_dir/alerts.monitrc $chroot/var/vcap/monit/alerts.monitrc

cd $assets_dir
if is_ppc64le; then
  curl -L -o bosh-agent "https://s3.amazonaws.com/bosh-agent-binaries/bosh-agent-0.0.47-linux-ppc64le?versionId=Gt0zOPqKo8dGKIauoDhcgypAjRx5UhZq"
  echo "2d8c3654e6b5ca026245f80b8a00f0b610f9ca8b08795fb627a045cded52c8c5  bosh-agent" | shasum -a 256 -c -
else
  curl -L -o bosh-agent "https://s3.amazonaws.com/bosh-agent-binaries/bosh-agent-0.0.47-linux-amd64?versionId=ylNNhw.Pi2NH6IRsyzDHP148.OpsAV2f"
  echo "353909faeb0a8b8081d0e3c536fc0b770151a6a393e577d43bf1a2847a75c70e  bosh-agent" | shasum -a 256 -c -
fi
mv bosh-agent $chroot/var/vcap/bosh/bin/

cp $assets_dir/bosh-agent-rc $chroot/var/vcap/bosh/bin/bosh-agent-rc
cp $assets_dir/mbus/agent.{cert,key} $chroot/var/vcap/bosh/

# Download CLI source or release from github into assets directory
cd $assets_dir
rm -rf davcli
mkdir davcli
current_version=0.0.19
curl -L -o davcli/davcli https://s3.amazonaws.com/davcli/davcli-${current_version}-linux-amd64
echo "ee6163803fc6c3a2a8fa2be04d6800d796a21dfd davcli/davcli" | sha1sum -c -
mv davcli/davcli $chroot/var/vcap/bosh/bin/bosh-blobstore-dav
chmod +x $chroot/var/vcap/bosh/bin/bosh-blobstore-dav


chmod +x $chroot/var/vcap/bosh/bin/bosh-agent
chmod +x $chroot/var/vcap/bosh/bin/bosh-agent-rc
chmod +x $chroot/var/vcap/bosh/bin/bosh-blobstore-dav
chmod 600 $chroot/var/vcap/bosh/agent.key

# Setup additional permissions
run_in_chroot $chroot "
rm -f /etc/cron.deny
rm -f /etc/at.deny

chmod 0770 /var/lock
chown -h root:vcap /var/lock
chown -LR root:vcap /var/lock

echo 'vcap' > /etc/cron.allow
echo 'vcap' > /etc/at.allow

chmod -f og-rwx /etc/at.allow /etc/cron.allow /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d
chown -f root:root /etc/at.allow /etc/cron.allow /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d

chmod -R 0700 /etc/sv/agent
chown -R root:root /etc/sv/agent

# monit processes will inherit this directory as the default $PWD, so make sure processes can read/list
# some scripts/packages might do this during startup and would potentially fail
chmod -R 0755 /etc/sv/monit
chown -R root:root /etc/sv/monit

chmod 0600 /var/vcap/monit/alerts.monitrc
chown root:root /var/vcap/monit/alerts.monitrc
"

# Since go agent is always specified with -C provide empty conf.
# File will be overwritten in whole by infrastructures.
echo '{}' > $chroot/var/vcap/bosh/agent.json

# We need to capture ssh events
cp $assets_dir/rsyslog.d/10-auth_agent_forwarder.conf $chroot/etc/rsyslog.d/10-auth_agent_forwarder.conf

# this directory is utilized by the agent/init/create-env
# https://github.com/cloudfoundry/bosh-agent/blob/1a6b1e11acd941e65c4f4155c22ff9a8f76098f9/micro/https_handler.go#L119
mkdir -p $chroot/$bosh_dir/../micro_bosh/data/cache
