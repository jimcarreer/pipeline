source settings
mkdir -p $DOCKER_VOL/artifactory
echo "server {
    listen              443 ssl;
    server_name         artifactory.$DOCKER_PIPELINE_DNSROOT;
    ssl_certificate     /etc/certs/nginx.crt;
    ssl_certificate_key /etc/certs/nginx.key;
    ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
       return 301 https://artifactory.$DOCKER_PIPELINE_DNSROOT/artifactory/webapp/;
    }

    location /artifactory {
        proxy_pass http://artifactory.internal:8081;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Artifactory-Override-Base-Url https://artifactory.$DOCKER_PIPELINE_DNSROOT/artifactory;
    }
}" > $DOCKER_VOL/nginx/conf.d/1.artifactory.conf
docker run --detach \
  --net $DOCKER_PIPELINE_NET \
  --net-alias artifactory.internal \
  --hostname artifactory.$DOCKER_PIPELINE_DNSROOT \
  --name artifactory \
  --restart always \
  --volume $DOCKER_VOL/artifactory:/var/opt/jfrog/artifactory \
  docker.bintray.io/jfrog/artifactory-oss:latest
docker restart nginx
