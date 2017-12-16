source settings
mkdir -p $DOCKER_VOL/gitlab
mkdir -p $DOCKER_VOL/gitlab/logs
mkdir -p $DOCKER_VOL/gitlab/data
echo "server {
    listen              443 ssl;
    server_name         gitlab.$DOCKER_PIPELINE_DNSROOT;
    ssl_certificate     /etc/certs/nginx.crt;
    ssl_certificate_key /etc/certs/nginx.key;
    ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    location / {
        proxy_pass http://gitlab.internal:80;
        proxy_set_header Host \$http_host;
    }
}" > $DOCKER_VOL/nginx/conf.d/1.gitlab.conf
docker run --detach \
  --env GITLAB_OMNIBUS_CONFIG="
        external_url 'https://gitlab.$DOCKER_PIPELINE_DNSROOT';
        gitlab_rails['gitlab_shell_ssh_host'] = 'gitlab.$DOCKER_PIPELINE_DNSROOT';
        gitlab_rails['gitlab_shell_ssh_port'] = 64022;
        nginx['listen_https'] = false;
        nginx['listen_port'] = 80;" \
  --net $DOCKER_PIPELINE_NET \
  --net-alias gitlab.internal \
  --hostname gitlab.$DOCKER_PIPELINE_DNSROOT \
  --publish 64022:22 \
  --name gitlab \
  --restart always \
  --volume $DOCKER_VOL/gitlab/config:/etc/gitlab \
  --volume $DOCKER_VOL/gitlab/logs:/var/log/gitlab \
  --volume $DOCKER_VOL/gitlab/data:/var/opt/gitlab \
  gitlab/gitlab-ce:latest
docker restart nginx
