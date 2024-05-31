# Setup folders
# vi /scripts/stable_deploy.sh
echo "Starting release (no reboot)"
cd /
rm -r /apps/central_release
mkdir -p /apps/central_release
cd /apps/central_release

echo "Decompressing"
tar mxfz /releases/teiserver_stable.tar.gz

echo "Backup existing"
rm -rf /apps/central_backup
mv /apps/central /apps/central_backup

echo "Stopping service"
/apps/central_backup/bin/central stop
# Lets see if this allows us to restart faster
# sudo systemctl stop clustering.service

echo "Remove existing binary"
sudo rm -rf /apps/central

echo "Relocate binary"
cp -r opt/build/_build/prod/rel/central /apps

echo "Rotate logs"
rm /var/log/central/error_old.log
rm /var/log/central/info_old.log

cp /var/log/central/error.log /var/log/central/error_old.log
cp /var/log/central/info.log /var/log/central/info_old.log

echo "Reset logs"
> /var/log/central/error.log
> /var/log/central/info.log

# Reset permissions
sudo chown -R deploy:deploy /apps/central
sudo chown -R deploy:deploy /var/log/central

echo "Starting service"
sudo systemctl restart central.service

