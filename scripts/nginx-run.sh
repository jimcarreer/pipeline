source settings
mkdir -p $DOCKER_VOL/nginx/
mkdir -p $DOCKER_VOL/nginx/conf.d/
echo "server {
    listen               443 ssl;
    ssl_certificate      /etc/certs/nginx.crt;
    ssl_certificate_key  /etc/certs/nginx.key;
    ssl_protocols        TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers          HIGH:!aNULL:!MD5;
    location / {
        return 404;
    }
}" > $DOCKER_VOL/nginx/conf.d/0.default.conf
docker run --detach \
  --net $DOCKER_PIPELINE_NET \
  --net-alias nginx.$DOCKER_PIPELINE_DNSROOT \
  --publish 443:443 \
  --name nginx \
  --restart always \
  --volume $DOCKER_VOL/nginx/conf.d/:/etc/nginx/conf.d/:ro \
  --volume $DOCKER_PIPELINE_CERT:/etc/certs/nginx.crt:ro \
  --volume $DOCKER_PIPELINE_KEY:/etc/certs/nginx.key:ro \
  nginx
